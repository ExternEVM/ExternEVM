mod consensus;
mod engine_api;
mod jwt;
mod round_robin;
mod types;

use crate::consensus::ConsensusStrategy;
use crate::engine_api::EngineApiClient;
use crate::jwt::read_jwt_secret;
use crate::round_robin::RoundRobin;
use clap::Parser;
use sha2::{Digest, Sha256};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Parser, Debug)]
#[command(name = "externevm-consensus")]
struct Args {
    #[arg(long)]
    validator: String,

    #[arg(long, value_delimiter = ',')]
    validators: Vec<String>,

    #[arg(long, default_value = "http://127.0.0.1:8551")]
    el_auth_url: String,

    #[arg(long, default_value = "http://127.0.0.1:8545")]
    el_rpc_url: String,

    #[arg(long, value_delimiter = ',')]
    all_el_auth_urls: Vec<String>,

    #[arg(long, default_value = "../config/jwt.hex")]
    jwt_secret: String,

    #[arg(long, default_value = "5")]
    slot_time: u64,
}

fn slot_hash(prefix: &str, slot: u64) -> String {
    let mut hasher = Sha256::new();
    hasher.update(prefix.as_bytes());
    hasher.update(slot.to_be_bytes());
    format!("0x{}", hex::encode(hasher.finalize()))
}

fn hex_to_u64(s: &str) -> u64 {
    let s = s.strip_prefix("0x").unwrap_or(s);
    u64::from_str_radix(s, 16).unwrap_or(0)
}

fn u64_to_hex(v: u64) -> String {
    format!("0x{:x}", v)
}

#[tokio::main]
async fn main() {
    let args = Args::parse();

    eprintln!("╔══════════════════════════════════════════════════════╗");
    eprintln!("║        ExternEVM Consensus Layer v0.1.0             ║");
    eprintln!("║        Round-Robin PoA via Engine API               ║");
    eprintln!("╚══════════════════════════════════════════════════════╝");
    eprintln!();
    eprintln!("[CL] Validator:       {}", args.validator);
    eprintln!("[CL] Validator set:   {:?}", args.validators);
    eprintln!("[CL] Local EL auth:   {}", args.el_auth_url);
    eprintln!("[CL] Local EL RPC:    {}", args.el_rpc_url);
    eprintln!("[CL] All EL auth:     {:?}", args.all_el_auth_urls);
    eprintln!("[CL] Slot time:       {}s", args.slot_time);
    eprintln!();

    let jwt_secret = read_jwt_secret(&args.jwt_secret).expect("Failed to read JWT secret");
    eprintln!("[CL] JWT secret loaded from {}", args.jwt_secret);

    let engine = EngineApiClient::new(
        args.el_auth_url.clone(),
        args.el_rpc_url.clone(),
        jwt_secret.clone(),
    );

    let consensus = RoundRobin::new(args.validators.clone());
    eprintln!("[CL] Consensus: Round-Robin with {} validators", consensus.validator_count());

    eprintln!("[CL] Fetching genesis block from EL...");
    let genesis = loop {
        match engine.get_block_by_number("0x0").await {
            Ok(block) => break block,
            Err(e) => {
                eprintln!("[CL] Waiting for EL to be ready: {}", e);
                tokio::time::sleep(std::time::Duration::from_secs(2)).await;
            }
        }
    };

    let genesis_hash = genesis.hash.clone();
    let genesis_time = hex_to_u64(&genesis.timestamp);
    eprintln!("[CL] Genesis hash:    {}", genesis_hash);
    eprintln!("[CL] Genesis time:    {} (unix)", genesis_time);

    eprintln!("[CL] Initializing fork choice with genesis as head...");
    match engine.local_forkchoice_updated(&genesis_hash, &genesis_hash, &genesis_hash, None).await {
        Ok(result) => {
            eprintln!("[CL] Fork choice initialized: status={}", result.payload_status.status);
        }
        Err(e) => {
            eprintln!("[CL] WARNING: Fork choice init failed: {}", e);
        }
    }

    let mut current_head = genesis_hash.clone();
    let mut current_block_number: u64 = 0;

    eprintln!();
    eprintln!("[CL] ═══ Entering slot loop ═══");
    eprintln!();

    loop {
        let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs();
        let slot = if now > genesis_time { (now - genesis_time) / args.slot_time } else { 0 };
        let next_slot_time = genesis_time + (slot + 1) * args.slot_time;

        let proposer = consensus.proposer_for_slot(slot);
        let is_my_turn = consensus.is_my_turn(slot, &args.validator);

        if is_my_turn {
            eprintln!("[CL] Slot {} — I AM THE PROPOSER (block {})", slot, current_block_number + 1);

            match propose_block(&engine, &args, &jwt_secret, slot, &current_head, current_block_number).await {
                Ok((new_head, new_number)) => {
                    current_head = new_head;
                    current_block_number = new_number;
                    eprintln!("[CL] Block {} produced and submitted to all nodes", current_block_number);
                }
                Err(e) => {
                    eprintln!("[CL] MISSED SLOT {}: {}", slot, e);
                }
            }
        } else {
            eprintln!("[CL] Slot {} — proposer is {}... — waiting", slot, &proposer[..10.min(proposer.len())]);

            tokio::time::sleep(std::time::Duration::from_secs(args.slot_time.saturating_sub(1))).await;

            match engine.get_block_by_number("latest").await {
                Ok(block) => {
                    let block_num = hex_to_u64(&block.number);
                    if block_num > current_block_number {
                        eprintln!("[CL] Received block {} (hash: {}...)", block_num, &block.hash[..10.min(block.hash.len())]);
                        current_head = block.hash;
                        current_block_number = block_num;
                    }
                }
                Err(e) => {
                    eprintln!("[CL] Failed to poll latest block: {}", e);
                }
            }
        }

        let remaining = next_slot_time.saturating_sub(
            SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs()
        );
        if remaining > 0 {
            tokio::time::sleep(std::time::Duration::from_secs(remaining)).await;
        }
    }
}

async fn propose_block(
    engine: &EngineApiClient,
    args: &Args,
    jwt_secret: &[u8],
    slot: u64,
    current_head: &str,
    current_block_number: u64,
) -> Result<(String, u64), String> {
    let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs();
    let prev_randao = slot_hash("prevRandao", slot);
    let beacon_root = slot_hash("beaconRoot", slot);

    eprintln!("[CL]   Step 1: forkchoiceUpdated (start building)");
    let payload_attributes = serde_json::json!({
        "timestamp": u64_to_hex(now),
        "prevRandao": prev_randao,
        "suggestedFeeRecipient": args.validator,
        "withdrawals": [],
        "parentBeaconBlockRoot": beacon_root,
    });

    let fcu_result = engine.local_forkchoice_updated(
        current_head, current_head, current_head, Some(payload_attributes),
    ).await?;

    if fcu_result.payload_status.status != "VALID" {
        return Err(format!("forkchoiceUpdated returned {}: {:?}",
            fcu_result.payload_status.status, fcu_result.payload_status.validation_error));
    }

    let payload_id = fcu_result.payload_id
        .ok_or("forkchoiceUpdated did not return a payload_id")?;
    eprintln!("[CL]   Payload ID: {}", payload_id);

    eprintln!("[CL]   Step 2: Waiting 1s for block assembly...");
    tokio::time::sleep(std::time::Duration::from_secs(1)).await;

    eprintln!("[CL]   Step 3: getPayload");
    let payload_result = engine.get_payload_v3(&payload_id).await?;
    let execution_payload = &payload_result.execution_payload;

    let block_hash = execution_payload.get("blockHash")
        .and_then(|v| v.as_str())
        .ok_or("Execution payload missing blockHash")?
        .to_string();

    let block_number = execution_payload.get("blockNumber")
        .and_then(|v| v.as_str())
        .map(hex_to_u64)
        .unwrap_or(current_block_number + 1);

    eprintln!("[CL]   Block #{} hash: {}...{}", block_number,
        &block_hash[..10.min(block_hash.len())],
        &block_hash[block_hash.len().saturating_sub(6)..]);

    eprintln!("[CL]   Step 4: newPayload → {} EL nodes", args.all_el_auth_urls.len());
    for (i, el_url) in args.all_el_auth_urls.iter().enumerate() {
        let remote_engine = EngineApiClient::new(el_url.clone(), String::new(), jwt_secret.to_vec());
        match remote_engine.new_payload_v3(el_url, execution_payload, &beacon_root).await {
            Ok(status) => eprintln!("[CL]     Node {}: newPayload → {}", i + 1, status.status),
            Err(e) => eprintln!("[CL]     Node {}: newPayload FAILED: {}", i + 1, e),
        }
    }

    eprintln!("[CL]   Step 5: forkchoiceUpdated (set head) → {} EL nodes", args.all_el_auth_urls.len());
    for (i, el_url) in args.all_el_auth_urls.iter().enumerate() {
        let remote_engine = EngineApiClient::new(el_url.clone(), String::new(), jwt_secret.to_vec());
        match remote_engine.forkchoice_updated_v3(
            el_url, &block_hash, &block_hash, &block_hash, None,
        ).await {
            Ok(status) => eprintln!("[CL]     Node {}: forkchoiceUpdated → {}", i + 1, status.payload_status.status),
            Err(e) => eprintln!("[CL]     Node {}: forkchoiceUpdated FAILED: {}", i + 1, e),
        }
    }

    Ok((block_hash, block_number))
}
