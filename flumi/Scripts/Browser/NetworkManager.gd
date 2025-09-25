extends Node

signal request_started(request: NetworkRequest)
signal request_completed(request: NetworkRequest)
signal request_failed(request: NetworkRequest)

var active_requests: Dictionary = {} # request_id -> NetworkRequest
var all_requests: Array[NetworkRequest] = []
var dev_tools_network_tab: NetworkTab = null

func register_dev_tools_network_tab(network_tab: NetworkTab):
	dev_tools_network_tab = network_tab

func start_request(url: String, method: String = "GET", is_from_lua: bool = false) -> NetworkRequest:
	var request = NetworkRequest.new(url, method)
	request.is_from_lua = is_from_lua
	
	active_requests[request.id] = request
	all_requests.append(request)
	
	# Notify dev tools
	if dev_tools_network_tab:
		dev_tools_network_tab.add_network_request(request)
	
	request_started.emit(request)
	return request

func complete_request(request_id: String, status_code: int, status_text: String, headers: Dictionary, body: String, body_bytes: PackedByteArray = []):
	var request = active_requests.get(request_id)
	if not request:
		return
	
	request.set_response(status_code, status_text, headers, body, body_bytes)
	active_requests.erase(request_id)
	
	# Update dev tools UI
	if dev_tools_network_tab:
		dev_tools_network_tab.update_request_item(request)
	
	if request.status == NetworkRequest.RequestStatus.SUCCESS:
		request_completed.emit(request)
	else:
		request_failed.emit(request)

func fail_request(request_id: String, error_message: String):
	var request = active_requests.get(request_id)
	if not request:
		return
	
	request.set_error(error_message)
	active_requests.erase(request_id)
	
	# Update dev tools UI
	if dev_tools_network_tab:
		dev_tools_network_tab.update_request_item(request)
	
	request_failed.emit(request)

func set_request_headers(request_id: String, headers: Dictionary):
	var request = active_requests.get(request_id)
	if request:
		request.request_headers = headers

func set_request_body(request_id: String, body: String):
	var request = active_requests.get(request_id)
	if request:
		request.request_body = body

func get_all_requests() -> Array[NetworkRequest]:
	return all_requests

func clear_all_requests():
	active_requests.clear()
	all_requests.clear()
	
	if dev_tools_network_tab:
		dev_tools_network_tab.clear_all_requests()

func clear_all_requests_except(preserve_request_id: String):
	# Remove from active_requests but preserve specific request
	var preserved_active = null
	if active_requests.has(preserve_request_id):
		preserved_active = active_requests[preserve_request_id]
	
	active_requests.clear()
	if preserved_active:
		active_requests[preserve_request_id] = preserved_active
	
	# Remove from all_requests but preserve specific request
	var preserved_request = null
	for request in all_requests:
		if request.id == preserve_request_id:
			preserved_request = request
			break
	
	all_requests.clear()
	if preserved_request:
		all_requests.append(preserved_request)
	
	if dev_tools_network_tab:
		dev_tools_network_tab.clear_all_requests_except(preserve_request_id)

func get_request_stats() -> Dictionary:
	var total_requests = all_requests.size()
	var total_size = 0
	var successful_requests = 0
	var failed_requests = 0
	var pending_requests = active_requests.size()
	
	for request in all_requests:
		total_size += request.size
		match request.status:
			NetworkRequest.RequestStatus.SUCCESS:
				successful_requests += 1
			NetworkRequest.RequestStatus.ERROR:
				failed_requests += 1
	
	return {
		"total": total_requests,
		"successful": successful_requests,
		"failed": failed_requests,
		"pending": pending_requests,
		"total_size": total_size
	}

func add_completed_request(url: String, method: String, is_from_lua: bool, status_code: int, status_text: String, response_headers: Dictionary, response_body: String, body_bytes: PackedByteArray = [], request_headers: Dictionary = {}, request_body: String = "", time_ms: float = 0.0):

	var request = NetworkRequest.new(url, method)
	request.is_from_lua = is_from_lua
	request.request_headers = request_headers
	request.request_body = request_body

	if time_ms > 0.0:
		request.start_time = Time.get_ticks_msec() - time_ms

	request.set_response(status_code, status_text, response_headers, response_body, body_bytes)

	all_requests.append(request)

	if dev_tools_network_tab:
		dev_tools_network_tab.add_network_request(request)

func start_websocket_connection(url: String, websocket_id: String) -> NetworkRequest:
	var request = NetworkRequest.create_websocket_connection(url, websocket_id)
	active_requests[request.id] = request
	all_requests.append(request)
	
	if dev_tools_network_tab:
		dev_tools_network_tab.add_network_request(request)
	
	request_started.emit(request)
	return request

func add_websocket_message(url: String, websocket_id: String, direction: String, message: String):
	var connection_request: NetworkRequest = null
	
	for request in active_requests.values():
		if request.websocket_id == websocket_id and request.websocket_event_type == "connection":
			connection_request = request
			break
	
	if not connection_request:
		for request in all_requests:
			if request.websocket_id == websocket_id and request.websocket_event_type == "connection":
				connection_request = request
				break
	
	if connection_request:
		connection_request.add_websocket_message(direction, message)
		
		if dev_tools_network_tab:
			dev_tools_network_tab.update_request_item(connection_request)
		
		request_completed.emit(connection_request)

func update_websocket_connection(websocket_id: String, status: String, status_code: int = 200, status_text: String = "OK"):
	for request in active_requests.values():
		if request.websocket_id == websocket_id and request.websocket_event_type == "connection":
			request.update_websocket_status(status, status_code, status_text)
			
			if status in ["closed", "error"]:
				active_requests.erase(request.id)
			
			if dev_tools_network_tab:
				dev_tools_network_tab.update_request_item(request)
			
			if request.status == NetworkRequest.RequestStatus.SUCCESS:
				request_completed.emit(request)
			else:
				request_failed.emit(request)
			break