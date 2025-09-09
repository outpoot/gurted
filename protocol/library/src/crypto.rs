use crate::{GurtError, Result};
use rustls::pki_types::{CertificateDer, PrivateKeyDer};
use rustls::{ClientConfig, ServerConfig};
use std::sync::Arc;
use tokio_rustls::{TlsAcceptor, TlsConnector};

pub const TLS_VERSION: &str = "TLS/1.3";
pub const GURT_ALPN: &[u8] = b"GURT/1.0";

#[derive(Debug, Clone)]
pub struct TlsConfig {
    pub client_config: Option<Arc<ClientConfig>>,
    pub server_config: Option<Arc<ServerConfig>>,
}

#[derive(Debug)]
pub struct DomainCertConfig {
    pub names: Vec<String>,
    pub cert_chain: Vec<CertificateDer<'static>>,
    pub private_key: Arc<PrivateKeyDer<'static>>,
}

impl TlsConfig {
    pub fn new_client() -> Result<Self> {
        let mut config =
            ClientConfig::builder().with_root_certificates(rustls::RootCertStore::empty()).with_no_client_auth();

        config.alpn_protocols = vec![GURT_ALPN.to_vec()];

        Ok(Self {
            client_config: Some(Arc::new(config)),
            server_config: None,
        })
    }

    pub fn new_server(
        cert_chain: Vec<CertificateDer<'static>>,
        private_key: PrivateKeyDer<'static>,
    ) -> Result<Self> {
        let mut config = ServerConfig::builder()
            .with_no_client_auth()
            .with_single_cert(cert_chain, private_key)
            .map_err(|e| GurtError::crypto(format!("TLS server config error: {}", e)))?;

        config.alpn_protocols = vec![GURT_ALPN.to_vec()];

        Ok(Self {
            client_config: None,
            server_config: Some(Arc::new(config)),
        })
    }

    pub fn new_server_multi(configs: Vec<DomainCertConfig>) -> Result<Self> {
        if configs.is_empty() {
            return Err(GurtError::crypto("No domain certificates provided"));
        }

        let mut resolver = rustls::server::ResolvesServerCertUsingSni::new();

        for domain_conf in configs {
            // use an Arc to clone the signing key
            let signing_key = rustls::crypto::aws_lc_rs::sign::any_supported_type(
                &domain_conf.private_key,
            )
                .map_err(|e| GurtError::crypto(format!("Invalid private key: {e}")))?;

            for name in &domain_conf.names {
                let certified_key = rustls::sign::CertifiedKey {
                    cert: domain_conf.cert_chain.clone(),
                    key: signing_key.clone(),
                    ocsp: None,
                };

                resolver
                    .add(name.as_str(), certified_key)
                    .map_err(|e| {
                        GurtError::crypto(format!("Failed to add cert for {name}: {e}"))
                    })?;
            }
        }

        let mut server_cfg = ServerConfig::builder()
            .with_no_client_auth()
            .with_cert_resolver(Arc::new(resolver));

        server_cfg.alpn_protocols = vec![GURT_ALPN.to_vec()];

        Ok(Self {
            client_config: None,
            server_config: Some(Arc::new(server_cfg)),
        })
    }

    pub fn get_connector(&self) -> Result<TlsConnector> {
        let config = self
            .client_config
            .as_ref()
            .ok_or_else(|| GurtError::crypto("No client config available"))?;
        Ok(TlsConnector::from(config.clone()))
    }

    pub fn get_acceptor(&self) -> Result<TlsAcceptor> {
        let config = self
            .server_config
            .as_ref()
            .ok_or_else(|| GurtError::crypto("No server config available"))?;
        Ok(TlsAcceptor::from(config.clone()))
    }
}

#[derive(Debug)]
pub struct CryptoManager {
    tls_config: Option<TlsConfig>,
}

impl CryptoManager {
    pub fn new() -> Self {
        Self { tls_config: None }
    }

    pub fn with_tls_config(config: TlsConfig) -> Self {
        Self {
            tls_config: Some(config),
        }
    }

    pub fn set_tls_config(&mut self, config: TlsConfig) {
        self.tls_config = Some(config);
    }

    pub fn has_tls_config(&self) -> bool {
        self.tls_config.is_some()
    }

    pub fn get_tls_connector(&self) -> Result<TlsConnector> {
        let config = self
            .tls_config
            .as_ref()
            .ok_or_else(|| GurtError::crypto("No TLS config available"))?;
        config.get_connector()
    }

    pub fn get_tls_acceptor(&self) -> Result<TlsAcceptor> {
        let config = self
            .tls_config
            .as_ref()
            .ok_or_else(|| GurtError::crypto("No TLS config available"))?;
        config.get_acceptor()
    }
}

impl Default for CryptoManager {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_tls_config_creation() {
        let client_config = TlsConfig::new_client();
        assert!(client_config.is_ok());

        let config = client_config.unwrap();
        assert!(config.client_config.is_some());
        assert!(config.server_config.is_none());
    }

    #[test]
    fn test_crypto_manager() {
        let crypto = CryptoManager::new();
        assert!(!crypto.has_tls_config());
    }
}