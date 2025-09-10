use crate::{
    config::GurtConfig, 
    handlers::{FileHandler, DirectoryHandler, DefaultFileHandler, DefaultDirectoryHandler},
    request_handler::{RequestHandler, RequestHandlerBuilder},
};
use gurtlib::prelude::*;
use std::{path::PathBuf, sync::Arc};

pub struct FileServerBuilder {
    config: GurtConfig,
    file_handler: Arc<dyn FileHandler>,
    directory_handler: Arc<dyn DirectoryHandler>,
}

impl FileServerBuilder {
    pub fn new(config: GurtConfig) -> Self {
        Self {
            config,
            file_handler: Arc::new(DefaultFileHandler),
            directory_handler: Arc::new(DefaultDirectoryHandler),
        }
    }

    pub fn with_file_handler<H: FileHandler + 'static>(mut self, handler: H) -> Self {
        self.file_handler = Arc::new(handler);
        self
    }

    pub fn with_directory_handler<H: DirectoryHandler + 'static>(mut self, handler: H) -> Self {
        self.directory_handler = Arc::new(handler);
        self
    }

    pub fn build(self) -> crate::Result<GurtServer> {
        let server = self.create_server()?;
        let request_handler = self.create_request_handler();
        let server_with_routes = self.add_routes(server, request_handler);
        Ok(server_with_routes)
    }

    fn create_server(&self) -> crate::Result<GurtServer> {
        match &self.config.tls {
            Some(tls) => {
                println!("TLS using certificate: {}", tls.certificate.display());
                GurtServerBuilder::new()
                    .with_tls_certificates(&tls.certificate, &tls.private_key)
                    .with_timeouts(
                        self.config.get_handshake_timeout(),
                        self.config.get_request_timeout(),
                        self.config.get_connection_timeout(),
                    )
                    .build()
            }
            None => {
                Err(crate::ServerError::TlsConfiguration(
                    "GURT protocol requires TLS encryption. Please provide --cert and --key parameters.".to_string()
                ))
            }
        }
    }

    fn create_request_handler(&self) -> RequestHandler {
        RequestHandlerBuilder::new(&*self.config.server.base_directory)
            .with_file_handler(DefaultFileHandler)
            .with_directory_handler(DefaultDirectoryHandler)
            .with_config(Arc::new(self.config.clone()))
            .build()
    }

    fn add_routes(self, server: GurtServer, request_handler: RequestHandler) -> GurtServer {
        let request_handler = Arc::new(request_handler);

        let server = server
            .get("/", {
                let handler = request_handler.clone();
                move |ctx| {
                    let handler = handler.clone();
                    let ctx_clone = ctx.clone();
                    async move {
                        handler.handle_root_request_with_context(ctx_clone).await
                    }
                }
            })
            .get("/*", {
                let handler = request_handler.clone();
                move |ctx| {
                    let handler = handler.clone();
                    let path = ctx.path().to_string();
                    let ctx_clone = ctx.clone();
                    async move {
                        handler.handle_file_request_with_context(&path, ctx_clone).await
                    }
                }
            });

        let server = server
            .post("/", {
                let handler = request_handler.clone();
                move |ctx| {
                    let handler = handler.clone();
                    let ctx_clone = ctx.clone();
                    async move {
                        handler.handle_method_request_with_context(ctx_clone).await
                    }
                }
            })
            .post("/*", {
                let handler = request_handler.clone();
                move |ctx| {
                    let handler = handler.clone();
                    let ctx_clone = ctx.clone();
                    async move {
                        handler.handle_method_request_with_context(ctx_clone).await
                    }
                }
            })
            .put("/", {
                let handler = request_handler.clone();
                move |ctx| {
                    let handler = handler.clone();
                    let ctx_clone = ctx.clone();
                    async move {
                        handler.handle_method_request_with_context(ctx_clone).await
                    }
                }
            })
            .put("/*", {
                let handler = request_handler.clone();
                move |ctx| {
                    let handler = handler.clone();
                    let ctx_clone = ctx.clone();
                    async move {
                        handler.handle_method_request_with_context(ctx_clone).await
                    }
                }
            })
            .delete("/", {
                let handler = request_handler.clone();
                move |ctx| {
                    let handler = handler.clone();
                    let ctx_clone = ctx.clone();
                    async move {
                        handler.handle_method_request_with_context(ctx_clone).await
                    }
                }
            })
            .delete("/*", {
                let handler = request_handler.clone();
                move |ctx| {
                    let handler = handler.clone();
                    let ctx_clone = ctx.clone();
                    async move {
                        handler.handle_method_request_with_context(ctx_clone).await
                    }
                }
            })
            .patch("/", {
                let handler = request_handler.clone();
                move |ctx| {
                    let handler = handler.clone();
                    let ctx_clone = ctx.clone();
                    async move {
                        handler.handle_method_request_with_context(ctx_clone).await
                    }
                }
            })
            .patch("/*", {
                let handler = request_handler.clone();
                move |ctx| {
                    let handler = handler.clone();
                    let ctx_clone = ctx.clone();
                    async move {
                        handler.handle_method_request_with_context(ctx_clone).await
                    }
                }
            })
            .options("/", {
                let handler = request_handler.clone();
                move |ctx| {
                    let handler = handler.clone();
                    let ctx_clone = ctx.clone();
                    async move {
                        handler.handle_method_request_with_context(ctx_clone).await
                    }
                }
            })
            .options("/*", {
                let handler = request_handler.clone();
                move |ctx| {
                    let handler = handler.clone();
                    let ctx_clone = ctx.clone();
                    async move {
                        handler.handle_method_request_with_context(ctx_clone).await
                    }
                }
            })
            .head("/", {
                let handler = request_handler.clone();
                move |ctx| {
                    let handler = handler.clone();
                    let ctx_clone = ctx.clone();
                    async move {
                        handler.handle_method_request_with_context(ctx_clone).await
                    }
                }
            })
            .head("/*", {
                let handler = request_handler.clone();
                move |ctx| {
                    let handler = handler.clone();
                    let ctx_clone = ctx.clone();
                    async move {
                        handler.handle_method_request_with_context(ctx_clone).await
                    }
                }
            });

        server
    }
}


pub struct GurtServerBuilder {
    cert_path: Option<PathBuf>,
    key_path: Option<PathBuf>,
    host: Option<String>,
    port: Option<u16>,
    handshake_timeout: Option<std::time::Duration>,
    request_timeout: Option<std::time::Duration>,
    connection_timeout: Option<std::time::Duration>,
}

impl GurtServerBuilder {
    pub fn new() -> Self {
        Self {
            cert_path: None,
            key_path: None,
            host: None,
            port: None,
            handshake_timeout: None,
            request_timeout: None,
            connection_timeout: None,
        }
    }

    pub fn with_tls_certificates<P: Into<PathBuf>>(mut self, cert_path: P, key_path: P) -> Self {
        self.cert_path = Some(cert_path.into());
        self.key_path = Some(key_path.into());
        self
    }

    pub fn with_host<S: Into<String>>(mut self, host: S) -> Self {
        self.host = Some(host.into());
        self
    }

    pub fn with_port(mut self, port: u16) -> Self {
        self.port = Some(port);
        self
    }

    pub fn with_timeouts(mut self, handshake_timeout: std::time::Duration, request_timeout: std::time::Duration, connection_timeout: std::time::Duration) -> Self {
        self.handshake_timeout = Some(handshake_timeout);
        self.request_timeout = Some(request_timeout);
        self.connection_timeout = Some(connection_timeout);
        self
    }

    pub fn build(self) -> crate::Result<GurtServer> {
        match (self.cert_path, self.key_path) {
            (Some(cert), Some(key)) => {
                let mut server = GurtServer::with_tls_certificates(
                    cert.to_str().ok_or_else(|| {
                        crate::ServerError::TlsConfiguration("Invalid certificate path".to_string())
                    })?,
                    key.to_str().ok_or_else(|| {
                        crate::ServerError::TlsConfiguration("Invalid key path".to_string())
                    })?
                ).map_err(crate::ServerError::from)?;
                
                if let (Some(handshake), Some(request), Some(connection)) = 
                    (self.handshake_timeout, self.request_timeout, self.connection_timeout) {
                    server = server.with_timeouts(handshake, request, connection);
                }
                
                Ok(server)
            }
            _ => {
                Err(crate::ServerError::TlsConfiguration(
                    "TLS certificates are required. Use with_tls_certificates() to provide them.".to_string()
                ))
            }
        }
    }
}

impl Default for GurtServerBuilder {
    fn default() -> Self {
        Self::new()
    }
}