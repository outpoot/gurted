use gurtlib::{GurtServer, GurtResponse, ServerContext, Result};

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();
    
    let server = GurtServer::with_tls_certificates("cert.pem", "cert.key.pem")?
        .get("/", |_ctx: &ServerContext| async {
            Ok(GurtResponse::ok().with_string_body("<h1>Hello from GURT!</h1>"))
        })
        .get("/test", |_ctx: &ServerContext| async {
            Ok(GurtResponse::ok().with_string_body("Test endpoint working!"))
        });
    
    println!("Starting GURT server on gurt://127.0.0.1:4878");
    
    server.listen("127.0.0.1:4878").await
}