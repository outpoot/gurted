class_name ClientPool
extends RefCounted

static var gurt_clients: Dictionary = {}
static var client_last_used: Dictionary = {}
static var client_timeout_ms: int = 30000

static func _cleanup_idle_clients():
	var current_time = Time.get_ticks_msec()
	var to_remove = []

	for domain in client_last_used:
		if current_time - client_last_used[domain] > client_timeout_ms:
			to_remove.append(domain)

	for domain in to_remove:
		if gurt_clients.has(domain):
			gurt_clients[domain].disconnect()
			gurt_clients.erase(domain)
		client_last_used.erase(domain)

static func get_or_create_gurt_client(domain: String) -> GurtProtocolClient:
	_cleanup_idle_clients()

	if gurt_clients.has(domain):
		client_last_used[domain] = Time.get_ticks_msec()
		return gurt_clients[domain]

	var client = GurtProtocolClient.new()

	for ca_cert in CertificateManager.trusted_ca_certificates:
		client.add_ca_certificate(ca_cert)

	if not client.create_client_with_dns(30, GurtProtocol.DNS_SERVER_IP, GurtProtocol.DNS_SERVER_PORT):
		return null

	gurt_clients[domain] = client
	client_last_used[domain] = Time.get_ticks_msec()
	return client

static func extract_domain_from_url(gurt_url: String) -> String:
	var host_domain = gurt_url
	if host_domain.begins_with("gurt://"):
		host_domain = host_domain.right(-7)
	var slash_pos = host_domain.find("/")
	if slash_pos != -1:
		host_domain = host_domain.left(slash_pos)
	return host_domain