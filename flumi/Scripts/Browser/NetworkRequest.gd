class_name NetworkRequest
extends RefCounted

enum RequestType {
	FETCH,
	DOC,
	CSS,
	LUA,
	FONT,
	IMG,
	SOCKET,
	OTHER
}

enum RequestStatus {
	PENDING,
	SUCCESS,
	ERROR,
	CANCELLED
}

var id: String
var name: String
var url: String
var method: String
var type: RequestType
var status: RequestStatus
var status_code: int
var status_text: String
var size: int
var time_ms: float
var start_time: float
var end_time: float

var request_headers: Dictionary = {}
var response_headers: Dictionary = {}

var request_body: String = ""
var response_body: String = ""
var response_body_bytes: PackedByteArray = []

var mime_type: String = ""
var is_from_lua: bool = false

var websocket_id: String = ""
var websocket_event_type: String = "" # "connection", "close", "error"
var connection_status: String = "" # "connecting", "open", "closing", "closed"
var websocket_messages: Array[WebSocketMessage] = []

class WebSocketMessage:
	var hour: int
	var minute: int
	var second: int
	var direction: String # "sent" or "received"
	var content: String
	var size: int

	func _init(dir: String, msg: String):
		var local_time = Time.get_datetime_dict_from_system(false)
		hour = local_time.hour
		minute = local_time.minute
		second = local_time.second
		direction = dir
		content = msg
		size = msg.length()

	func get_formatted_time() -> String:
		return "%02d:%02d:%02d" % [hour, minute, second]

func _init(request_url: String = "", request_method: String = "GET"):
	id = generate_id()
	url = request_url
	method = request_method.to_upper()
	name = extract_name_from_url(url)
	type = determine_type_from_url(url)
	status = RequestStatus.PENDING
	status_code = 0
	status_text = ""
	size = 0
	time_ms = 0.0
	start_time = Time.get_ticks_msec()
	end_time = 0.0

func generate_id() -> String:
	return str(Time.get_ticks_msec()) + "_" + str(randi())

func extract_name_from_url(request_url: String) -> String:
	if request_url.is_empty():
		return "Unknown"

	if request_url.begins_with("ws://") or request_url.begins_with("wss://"):
		if not websocket_event_type.is_empty():
			match websocket_event_type:
				"connection":
					return "WebSocket"
				"close":
					return "WebSocket Close"
				"error":
					return "WebSocket Error"
	
	var parts = request_url.split("/")
	if parts.size() > 0:
		var filename = parts[-1]
		if filename.is_empty() and parts.size() > 1:
			filename = parts[-2]
		if "?" in filename:
			filename = filename.split("?")[0]
		if "#" in filename:
			filename = filename.split("#")[0]
		return filename if not filename.is_empty() else "/"
	
	return request_url

func determine_type_from_url(request_url: String) -> RequestType:
	var lower_url = request_url.to_lower()
	
	if lower_url.ends_with(".html") or lower_url.ends_with(".htm"):
		return RequestType.DOC
	elif lower_url.ends_with(".css"):
		return RequestType.CSS
	elif lower_url.ends_with(".lua") or lower_url.ends_with(".luau"):
		return RequestType.LUA
	elif lower_url.ends_with(".woff") or lower_url.ends_with(".woff2") or lower_url.ends_with(".ttf") or lower_url.ends_with(".otf"):
		return RequestType.FONT
	elif lower_url.ends_with(".png") or lower_url.ends_with(".jpg") or lower_url.ends_with(".jpeg") or lower_url.ends_with(".gif") or lower_url.ends_with(".webp") or lower_url.ends_with(".svg") or lower_url.ends_with(".bmp"):
		return RequestType.IMG
	elif lower_url.begins_with("ws://") or lower_url.begins_with("wss://"):
		return RequestType.SOCKET
	
	if not mime_type.is_empty():
		var lower_mime = mime_type.to_lower()
		if lower_mime.begins_with("text/html"):
			return RequestType.DOC
		elif lower_mime.begins_with("text/css"):
			return RequestType.CSS
		elif lower_mime.begins_with("image/"):
			return RequestType.IMG
		elif lower_mime.begins_with("font/") or lower_mime == "application/font-woff" or lower_mime == "application/font-woff2":
			return RequestType.FONT
	
	if is_from_lua:
		return RequestType.FETCH
	
	return RequestType.OTHER

func set_response(response_status_code: int, response_status_text: String, response_headers_dict: Dictionary, response_body_content: String, body_bytes: PackedByteArray = []):
	end_time = Time.get_ticks_msec()
	time_ms = end_time - start_time
	
	status_code = response_status_code
	status_text = response_status_text
	response_headers = response_headers_dict
	response_body = response_body_content
	response_body_bytes = body_bytes if not body_bytes.is_empty() else response_body_content.to_utf8_buffer()
	size = response_body_bytes.size()
	
	for header_name in response_headers:
		if header_name.to_lower() == "content-type":
			mime_type = response_headers[header_name].split(";")[0].strip_edges()
			break
	
	type = determine_type_from_url(url)
	
	if response_status_code >= 200 and response_status_code < 300:
		status = RequestStatus.SUCCESS
	else:
		status = RequestStatus.ERROR

func set_error(error_message: String):
	end_time = Time.get_ticks_msec()
	time_ms = end_time - start_time
	status = RequestStatus.ERROR
	status_text = error_message

func get_status_display() -> String:
	match status:
		RequestStatus.PENDING:
			return "Pending"
		RequestStatus.SUCCESS:
			return str(status_code)
		RequestStatus.ERROR:
			return str(status_code) if status_code > 0 else "Failed"
		RequestStatus.CANCELLED:
			return "Cancelled"
		_:
			return "Unknown"

func get_type_display() -> String:
	match type:
		RequestType.FETCH:
			return "Fetch"
		RequestType.DOC:
			return "Doc"
		RequestType.CSS:
			return "CSS"
		RequestType.LUA:
			return "Lua"
		RequestType.FONT:
			return "Font"
		RequestType.IMG:
			return "Img"
		RequestType.SOCKET:
			return "Socket"
		RequestType.OTHER:
			return "Other"
		_:
			return "Unknown"

static func format_bytes(given_size: int) -> String:
	if given_size < 1024:
		return str(given_size) + " B"
	elif given_size < 1024 * 1024:
		return str(given_size / 1024) + " KB"
	else:
		return str(given_size / (1024.0 * 1024)) + " MB"

func get_time_display() -> String:
	if status == RequestStatus.PENDING:
		return "Pending"
	if time_ms < 1000:
		return str(int(time_ms)) + " ms"
	else:
		return "%.1f s" % (time_ms / 1000.0)

func get_icon_texture() -> Texture2D:
	match type:
		RequestType.FETCH:
			return load("res://Assets/Icons/download.svg")
		RequestType.DOC:
			return load("res://Assets/Icons/file-text.svg")
		RequestType.CSS:
			return load("res://Assets/Icons/palette.svg")
		RequestType.LUA:
			return load("res://Assets/Icons/braces.svg")
		RequestType.FONT:
			return load("res://Assets/Icons/braces.svg")
		RequestType.IMG:
			return load("res://Assets/Icons/image.svg")
		RequestType.SOCKET:
			return load("res://Assets/Icons/arrow-down-up.svg")
		_:
			return load("res://Assets/Icons/search.svg")

static func create_websocket_connection(ws_url: String, ws_id: String) -> NetworkRequest:
	var request = NetworkRequest.new(ws_url, "WS")
	request.type = RequestType.SOCKET
	request.websocket_id = ws_id
	request.websocket_event_type = "connection"
	request.connection_status = "connecting"
	request.is_from_lua = true
	return request

func add_websocket_message(direction: String, message: String):
	var ws_message = WebSocketMessage.new(direction, message)
	websocket_messages.append(ws_message)
	
	var total_message_size = 0
	for msg in websocket_messages:
		total_message_size += msg.size
	size = total_message_size

func update_websocket_status(new_status: String, status_code: int = 200, status_text: String = "OK"):
	connection_status = new_status
	self.status_code = status_code
	self.status_text = status_text
	
	match new_status:
		"open":
			status = RequestStatus.SUCCESS
		"closed":
			if status_code >= 1000 and status_code < 1100:
				status = RequestStatus.SUCCESS
			else:
				status = RequestStatus.ERROR
		"error":
			status = RequestStatus.ERROR
	
	end_time = Time.get_ticks_msec()
	time_ms = end_time - start_time
