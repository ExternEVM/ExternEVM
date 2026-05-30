use crate::jwt::generate_jwt_token;
use crate::types::*;
use serde_json::json;
use std::sync::atomic::{AtomicU64, Ordering};

static REQUEST_ID: AtomicU64 = AtomicU64::new(1);

fn next_id() -> u64 {
    REQUEST_ID.fetch_add(1, Ordering::SeqCst)
}

pub struct EngineApiClient {
    auth_url: String,
    rpc_url: String,
    jwt_secret: Vec<u8>,
    client: reqwest::Client,
}

impl EngineApiClient {
    pub fn new(auth_url: String, rpc_url: String, jwt_secret: Vec<u8>) -> Self {
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(10))
            .build()
            .expect("Failed to build HTTP client");
        Self { auth_url, rpc_url, jwt_secret, client }
    }

    async fn engine_rpc(
        &self,
        url: &str,
        method: &str,
        params: serde_json::Value,
    ) -> Result<serde_json::Value, String> {
        let token = generate_jwt_token(&self.jwt_secret)?;
        let body = json!({
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": next_id(),
        });

        let resp = self.client
            .post(url)
            .header("Content-Type", "application/json")
            .header("Authorization", format!("Bearer {}", token))
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("{} failed: {}", method, e))?;

        let status = resp.status();
        let text = resp.text().await
            .map_err(|e| format!("{} response read failed: {}", method, e))?;

        if !status.is_success() {
            return Err(format!("{} HTTP {}: {}", method, status, text));
        }

        let json: serde_json::Value = serde_json::from_str(&text)
            .map_err(|e| format!("{} JSON parse failed: {} — raw: {}", method, e, text))?;

        if let Some(err) = json.get("error") {
            return Err(format!("{} RPC error: {}", method, err));
        }

        Ok(json)
    }

    pub async fn forkchoice_updated_v3(
        &self,
        url: &str,
        head_hash: &str,
        safe_hash: &str,
        finalized_hash: &str,
        payload_attributes: Option<serde_json::Value>,
    ) -> Result<ForkchoiceUpdatedResult, String> {
        let forkchoice_state = json!({
            "headBlockHash": head_hash,
            "safeBlockHash": safe_hash,
            "finalizedBlockHash": finalized_hash,
        });
        let params = json!([forkchoice_state, payload_attributes]);
        let resp = self.engine_rpc(url, "engine_forkchoiceUpdatedV3", params).await?;
        let result: ForkchoiceUpdatedResult = serde_json::from_value(
            resp.get("result").ok_or("forkchoiceUpdatedV3: missing result field")?.clone(),
        ).map_err(|e| format!("forkchoiceUpdatedV3 parse error: {}", e))?;
        Ok(result)
    }

    pub async fn get_payload_v3(&self, payload_id: &str) -> Result<GetPayloadV3Result, String> {
        let params = json!([payload_id]);
        let resp = self.engine_rpc(&self.auth_url, "engine_getPayloadV3", params).await?;
        let result: GetPayloadV3Result = serde_json::from_value(
            resp.get("result").ok_or("getPayloadV3: missing result field")?.clone(),
        ).map_err(|e| format!("getPayloadV3 parse error: {}", e))?;
        Ok(result)
    }

    pub async fn new_payload_v3(
        &self,
        url: &str,
        execution_payload: &serde_json::Value,
        parent_beacon_block_root: &str,
    ) -> Result<PayloadStatusResult, String> {
        let versioned_hashes: Vec<String> = vec![];
        let params = json!([execution_payload, versioned_hashes, parent_beacon_block_root]);
        let resp = self.engine_rpc(url, "engine_newPayloadV3", params).await?;
        let result: PayloadStatusResult = serde_json::from_value(
            resp.get("result").ok_or("newPayloadV3: missing result field")?.clone(),
        ).map_err(|e| format!("newPayloadV3 parse error: {}", e))?;
        Ok(result)
    }

    pub async fn get_block_by_number(&self, block: &str) -> Result<BlockInfo, String> {
        let body = json!({
            "jsonrpc": "2.0",
            "method": "eth_getBlockByNumber",
            "params": [block, false],
            "id": next_id(),
        });
        let resp = self.client
            .post(&self.rpc_url)
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("eth_getBlockByNumber failed: {}", e))?;

        let json: serde_json::Value = resp.json().await
            .map_err(|e| format!("eth_getBlockByNumber parse failed: {}", e))?;

        if let Some(err) = json.get("error") {
            return Err(format!("eth_getBlockByNumber RPC error: {}", err));
        }

        let result: BlockInfo = serde_json::from_value(
            json.get("result").ok_or("eth_getBlockByNumber: missing result")?.clone(),
        ).map_err(|e| format!("eth_getBlockByNumber parse error: {}", e))?;
        Ok(result)
    }

    pub async fn local_forkchoice_updated(
        &self,
        head_hash: &str,
        safe_hash: &str,
        finalized_hash: &str,
        payload_attributes: Option<serde_json::Value>,
    ) -> Result<ForkchoiceUpdatedResult, String> {
        self.forkchoice_updated_v3(&self.auth_url, head_hash, safe_hash, finalized_hash, payload_attributes).await
    }
}
