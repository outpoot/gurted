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
    
    #[error("Cancelled")]
    Cancelled,
}

pub type Result<T> = std::result::Result<T, GurtError>;