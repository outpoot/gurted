extends Node

const ClientPool = preload("res://Scripts/ClientPool.gd")

func _ready():
	var timer = Timer.new()
	timer.wait_time = 10.0
	timer.autostart = true
	timer.timeout.connect(ClientPool._cleanup_idle_clients)
	add_child(timer)

func fetch_image(url: String) -> ImageTexture:
	if url.is_empty():
		return null
	
	var network_request = NetworkManager.start_request(url, "GET", false)
	
	var body: PackedByteArray
	var response_code: int
	var headers: PackedStringArray
	var response_headers = {}
	
	if url.begins_with("gurt://"):
		var gurt_body = await fetch_gurt_resource(url, true)
		if gurt_body.is_empty():
			return null
		
		body = gurt_body
		response_code = 200
		headers = PackedStringArray()
	else:
		# Handle HTTP/HTTPS URLs
		var http_request = HTTPRequest.new()
		add_child(http_request)
		
		var request_headers = PackedStringArray()
		request_headers.append("User-Agent: " + UserAgent.get_user_agent())
		
		var headers_dict = {}
		headers_dict["User-Agent"] = UserAgent.get_user_agent()
		NetworkManager.set_request_headers(network_request.id, headers_dict)
		
		var error = http_request.request(url, request_headers)
		if error != OK:
			print("Error making HTTP request: ", error)
			NetworkManager.fail_request(network_request.id, "HTTP request error: " + str(error))
			http_request.queue_free()
			return null
		
		var response = await http_request.request_completed
		
		var result = response[0]  # HTTPClient.Result
		response_code = response[1]  # int
		headers = response[2]  # PackedStringArray
		body = response[3]  # PackedByteArray
		
		http_request.queue_free()
		
		for header in headers:
			var parts = header.split(":", 1)
			if parts.size() == 2:
				response_headers[parts[0].strip_edges()] = parts[1].strip_edges()
		
		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			print("Failed to fetch image. Result: ", result, " Response code: ", response_code)
			NetworkManager.complete_request(network_request.id, response_code, "Request failed", response_headers, body.get_string_from_utf8(), body)
			return null
	
	NetworkManager.complete_request(network_request.id, response_code, "OK", response_headers, body.get_string_from_utf8(), body)
	
	# Get content type from headers
	var content_type = ""
	for header in headers:
		if header.to_lower().begins_with("content-type:"):
			content_type = header.split(":")[1].strip_edges().to_lower()
			break
	
	var image: Image = Image.new()
	var load_error
	
	# Load image based on content type
	if content_type.contains("jpeg") or content_type.contains("jpg") or url.to_lower().ends_with(".jpg") or url.to_lower().ends_with(".jpeg"):
		load_error = image.load_jpg_from_buffer(body)
	elif content_type.contains("png") or url.to_lower().ends_with(".png"):
		load_error = image.load_png_from_buffer(body)
	elif content_type.contains("webp") or url.to_lower().ends_with(".webp"):
		load_error = image.load_webp_from_buffer(body)
	elif content_type.contains("bmp"):
		load_error = image.load_bmp_from_buffer(body)
	elif content_type.contains("tga"):
		load_error = image.load_tga_from_buffer(body)
	else:
		print("Unknown or missing content-type. Attempting bruteforce converting across JPEG, PNG and WebP...")
		load_error = image.load_jpg_from_buffer(body)
		if load_error != OK:
			load_error = image.load_png_from_buffer(body)
			if load_error != OK:
				load_error = image.load_webp_from_buffer(body)
	
	if load_error != OK:
		print("Failed to load image from buffer. Content-Type: ", content_type, " Error: ", load_error)
		return null
	
	var texture = ImageTexture.create_from_image(image)
	
	return texture

func fetch_text(url: String) -> String:
	var http_request = HTTPRequest.new()
	add_child(http_request)
	
	if url.is_empty():
		http_request.queue_free()
		return ""
	
	var network_request = NetworkManager.start_request(url, "GET", false)
	
	var request_headers = PackedStringArray()
	request_headers.append("User-Agent: " + UserAgent.get_user_agent())
	
	var headers_dict = {}
	headers_dict["User-Agent"] = UserAgent.get_user_agent()
	NetworkManager.set_request_headers(network_request.id, headers_dict)
	
	var error = http_request.request(url, request_headers)
	if error != OK:
		print("Error making HTTP request for text resource: ", url, " Error: ", error)
		NetworkManager.fail_request(network_request.id, "HTTP request error: " + str(error))
		http_request.queue_free()
		return ""
	
	var response = await http_request.request_completed
	
	var result = response[0]  # HTTPClient.Result
	var response_code = response[1]  # int
	var headers = response[2]  # PackedStringArray
	var body = response[3]  # PackedByteArray
	
	http_request.queue_free()
	
	var response_headers = {}
	for header in headers:
		var parts = header.split(":", 1)
		if parts.size() == 2:
			response_headers[parts[0].strip_edges()] = parts[1].strip_edges()
	
	var response_body = body.get_string_from_utf8()
	
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		print("Failed to fetch text resource. URL: ", url, " Result: ", result, " Response code: ", response_code)
		NetworkManager.complete_request(network_request.id, response_code, "Request failed", response_headers, response_body)
		return ""
	
	NetworkManager.complete_request(network_request.id, response_code, "OK", response_headers, response_body)
	
	return response_body

func fetch_external_resource(url: String, base_url: String = "") -> String:
	var resolved_url = URLUtils.resolve_url(base_url, url)
	
	if resolved_url.begins_with("https://"):
		return await fetch_text(resolved_url)
	elif resolved_url.begins_with("gurt://"):
		return fetch_gurt_resource(resolved_url)
	else:
		print("Resource loading error: Only HTTPS and GURT protocols are supported. Attempted: ", resolved_url)
		return ""

func fetch_gurt_resource(url: String, as_binary: bool = false):
	if not GurtProtocol.is_gurt_domain(url):
		return PackedByteArray() if as_binary else ""
	
	var gurt_url = url
	if not gurt_url.begins_with("gurt://"):
		gurt_url = "gurt://" + gurt_url
	
	if gurt_url.contains("localhost"):
		gurt_url = gurt_url.replace("localhost", "127.0.0.1")
	
	var network_request = NetworkManager.start_request(gurt_url, "GET", false)
	
	var host_domain = ClientPool.extract_domain_from_url(gurt_url)

	var client = ClientPool.get_or_create_gurt_client(host_domain)
	if client == null:
		NetworkManager.fail_request(network_request.id, "Failed to create GURT client")
		return PackedByteArray() if as_binary else ""
	
	var response = client.request(gurt_url, {
		"method": "GET",
		"headers": {"Host": host_domain}
	})
	
	if not response or not response.is_success:
		var error_msg = "Failed to load GURT resource"
		var status_code = 0
		if response:
			status_code = response.status_code
			error_msg += ": " + str(response.status_code) + " " + response.status_message
		NetworkManager.complete_request(network_request.id, status_code, error_msg, {}, "")
		return PackedByteArray() if as_binary else ""
	
	var response_headers = response.headers if response.headers else {}
	
	var response_body = response.body
	
	if as_binary:
		var size_info = "Binary data: " + str(response_body.size()) + " bytes"
		NetworkManager.complete_request(network_request.id, response.status_code, "OK", response_headers, size_info, response_body)
		return response_body
	else:
		var response_body_str = response_body.get_string_from_utf8()
		NetworkManager.complete_request(network_request.id, response.status_code, "OK", response_headers, response_body_str)
		return response_body_str
