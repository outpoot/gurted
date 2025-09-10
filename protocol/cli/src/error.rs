use std::fmt;

#[derive(Debug)]
pub enum ServerError {
    Io(std::io::Error),
    InvalidPath(String),
    InvalidConfiguration(String),
    TlsConfiguration(String),
    ServerStartup(String),
}

impl fmt::Display for ServerError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ServerError::Io(err) => write!(f, "I/O error: {}", err),
            ServerError::InvalidPath(path) => write!(f, "Invalid path: {}", path),
            ServerError::InvalidConfiguration(msg) => write!(f, "Configuration error: {}", msg),
            ServerError::TlsConfiguration(msg) => write!(f, "TLS configuration error: {}", msg),
            ServerError::ServerStartup(msg) => write!(f, "Server startup error: {}", msg),
        }
    }
}

impl std::error::Error for ServerError {}

impl From<std::io::Error> for ServerError {
    fn from(err: std::io::Error) -> Self {
        ServerError::Io(err)
    }
}

impl From<gurtlib::GurtError> for ServerError {
    fn from(err: gurtlib::GurtError) -> Self {
        ServerError::ServerStartup(err.to_string())
    }
}

pub type Result<T> = std::result::Result<T, ServerError>;
