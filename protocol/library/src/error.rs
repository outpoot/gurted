// src/error.rs
use std::fmt;
use thiserror::Error;

#[derive(Error, Debug)]
pub enum GurtError {
    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),

    #[error("Cryptographic error: {0}")]
    Crypto(String),

    #[error("Protocol error: {0}")]
    Protocol(String),

    #[error("Invalid message format: {0}")]
    InvalidMessage(String),

    #[error("Connection error: {0}")]
    Connection(String),

    #[error("Handshake failed: {0}")]
    Handshake(String),

    #[error("Timeout error: {0}")]
    Timeout(String),

    #[error("Server error: {status} {message}")]
    Server { status: u16, message: String },

    #[error("Client error: {0}")]
    Client(String),
}

pub type Result<T> = std::result::Result<T, GurtError>;

impl GurtError {
    pub fn crypto<T: fmt::Display>(msg: T) -> Self {
        GurtError::Crypto(msg.to_string())
    }

    pub fn protocol<T: fmt::Display>(msg: T) -> Self {
        GurtError::Protocol(msg.to_string())
    }

    pub fn invalid_message<T: fmt::Display>(msg: T) -> Self {
        GurtError::InvalidMessage(msg.to_string())
    }

    pub fn connection<T: fmt::Display>(msg: T) -> Self {
        GurtError::Connection(msg.to_string())
    }

    pub fn handshake<T: fmt::Display>(msg: T) -> Self {
        GurtError::Handshake(msg.to_string())
    }

    pub fn timeout<T: fmt::Display>(msg: T) -> Self {
        GurtError::Timeout(msg.to_string())
    }

    pub fn server(status: u16, message: String) -> Self {
        GurtError::Server { status, message }
    }

    pub fn client<T: fmt::Display>(msg: T) -> Self {
        GurtError::Client(msg.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn basic_error_works() {
        let e = GurtError::protocol("oops");
        assert!(format!("{e}").contains("oops"));
    }
}