use super::{models::*, AppState};
use crate::auth::*;
use gurtlib::prelude::*;
use gurtlib::GurtStatusCode;
use sqlx::Row;
use chrono::Utc;

pub(crate) async fn register(ctx: &ServerContext, app_state: AppState) -> Result<GurtResponse> {
    let user: RegisterRequest = serde_json::from_slice(ctx.body())
        .map_err(|_| GurtError::invalid_message("Invalid JSON"))?;

    let registrations = 3; // New users get 3 registrations by default

    // Hash password
    let password_hash = match hash_password(&user.password) {
        Ok(hash) => hash,
        Err(_) => {
            return Ok(GurtResponse::internal_server_error().with_json_body(&Error {
                msg: "Failed to hash password",
                error: "HASH_ERROR".into(),
            })?);
        }
    };

    // Create user
    let user_result = sqlx::query(
        "INSERT INTO users (username, password_hash, registrations_remaining, domain_invite_codes) VALUES ($1, $2, $3, $4) RETURNING id"
    )
    .bind(&user.username)
    .bind(&password_hash)
    .bind(registrations)
    .bind(3) // Default 3 domain invite codes
    .fetch_one(&app_state.db)
    .await;

    match user_result {
        Ok(row) => {
            let user_id: i32 = row.get("id");

            // Generate JWT
            match generate_jwt(user_id, &user.username, &app_state.jwt_secret) {
                Ok(token) => {
                    let response = LoginResponse {
                        token,
                        user: UserInfo {
                            id: user_id,
                            username: user.username.clone(),
                            registrations_remaining: registrations,
                            domain_invite_codes: 3,
                            created_at: Utc::now(),
                        },
                    };
                    Ok(GurtResponse::ok().with_json_body(&response)?)
                }
                Err(_) => {
                    Ok(GurtResponse::internal_server_error().with_json_body(&Error {
                        msg: "Failed to generate token",
                        error: "JWT_ERROR".into(),
                    })?)
                }
            }
        }
        Err(e) => {
            if e.to_string().contains("duplicate key") {
                Ok(GurtResponse::bad_request().with_json_body(&Error {
                    msg: "Username already exists",
                    error: "DUPLICATE_USERNAME".into(),
                })?)
            } else {
                Ok(GurtResponse::internal_server_error().with_json_body(&Error {
                    msg: "Failed to create user",
                    error: e.to_string(),
                })?)
            }
        }
    }
}

pub(crate) async fn login(ctx: &ServerContext, app_state: AppState) -> Result<GurtResponse> {
    let body_bytes = ctx.body();
    
    let login_req: LoginRequest = serde_json::from_slice(body_bytes)
        .map_err(|e| {
            log::error!("JSON parse error: {}", e);
            GurtError::invalid_message("Invalid JSON")
        })?;

    // Find user
    let user_result = sqlx::query_as::<_, User>(
        "SELECT id, username, password_hash, registrations_remaining, domain_invite_codes, created_at FROM users WHERE username = $1"
    )
    .bind(&login_req.username)
    .fetch_optional(&app_state.db)
    .await;

    match user_result {
        Ok(Some(user)) => {
            // Verify password
            match verify_password(&login_req.password, &user.password_hash) {
                Ok(true) => {
                    // Generate JWT
                    match generate_jwt(user.id, &user.username, &app_state.jwt_secret) {
                        Ok(token) => {
                            let response = LoginResponse {
                                token,
                                user: UserInfo {
                                    id: user.id,
                                    username: user.username,
                                    registrations_remaining: user.registrations_remaining,
                                    domain_invite_codes: user.domain_invite_codes,
                                    created_at: user.created_at,
                                },
                            };
                            Ok(GurtResponse::ok().with_json_body(&response)?)
                        }
                        Err(_) => {
                            Ok(GurtResponse::internal_server_error().with_json_body(&Error {
                                msg: "Failed to generate token",
                                error: "JWT_ERROR".into(),
                            })?)
                        }
                    }
                }
                Ok(false) => {
                    Ok(GurtResponse::new(GurtStatusCode::Unauthorized).with_json_body(&Error {
                        msg: "Invalid credentials",
                        error: "INVALID_CREDENTIALS".into(),
                    })?)
                }
                Err(_) => {
                    Ok(GurtResponse::internal_server_error().with_json_body(&Error {
                        msg: "Password verification failed",
                        error: "PASSWORD_ERROR".into(),
                    })?)
                }
            }
        }
        Ok(None) => {
            Ok(GurtResponse::new(GurtStatusCode::Unauthorized).with_json_body(&Error {
                msg: "Invalid credentials",
                error: "INVALID_CREDENTIALS".into(),
            })?)
        }
        Err(_) => {
            Ok(GurtResponse::internal_server_error().with_json_body(&Error {
                msg: "Database error",
                error: "DATABASE_ERROR".into(),
            })?)
        }
    }
}

pub(crate) async fn get_user_info(_ctx: &ServerContext, app_state: AppState, claims: Claims) -> Result<GurtResponse> {
    let user_result = sqlx::query_as::<_, User>(
        "SELECT id, username, password_hash, registrations_remaining, domain_invite_codes, created_at FROM users WHERE id = $1"
    )
    .bind(claims.user_id)
    .fetch_optional(&app_state.db)
    .await;

    match user_result {
        Ok(Some(user)) => {
            let user_info = UserInfo {
                id: user.id,
                username: user.username,
                registrations_remaining: user.registrations_remaining,
                domain_invite_codes: user.domain_invite_codes,
                created_at: user.created_at,
            };
            Ok(GurtResponse::ok().with_json_body(&user_info)?)
        }
        Ok(None) => {
            Ok(GurtResponse::not_found().with_json_body(&Error {
                msg: "User not found",
                error: "USER_NOT_FOUND".into(),
            })?)
        }
        Err(_) => {
            Ok(GurtResponse::internal_server_error().with_json_body(&Error {
                msg: "Database error",
                error: "DATABASE_ERROR".into(),
            })?)
        }
    }
}

pub(crate) async fn create_invite(_ctx: &ServerContext, app_state: AppState, claims: Claims) -> Result<GurtResponse> {
    // Generate random invite code
    let invite_code: String = {
        use rand::Rng;
        let mut rng = rand::thread_rng();
        (0..12)
            .map(|_| {
                let chars = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
                chars[rng.gen_range(0..chars.len())] as char
            })
            .collect()
    };

    let mut tx = app_state.db.begin().await
        .map_err(|_| GurtError::invalid_message("Database error"))?;

    let affected_rows = sqlx::query("UPDATE users SET registrations_remaining = registrations_remaining - 1 WHERE id = $1 AND registrations_remaining > 0")
        .bind(claims.user_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| GurtError::invalid_message("Database error"))?
        .rows_affected();

    if affected_rows == 0 {
        return Ok(GurtResponse::bad_request().with_json_body(&Error {
            msg: "No registrations remaining to create invite",
            error: "INSUFFICIENT_REGISTRATIONS".into(),
        })?);
    }

    sqlx::query("INSERT INTO invite_codes (code, created_by, created_at) VALUES ($1, $2, $3)")
        .bind(&invite_code)
        .bind(claims.user_id)
        .bind(Utc::now())
        .execute(&mut *tx)
        .await
        .map_err(|_| GurtError::invalid_message("Database error"))?;

    match tx.commit().await {
        Ok(_) => {
            let response = serde_json::json!({
                "invite_code": invite_code
            });
            Ok(GurtResponse::ok().with_json_body(&response)?)
        }
        Err(_) => {
            Ok(GurtResponse::internal_server_error().with_json_body(&Error {
                msg: "Failed to create invite",
                error: "DATABASE_ERROR".into(),
            })?)
        }
    }
}

pub(crate) async fn redeem_invite(ctx: &ServerContext, app_state: AppState, claims: Claims) -> Result<GurtResponse> {
    let request: serde_json::Value = serde_json::from_slice(ctx.body())
        .map_err(|_| GurtError::invalid_message("Invalid JSON"))?;

    let invite_code = request["invite_code"].as_str()
        .ok_or(GurtError::invalid_message("Missing invite_code"))?;

    // Check if invite code exists and is not used
    let invite_result = sqlx::query_as::<_, InviteCode>(
        "SELECT id, code, created_by, used_by, created_at, used_at FROM invite_codes WHERE code = $1 AND used_by IS NULL"
    )
    .bind(invite_code)
    .fetch_optional(&app_state.db)
    .await;

    match invite_result {
        Ok(Some(invite)) => {
            // Mark invite as used and give user 3 additional registrations
            let mut tx = app_state.db.begin().await
                .map_err(|_| GurtError::invalid_message("Database error"))?;

            sqlx::query("UPDATE invite_codes SET used_by = $1, used_at = $2 WHERE id = $3")
                .bind(claims.user_id)
                .bind(Utc::now())
                .bind(invite.id)
                .execute(&mut *tx)
                .await
                .map_err(|_| GurtError::invalid_message("Database error"))?;

            sqlx::query("UPDATE users SET registrations_remaining = registrations_remaining + 1 WHERE id = $1")
                .bind(claims.user_id)
                .execute(&mut *tx)
                .await
                .map_err(|_| GurtError::invalid_message("Database error"))?;

            tx.commit().await
                .map_err(|_| GurtError::invalid_message("Database error"))?;

            let response = serde_json::json!({
                "registrations_added": 1
            });
            Ok(GurtResponse::ok().with_json_body(&response)?)
        }
        Ok(None) => {
            Ok(GurtResponse::bad_request().with_json_body(&Error {
                msg: "Invalid or already used invite code",
                error: "INVALID_INVITE".into(),
            })?)
        }
        Err(_) => {
            Ok(GurtResponse::internal_server_error().with_json_body(&Error {
                msg: "Database error",
                error: "DATABASE_ERROR".into(),
            })?)
        }
    }
}

pub(crate) async fn create_domain_invite(_ctx: &ServerContext, app_state: AppState, claims: Claims) -> Result<GurtResponse> {
    // Generate random domain invite code
    let invite_code: String = {
        use rand::Rng;
        let mut rng = rand::thread_rng();
        (0..12)
            .map(|_| {
                let chars = b"ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
                chars[rng.gen_range(0..chars.len())] as char
            })
            .collect()
    };

    // Insert domain invite code and decrease user's count
    let mut tx = app_state.db.begin().await
        .map_err(|_| GurtError::invalid_message("Database error"))?;

    let affected_rows = sqlx::query("UPDATE users SET domain_invite_codes = domain_invite_codes - 1 WHERE id = $1 AND domain_invite_codes > 0")
        .bind(claims.user_id)
        .execute(&mut *tx)
        .await
        .map_err(|_| GurtError::invalid_message("Database error"))?
        .rows_affected();

    if affected_rows == 0 {
        return Ok(GurtResponse::bad_request().with_json_body(&Error {
            msg: "No domain invite codes remaining",
            error: "NO_INVITES_REMAINING".into(),
        })?);
    }

    sqlx::query(
        "INSERT INTO domain_invite_codes (code, created_by, created_at) VALUES ($1, $2, $3)"
    )
    .bind(&invite_code)
    .bind(claims.user_id)
    .bind(Utc::now())
    .execute(&mut *tx)
    .await
    .map_err(|_| GurtError::invalid_message("Database error"))?;

    tx.commit().await
        .map_err(|_| GurtError::invalid_message("Database error"))?;

    let response = serde_json::json!({
        "domain_invite_code": invite_code
    });
    Ok(GurtResponse::ok().with_json_body(&response)?)
}

pub(crate) async fn redeem_domain_invite(ctx: &ServerContext, app_state: AppState, claims: Claims) -> Result<GurtResponse> {
    let request: serde_json::Value = serde_json::from_slice(ctx.body())
        .map_err(|_| GurtError::invalid_message("Invalid JSON"))?;

    let invite_code = request["domain_invite_code"].as_str()
        .ok_or(GurtError::invalid_message("Missing domain_invite_code"))?;

    // Check if domain invite code exists and is not used
    let invite_result = sqlx::query_as::<_, DomainInviteCode>(
        "SELECT id, code, created_by, used_by, created_at, used_at FROM domain_invite_codes WHERE code = $1 AND used_by IS NULL"
    )
    .bind(invite_code)
    .fetch_optional(&app_state.db)
    .await;

    match invite_result {
        Ok(Some(invite)) => {
            // Mark invite as used and give user 1 additional domain invite code
            let mut tx = app_state.db.begin().await
                .map_err(|_| GurtError::invalid_message("Database error"))?;

            sqlx::query("UPDATE domain_invite_codes SET used_by = $1, used_at = $2 WHERE id = $3")
                .bind(claims.user_id)
                .bind(Utc::now())
                .bind(invite.id)
                .execute(&mut *tx)
                .await
                .map_err(|_| GurtError::invalid_message("Database error"))?;

            sqlx::query("UPDATE users SET domain_invite_codes = domain_invite_codes + 1 WHERE id = $1")
                .bind(claims.user_id)
                .execute(&mut *tx)
                .await
                .map_err(|_| GurtError::invalid_message("Database error"))?;

            tx.commit().await
                .map_err(|_| GurtError::invalid_message("Database error"))?;

            let response = serde_json::json!({
                "domain_invite_codes_added": 1
            });
            Ok(GurtResponse::ok().with_json_body(&response)?)
        }
        Ok(None) => {
            Ok(GurtResponse::bad_request().with_json_body(&Error {
                msg: "Invalid or already used domain invite code",
                error: "INVALID_DOMAIN_INVITE".into(),
            })?)
        }
        Err(_) => {
            Ok(GurtResponse::internal_server_error().with_json_body(&Error {
                msg: "Database error",
                error: "DATABASE_ERROR".into(),
            })?)
        }
    }
}

#[derive(serde::Serialize)]
struct Error {
    msg: &'static str,
    error: String,
}