// src/lib.rs
pub mod client;
mod crypto;
mod error;
mod message;
mod protocol;
mod server;

pub use client::{GurtClient, GurtClientConfig};
pub use crypto::{
    CryptoManager, DomainCertConfig, GURT_ALPN, TLS_VERSION, TlsConfig,
};
pub use error::{GurtError, Result};
pub use message::{GurtMessage, GurtMethod, GurtRequest, GurtResponse};
pub use protocol::{GurtStatusCode, GURT_VERSION, DEFAULT_PORT};
pub use server::{
    DomainCertFile, GurtHandler, GurtServer, Route, ServerContext,
};

pub mod prelude {
    pub use crate::{
        CryptoManager, DomainCertConfig, DomainCertFile, GURT_ALPN, GURT_VERSION,
        GurtClient, GurtClientConfig, GurtError, GurtHandler, GurtMessage,
        GurtMethod, GurtRequest, GurtResponse, GurtServer, GurtStatusCode,
        Result, TlsConfig, TLS_VERSION, DEFAULT_PORT,
    };
}