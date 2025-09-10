use gurtlib::prelude::*;
use jsonwebtoken::{decode, encode, DecodingKey, EncodingKey, Header, Validation, Algorithm};
use serde::{Deserialize, Serialize};
use bcrypt::{hash, verify, DEFAULT_COST};
use std::time::{SystemTime, UNIX_EPOCH};
use chrono::{DateTime, Utc};

#[derive(Debug, Serialize, Deserialize)]
pub struct Claims {
    pub user_id: i32,
    pub username: String,
    pub exp: usize,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct RegisterRequest {
    pub username: String,
    pub password: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct LoginRequest {
    pub username: String,
    pub password: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct LoginResponse {
    pub token: String,
    pub user: UserInfo,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct UserInfo {
    pub id: i32,
    pub username: String,
    pub registrations_remaining: i32,
    pub domain_invite_codes: i32,
    pub created_at: DateTime<Utc>,
}

pub fn generate_jwt(user_id: i32, username: &str, secret: &str) -> std::result::Result<String, jsonwebtoken::errors::Error> {
    let expiration = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs() + 86400 * 7; // 7 days

    let claims = Claims {
        user_id,
        username: username.to_string(),
        exp: expiration as usize,
    };

    encode(&Header::default(), &claims, &EncodingKey::from_secret(secret.as_ref()))
}

pub fn validate_jwt(token: &str, secret: &str) -> std::result::Result<Claims, jsonwebtoken::errors::Error> {
    let mut validation = Validation::new(Algorithm::HS256);
    validation.validate_exp = true;
    
    decode::<Claims>(token, &DecodingKey::from_secret(secret.as_ref()), &validation)
        .map(|token_data| token_data.claims)
}

pub fn hash_password(password: &str) -> std::result::Result<String, bcrypt::BcryptError> {
    hash(password, DEFAULT_COST)
}

pub fn verify_password(password: &str, hash: &str) -> std::result::Result<bool, bcrypt::BcryptError> {
    verify(password, hash)
}

pub async fn jwt_middleware_gurt(ctx: &ServerContext, jwt_secret: &str) -> Result<Claims> {
    let start_time = std::time::Instant::now();
    log::info!("JWT middleware started for {} {}", ctx.method(), ctx.path());
    
    let auth_header = ctx.header("authorization")
        .or_else(|| ctx.header("Authorization"))
        .ok_or_else(|| {
            log::warn!("JWT middleware failed: Missing Authorization header in {:?}", start_time.elapsed());
            GurtError::invalid_message("Missing Authorization header")
        })?;

    if !auth_header.starts_with("Bearer ") {
        log::warn!("JWT middleware failed: Invalid header format in {:?}", start_time.elapsed());
        return Err(GurtError::invalid_message("Invalid Authorization header format"));
    }

    let token = &auth_header[7..]; // Remove "Bearer " prefix
    
    let result = validate_jwt(token, jwt_secret)
        .map_err(|e| GurtError::invalid_message(format!("Invalid JWT token: {}", e)));
        
    match &result {
        Ok(_) => log::info!("JWT middleware completed successfully in {:?}", start_time.elapsed()),
        Err(e) => log::warn!("JWT middleware failed: {} in {:?}", e, start_time.elapsed()),
    }
    
    result
}