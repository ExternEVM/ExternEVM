use jsonwebtoken::{encode, Algorithm, EncodingKey, Header};
use serde::Serialize;
use std::fs;
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Serialize)]
struct Claims {
    iat: u64,
}

pub fn read_jwt_secret(path: &str) -> Result<Vec<u8>, String> {
    let content = fs::read_to_string(Path::new(path))
        .map_err(|e| format!("Failed to read JWT secret from {}: {}", path, e))?;
    let hex_str = content.trim().strip_prefix("0x").unwrap_or(content.trim());
    hex::decode(hex_str).map_err(|e| format!("Invalid hex in JWT secret file: {}", e))
}

pub fn generate_jwt_token(secret: &[u8]) -> Result<String, String> {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| format!("System time error: {}", e))?;
    let claims = Claims { iat: now.as_secs() };
    let header = Header::new(Algorithm::HS256);
    let key = EncodingKey::from_secret(secret);
    encode(&header, &claims, &key).map_err(|e| format!("JWT encoding failed: {}", e))
}
