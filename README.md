# ExternEVM

**A custom EVM runtime with native external data access — from execution layer to consensus layer.**

> ExternEVM is a research blockchain protocol that embeds external API access directly into the EVM execution client, paired with a custom consensus layer implementing round-robin Proof of Authority over the Ethereum Engine API. Contracts call a native precompile. Validators fetch, commit, reveal, and verify external data at the protocol level — no oracles, no middleware.

---

## ⚠️ Experimental Protocol

ExternEVM is research software. The v3 multi-node devnet uses designated fetcher rotation with commit-reveal binding — one validator fetches per request, cryptographically committed before reveal, verified by all peers. The protocol roadmap progresses through stake-weighted consensus and TEE-assisted verification.

---

## Architecture Overview

ExternEVM is a two-component protocol following the post-merge Ethereum architecture ([EIP-3675](https://eips.ethereum.org/EIPS/eip-3675)):

```
┌──────────────────────────────────────────────────────────────────┐
│                      ExternEVM Protocol                           │
│                                                                   │
│  ┌───────────────────────┐    Engine API    ┌──────────────────┐ │
│  │   Execution Layer     │◄───(EIP-3675)───►│  Consensus Layer │ │
│  │   (Modified Reth)     │    JWT Auth      │                  │ │
│  │                       │   Port 8551      │  • Round-Robin   │ │
│  │  • API_CALL 0xAA      │                  │    PoA           │ │
│  │  • extern/1 p2p       │                  │  • Slot mgmt     │ │
│  │  • Protocol Store     │                  │  • Fork choice   │ │
│  │  • Designated Fetcher │                  │                  │ │
│  │  • Commit-Reveal      │                  │                  │ │
│  │  • In-block Cache     │                  │                  │ │
│  └──────────┬────────────┘                  └──────┬───────────┘ │
│             │ eth/68 + extern/1                     │            │
│             └──────────────┬──────────────────────┘             │
│                            │                                     │
│                    ┌───────▼────────┐                            │
│                    │  Peer Nodes    │                            │
│                    │  (same stack)  │                            │
│                    └────────────────┘                            │
└──────────────────────────────────────────────────────────────────┘
```

Each node runs two processes:

| Component | Binary | Role | Ports |
|-----------|--------|------|-------|
| Execution Layer | `reth` (modified) | Block execution, precompile, p2p commit-reveal exchange | 8545 (RPC), 8551 (Engine API), 30303 (p2p) |
| Consensus Layer | `externevm-consensus` | Block production, proposer selection, fork choice | — (connects to EL via Engine API) |

---

## What This Does

Solidity contracts on ExternEVM can call external APIs during execution:

```solidity
function getBitcoinPrice() external view returns (uint256) {
    ApiRequest memory req = ApiRequest({
        url: "https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=usd",
        method: "GET",
        headers: "",
        body: "",
        responsePath: "bitcoin.usd",
        responseType: 1
    });
    (bool ok, bytes memory out) = API_CALL.staticcall(abi.encode(req));
    require(ok, "API_CALL failed");
    return abi.decode(out, (uint256));
}
```

In a multi-node deployment, exactly one validator is designated to fetch per request (selected deterministically via `keccak256(requestHash) % validatorCount`). That validator commits a cryptographic hash of their answer before revealing it. All other validators verify the commitment matches the reveal. The verified value is returned to the contract — one API hit, cryptographic binding, no trust required in the fetcher.

---

## Protocol Stack

### Execution Layer — Modified Reth

Built on [Reth](https://github.com/paradigmxyz/reth) v2.2.0. Modifications are confined to four files in `reth-evm-ethereum`:

| File | Purpose |
|------|---------|
| `externevm.rs` | `ExternEvmFactory` — injects `API_CALL` precompile at `0xAA`. Implements designated fetcher selection, HTTP fetch via `reqwest::blocking` inside `tokio::task::block_in_place()`, commit-reveal broadcast, in-block cache, and non-fetcher reveal verification loop |
| `protocol_store.rs` | Thread-safe in-memory storage (`Arc<RwLock<>>` + `LazyLock` singleton) — validator registry, `ValidatorCommit` and `ValidatorReveal` structs with hash verification, in-block response cache keyed by `(requestHash, blockNumber)`, v2-compat submission infrastructure |
| `extern_proto.rs` | Three RLP-encoded wire message types (`ExternDataMsg`, `ExternCommitMsg`, `ExternRevealMsg`), three independent `tokio::sync::broadcast` channels (one per message type), type discriminant bytes `0x00/0x01/0x02`, deterministic `compute_request_hash()` |
| `extern_p2p.rs` | `ProtocolHandler` + `ConnectionHandler` + `Stream` impl — registers `extern/1` as a custom RLPx subprotocol, handles all three message types on inbound, fans out all three broadcast channels on outbound |

#### Precompile Interface

```
Address:  0x00000000000000000000000000000000000000AA
Name:     API_CALL
Gas:      100 (cache hit) / 3,000 (single-node) / 1,000 (non-fetcher verify) / 10,000 (fetcher fetch)
Input:    abi.encode(ApiRequest)
Output:   abi.encode(value) where value type depends on responseType
```

```solidity
struct ApiRequest {
    string url;            // Full URL — any public HTTP/HTTPS endpoint
    string method;         // "GET" or "POST"
    bytes headers;         // JSON-encoded headers or empty bytes
    bytes body;            // Request body for POST or empty
    string responsePath;   // Dot-notation JSON path — "bitcoin.usd", "properties.periods[0].temperature"
    uint8 responseType;    // 0=bytes, 1=uint256, 2=string, 3=bool
}
```

#### Safety Enforcement

| Check | Constraint |
|-------|-----------|
| URL scheme | `http://` or `https://` only |
| Private IPs | Blocks `127.0.0.0/8`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` |
| HTTP method | `GET` and `POST` only |
| Request body | ≤ 4,096 bytes |
| Response size | ≤ 32,768 bytes |
| HTTP timeout | 5,000 ms |
| Redirects | Blocked entirely |
| Response type | Must be 0–3 |

---

## v3 — Designated Fetcher Rotation + Commit-Reveal

v3 is the current protocol version on branch `externevm-v3`.

### The Problem v3 Solves

In v2, every validator independently fetches the same URL on every contract call. With N validators, one contract call generates N simultaneous HTTP requests to the same API endpoint. This breaks rate limits on paid APIs, burns through API quotas N times faster, and is architecturally redundant — all N nodes are fetching identical data.

v3 reduces this to exactly **one** HTTP request per contract call, regardless of validator count, while preserving cryptographic accountability via a commit-reveal scheme.

### Designated Fetcher Rotation

For each incoming API request, exactly one validator is designated as the fetcher. The designation is computed deterministically from the request hash — no election, no coordination, no additional messages:

```
requestHash = keccak256(url ‖ 0xFF ‖ method ‖ 0xFF ‖ responsePath ‖ 0xFF ‖ responseType)

fetcher_index = u64::from_be_bytes(requestHash[0..8]) % validator_count
designated_fetcher = validators[fetcher_index]
```

Every node independently computes the same `fetcher_index` given the same validator list. The separator byte `0xFF` prevents field boundary collisions (a path `"a"` + type `1` must not hash the same as path `"a1"` + type empty). Across many requests with uniformly distributed `requestHash` values, each validator is designated approximately `1/N` of the time.

### Commit-Reveal Protocol

The designated fetcher cannot simply broadcast their value openly — an open broadcast allows the fetcher to wait, observe network conditions, and selectively withhold or modify their answer.

Commit-reveal solves this with two properties:

**Hiding**: given a commitment `C = keccak256(value ‖ salt)`, an observer cannot determine `value` without knowing the 32-byte random `salt`. Brute-force is computationally infeasible.

**Binding**: once `C` is published, the fetcher cannot produce a different `value'` such that `keccak256(value' ‖ salt) == C` without breaking keccak256 preimage resistance.

#### Protocol flow (multi-node):

```
All nodes: compute requestHash, compute designate_fetcher(requestHash)

Designated fetcher:
  1. Perform HTTP call via reqwest::blocking inside tokio::task::block_in_place()
  2. Extract value at responsePath using dot-notation + array index parser
  3. ABI-encode value according to responseType
  4. Generate 32-byte cryptographically random salt via OsRng::fill_bytes()
  5. Compute commitment: C = keccak256(encoded_value ‖ salt)
  6. Store commit locally in protocol store
  7. Broadcast ExternCommitMsg { requestHash, commitment: C, validator } via extern/1
  8. Sleep EXTERNEVM_COMMIT_WINDOW_MS (default 200ms)
  9. Broadcast ExternRevealMsg { requestHash, value: encoded_value, salt, validator }
  10. Populate in-block cache: cache[(requestHash, blockNumber)] = encoded_value
  11. Return encoded_value to precompile caller

Non-fetchers (on receiving ExternCommitMsg):
  1. Store (requestHash, validator) → commitment in protocol store

Non-fetchers (on receiving ExternRevealMsg via extern_p2p.rs):
  1. Compute actual = keccak256(reveal.value ‖ reveal.salt)
  2. Retrieve stored commitment for (requestHash, reveal.validator)
  3. If actual == stored_commitment: store as verified reveal, populate cache
  4. If actual != stored_commitment: log commitment mismatch violation (v4: slashable)

Non-fetchers (in precompile, waiting for reveal):
  1. Poll get_verified_reveal(requestHash, designated) in 10ms intervals
  2. If verified reveal found: return it
  3. If deadline (commitWindow + revealWindow) exceeded: return error to contract
```

#### Wire protocol (extern/1 subprotocol):

Messages are prefixed with a 1-byte type discriminant before RLP-encoded payload:

```
0x00 ‖ RLP(ExternDataMsg)   — v2 compat (open value broadcast)
0x01 ‖ RLP(ExternCommitMsg) — v3 phase 1 (commitment)
0x02 ‖ RLP(ExternRevealMsg) — v3 phase 2 (reveal + salt)
```

The `extern/1` subprotocol is registered as a custom RLPx capability during the devp2p handshake. Peers that do not support it receive `OnNotSupported::KeepAlive` — connection is preserved, extern messages are simply not exchanged.

### In-Block Response Cache

If the same API endpoint is called multiple times within a single block (different transactions, same `requestHash`), the second and subsequent calls hit the in-block cache at 100 gas instead of triggering another fetch cycle. The cache is keyed by `(requestHash, blockNumber)` and evicted automatically at `current_block - 1` to bound memory usage.

```
cache_key = (keccak256(url ‖ 0xFF ‖ method ‖ 0xFF ‖ responsePath ‖ 0xFF ‖ responseType), blockNumber)

check_cache(key):
  hit  → return cached value at 100 gas
  miss → proceed to fetch/verify cycle
```

### Single-Node Fast Path

When `validator_count <= 1`, the commit-reveal overhead is skipped entirely. The node fetches, encodes, populates the cache, and returns immediately — behavior identical to v1/v2 single-node mode. No timing overhead, no broadcast messages.

### Gas Schedule (v3)

| Path | Gas | Condition |
|------|-----|-----------|
| Cache hit | 100 | Same `(requestHash, blockNumber)` seen before |
| Non-fetcher verify | 1,000 | Received and verified commit + reveal from designated fetcher |
| Fetcher fetch | 10,000 | This node is the designated fetcher, performs HTTP call |
| Single-node | 3,000 | Only one validator registered |

Gas costs are fixed placeholders. Dynamic metering based on response size and latency is planned for v4.

### Security Properties

**Fetch manipulation**: the fetcher is bound to their answer from the moment they broadcast the commitment. Changing their value between commit and reveal causes `keccak256(new_value ‖ salt) ≠ commitment` — the reveal is rejected by all peers.

**Free-riding**: a non-fetcher cannot skip the protocol. They wait for the designated fetcher's reveal. If they never receive one, the request times out and the contract call fails.

**Frontrunning**: commits are published before reveals. A non-fetcher who sees the commitment hash learns nothing about the underlying value — they cannot compute `value` from `C = keccak256(value ‖ salt)` without exhaustive search over the salt space.

**Rotation fairness**: over `R` requests, a Byzantine validator controls exactly `ceil(R/N)` fetch opportunities. They cannot concentrate their influence on high-value requests — the designation is determined by `keccak256(requestHash)`, which depends on the request parameters known only after the request is submitted.

---

## Consensus Layer — `externevm-consensus`

A standalone Rust binary implementing **Round-Robin Proof of Authority** over the Ethereum Engine API. Zero Reth dependencies — pure HTTP client using `reqwest` + `serde_json` + `jsonwebtoken`.

### Engine API Methods Used

| Method | Spec | Purpose |
|--------|------|---------|
| `engine_forkchoiceUpdatedV3` | [Cancun](https://github.com/ethereum/execution-apis/blob/main/src/engine/cancun.md#engine_forkchoiceupdatedv3) | Set chain head + trigger block building |
| `engine_getPayloadV3` | [Cancun](https://github.com/ethereum/execution-apis/blob/main/src/engine/cancun.md#engine_getpayloadv3) | Retrieve built block |
| `engine_newPayloadV3` | [Cancun](https://github.com/ethereum/execution-apis/blob/main/src/engine/cancun.md#engine_newpayloadv3) | Submit block for validation and execution |

Authentication uses HS256 JWT with `iat` claim, regenerated per request, validated against a shared 32-byte hex secret.

### Consensus Model

```
Slot time:     5 seconds (configurable via --slot-time)
Validator set: Fixed at startup via --validators flag
Selection:     Round-robin — proposer(slot) = validators[slot % count]
Finality:      Instant (PoA)
Fork choice:   Longest chain
```

### `ConsensusStrategy` Trait

```rust
pub trait ConsensusStrategy {
    fn proposer_for_slot(&self, slot: u64) -> String;
    fn is_my_turn(&self, slot: u64, my_address: &str) -> bool;
    fn validator_count(&self) -> usize;
}
```

v3 implements `RoundRobin`. v4 will implement `StakeWeighted`. Engine API layer never changes.

---

## Running the 3-Node Devnet

### Prerequisites

- Rust stable 1.80+
- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, cast)

### Build

```bash
git clone --recursive https://github.com/ExternEVM/ExternEVM.git
cd ExternEVM
cd reth && cargo build --release && cd ..
cd consensus && cargo build --release && cd ..
```

### Start devnet (automated)

```bash
./scripts/start-devnet.sh
```

### Deploy and test

```bash
./scripts/deploy-contract.sh
./scripts/test-api.sh
```

### Manual node startup

```bash
# Node 1 EL
EXTERNEVM_VALIDATOR_ADDRESS=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
EXTERNEVM_COMMIT_WINDOW_MS=200 \
EXTERNEVM_REVEAL_WINDOW_MS=200 \
cargo run --release -- node \
  --chain ../config/genesis.json \
  --http --http.api eth,net,web3,debug,trace,admin \
  --http.addr 0.0.0.0 --http.port 8545 \
  --authrpc.port 8551 --authrpc.jwtsecret ../config/jwt.hex \
  --port 30303 --datadir /tmp/externevm-node1
```

### Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `EXTERNEVM_VALIDATOR_ADDRESS` | `0xf39F...2266` | This node's validator identity |
| `EXTERNEVM_COMMIT_WINDOW_MS` | `200` | Time to wait after broadcasting commit before revealing |
| `EXTERNEVM_REVEAL_WINDOW_MS` | `200` | Time non-fetchers wait for reveal after commit window |

---

## Chain Configuration

| Parameter | Value |
|-----------|-------|
| Chain ID | `22042004` |
| Consensus | Round-Robin PoA (3 validators) |
| Slot Time | 5 seconds |
| Gas Limit | 30,000,000 |
| EVM Forks | All activated at genesis (Homestead → Cancun) |
| Precompile `0xAA` | API_CALL — external data access |

### Pre-funded Validator Accounts

| Validator | Address | Private Key |
|-----------|---------|-------------|
| Node 1 | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` | `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` |
| Node 2 | `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` | `0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d` |
| Node 3 | `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC` | `0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a` |

**Never use these keys with real funds.**

---

## Repo Structure

```
ExternEVM/
├── reth/                                    # Execution Layer (git submodule — modified Reth)
│   ├── crates/ethereum/evm/src/
│   │   ├── externevm.rs                     # ExternEvmFactory + API_CALL precompile (v3)
│   │   ├── protocol_store.rs                # Protocol store — commits, reveals, cache, validators
│   │   ├── extern_proto.rs                  # Wire messages + broadcast channels (3 types)
│   │   └── lib.rs                           # Module exports
│   └── bin/reth/src/
│       ├── main.rs                          # Node binary + subprotocol registration
│       └── extern_p2p.rs                    # ProtocolHandler + 3-message-type ConnectionHandler
│
├── consensus/                               # Consensus Layer (standalone binary)
│   └── src/
│       ├── main.rs                          # Slot loop + CLI
│       ├── engine_api.rs                    # Engine API client (JWT + 3 methods)
│       ├── jwt.rs                           # JWT token generation (HS256, iat)
│       ├── consensus.rs                     # ConsensusStrategy trait
│       ├── round_robin.rs                   # v3 round-robin PoA
│       └── types.rs                         # Engine API JSON wire types
│
├── contracts/
│   └── src/ExternApiDemo.sol                # Demo contract — getBitcoinPrice, getPeopleInSpace, getISSPosition
│
├── config/
│   ├── genesis.json                         # Chain genesis (ID 22042004, all forks active from block 0)
│   └── jwt.hex                              # Shared JWT secret (EL ↔ CL auth)
│
└── scripts/
    ├── start-devnet.sh                      # Start 3 EL + 3 CL nodes, auto peer discovery
    ├── stop-devnet.sh                       # Kill all devnet processes
    ├── deploy-contract.sh                   # Deploy ExternApiDemo, save address
    └── test-api.sh                          # Integration test — all functions, all 3 nodes
```

---

## References

| Specification | Relevance |
|---------------|-----------|
| [EIP-3675](https://eips.ethereum.org/EIPS/eip-3675) — The Merge | EL/CL separation architecture |
| [EIP-225](https://eips.ethereum.org/EIPS/eip-225) — Clique PoA | Round-robin proposer selection reference |
| [EIP-4399](https://eips.ethereum.org/EIPS/eip-4399) — PREVRANDAO | Post-merge randomness in payload attributes |
| [Engine API — Cancun](https://github.com/ethereum/execution-apis/blob/main/src/engine/cancun.md) | V3 Engine API methods |
| [Engine API — Auth](https://github.com/ethereum/execution-apis/blob/main/src/engine/authentication.md) | JWT authentication spec |
| [Chainlink Whitepaper v2](https://research.chain.link/whitepaper-v2.pdf) | Off-chain reporting (application-layer comparison) |
| [TLSNotary](https://tlsnotary.org/) | TLS proof of fetch (v5 reference) |
| [PBFT — Castro & Liskov](https://pmg.csail.mit.edu/papers/osdi99.pdf) | BFT quorum intersection (v4 reference) |

---

## License

MIT

---

*ExternEVM — protocol-level external data for smart contracts.*

Made with 💖 by Prateush Sharma
