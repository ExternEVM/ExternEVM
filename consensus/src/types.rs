use serde::{Deserialize, Serialize};

#[derive(Debug, Clone)]
pub struct ConsensusConfig {
    pub validator_address: String,
    pub validators: Vec<String>,
    pub slot_time_secs: u64,
    pub el_auth_url: String,
    pub all_el_auth_urls: Vec<String>,
    pub el_rpc_url: String,
    pub jwt_secret_path: String,
}

#[derive(Debug, Deserialize)]
pub struct JsonRpcResponse<T> {
    pub jsonrpc: String,
    pub id: u64,
    pub result: Option<T>,
    pub error: Option<JsonRpcError>,
}

#[derive(Debug, Deserialize)]
pub struct JsonRpcError {
    pub code: i64,
    pub message: String,
    pub data: Option<serde_json::Value>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ForkchoiceUpdatedResult {
    pub payload_status: PayloadStatusResult,
    pub payload_id: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PayloadStatusResult {
    pub status: String,
    pub latest_valid_hash: Option<String>,
    pub validation_error: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GetPayloadV3Result {
    pub execution_payload: serde_json::Value,
    pub block_value: Option<String>,
    pub blobs_bundle: Option<serde_json::Value>,
    pub should_override_builder: Option<bool>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BlockInfo {
    pub hash: String,
    pub number: String,
    pub timestamp: String,
}
