use anyhow::Result;
use openssl::pkey::PKey;
use openssl::rsa::Rsa;
use openssl::x509::X509Req;
use openssl::x509::X509Name;
use openssl::hash::MessageDigest;

pub fn generate_ca_cert() -> Result<(String, String)> {
    let rsa = Rsa::generate(4096)?;
    let ca_key = PKey::from_rsa(rsa)?;
    
    let mut name_builder = X509Name::builder()?;
    name_builder.append_entry_by_text("C", "US")?;
    name_builder.append_entry_by_text("O", "Gurted Network")?;
    name_builder.append_entry_by_text("CN", "Gurted Root CA")?;
    let ca_name = name_builder.build();
    
    let mut cert_builder = openssl::x509::X509::builder()?;
    cert_builder.set_version(2)?;
    cert_builder.set_subject_name(&ca_name)?;
    cert_builder.set_issuer_name(&ca_name)?;
    cert_builder.set_pubkey(&ca_key)?;
    
    // validity period (10 years)
    let not_before = openssl::asn1::Asn1Time::days_from_now(0)?;
    let not_after = openssl::asn1::Asn1Time::days_from_now(3650)?;
    cert_builder.set_not_before(&not_before)?;
    cert_builder.set_not_after(&not_after)?;
    
    let serial = openssl::bn::BigNum::from_u32(1)?.to_asn1_integer()?;
    cert_builder.set_serial_number(&serial)?;
    
    let basic_constraints = openssl::x509::extension::BasicConstraints::new()
        .critical()
        .ca()
        .build()?;
    cert_builder.append_extension(basic_constraints)?;
    
    let key_usage = openssl::x509::extension::KeyUsage::new()
        .critical()
        .key_cert_sign()
        .crl_sign()
        .build()?;
    cert_builder.append_extension(key_usage)?;
    
    cert_builder.sign(&ca_key, MessageDigest::sha256())?;
    let ca_cert = cert_builder.build();
    
    let ca_key_pem = ca_key.private_key_to_pem_pkcs8()?;
    let ca_cert_pem = ca_cert.to_pem()?;
    
    Ok((
        String::from_utf8(ca_key_pem)?,
        String::from_utf8(ca_cert_pem)?
    ))
}

pub fn sign_csr_with_ca(
    csr_pem: &str,
    ca_cert_pem: &str,
    ca_key_pem: &str,
    domain: &str,
    client_ip: Option<&str>
) -> Result<String> {
    let ca_cert = openssl::x509::X509::from_pem(ca_cert_pem.as_bytes())?;
    let ca_key = PKey::private_key_from_pem(ca_key_pem.as_bytes())?;
    
    let csr = X509Req::from_pem(csr_pem.as_bytes())?;
    
    let mut cert_builder = openssl::x509::X509::builder()?;
    cert_builder.set_version(2)?;
    cert_builder.set_subject_name(csr.subject_name())?;
    cert_builder.set_issuer_name(ca_cert.subject_name())?;
    cert_builder.set_pubkey(csr.public_key()?.as_ref())?;
    
    // validity period (90 days)
    let not_before = openssl::asn1::Asn1Time::days_from_now(0)?;
    let not_after = openssl::asn1::Asn1Time::days_from_now(90)?;
    cert_builder.set_not_before(&not_before)?;
    cert_builder.set_not_after(&not_after)?;
    
    let mut serial = openssl::bn::BigNum::new()?;
    serial.rand(128, openssl::bn::MsbOption::MAYBE_ZERO, false)?;
    let asn1_serial = serial.to_asn1_integer()?;
    cert_builder.set_serial_number(&asn1_serial)?;
    
    let context = cert_builder.x509v3_context(Some(&ca_cert), None);
    
    let mut san_builder = openssl::x509::extension::SubjectAlternativeName::new();
    san_builder
        .dns(domain)
        .dns("localhost")
        .ip("127.0.0.1");
    
    if let Some(ip) = client_ip {
        if is_valid_ip(ip) && ip != "127.0.0.1" {
            san_builder.ip(ip);
            println!("Added client IP {} to certificate for {}", ip, domain);
        }
    }
    
    let subject_alt_name = san_builder.build(&context)?;
    cert_builder.append_extension(subject_alt_name)?;
    
    let key_usage = openssl::x509::extension::KeyUsage::new()
        .critical()
        .digital_signature()
        .key_encipherment()
        .build()?;
    cert_builder.append_extension(key_usage)?;
    
    let ext_key_usage = openssl::x509::extension::ExtendedKeyUsage::new()
        .server_auth()
        .client_auth()
        .build()?;
    cert_builder.append_extension(ext_key_usage)?;
    
    cert_builder.sign(&ca_key, MessageDigest::sha256())?;
    let cert = cert_builder.build();
    
    let cert_pem = cert.to_pem()?;
    Ok(String::from_utf8(cert_pem)?)
}


fn is_valid_ip(ip: &str) -> bool {
    ip.split('.')
        .count() == 4
        && ip.split('.')
            .all(|part| part.parse::<u8>().is_ok())
}
