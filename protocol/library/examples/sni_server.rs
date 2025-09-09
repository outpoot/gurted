// examples/mail_search_server.rs
use gurt::{GurtResponse, GurtServer, Result, ServerContext, DomainCertFile};

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();

    // Replace with paths to *real certificates and keys* you provisioned
    // with your custom CA for each domain.
    //
    // Example: using mkcert or your gurtca tool to issue certs for ma.il and sear.ch
    let certs = vec![
        DomainCertFile {
            names: vec!["ma.il".into()],
            cert_path: "./certs/ma.il.crt".into(),
            key_path: "./certs/ma.il.key".into(),
        },
        DomainCertFile {
            names: vec!["sear.ch".into()],
            cert_path: "./certs/sear.ch.crt".into(),
            key_path: "./certs/sear.ch.key".into(),
        },
    ];

    let server = GurtServer::with_tls_certificates_multi(certs)?
        // Global route: fallback if host not matched
        .get("/", |_ctx: &ServerContext| async {
            Ok(GurtResponse::ok().with_string_body("<h1>Global landing</h1>"))
        })
        // ma.il routes
        .get_host("ma.il", "/", |_ctx: &ServerContext| async {
            Ok(GurtResponse::ok().with_string_body("<h1>📬 Welcome to ma.il</h1>"))
        })
        .get_host("ma.il", "/inbox", |_ctx: &ServerContext| async {
            Ok(GurtResponse::ok().with_string_body("<h1>Your Inbox</h1>"))
        })
        .get_host("ma.il", "/send", |_ctx: &ServerContext| async {
            Ok(GurtResponse::ok().with_string_body("<h1>Compose a new message</h1>"))
        })
        // sear.ch routes
        .get_host("sear.ch", "/", |_ctx: &ServerContext| async {
            Ok(GurtResponse::ok().with_string_body("<h1>🔎 Welcome to sear.ch</h1>"))
        })
        .get_host("sear.ch", "/query", |_ctx: &ServerContext| async {
            Ok(GurtResponse::ok().with_string_body("<h1>Search results</h1>"))
        });

    println!("Starting multi-host GURT server on gurt://0.0.0.0:4878");
    server.listen("0.0.0.0:4878").await
}