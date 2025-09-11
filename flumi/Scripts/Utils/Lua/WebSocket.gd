class_name LuaWebSocketUtils
extends RefCounted

static var websocket_instances: Dictionary = {}
static var instance_counter: int = 0

class WebSocketWrapper:
	extends RefCounted
	
	var instance_id: String
	var vm: LuauVM
	var url: String
	var websocket: WebSocketPeer
	var connection_status: bool = false
	var event_handlers: Dictionary = {}
	var timer: Timer
	var last_state: int = -1
	
	func _init():
		websocket = WebSocketPeer.new()
	
	func connect_to_url():
		if connection_status:
			return
		
		NetworkManager.call_deferred("start_websocket_connection", url, instance_id)
		
		var error = websocket.connect_to_url(url)
		
		if error == OK:
			# Start polling timer
			if timer:
				timer.queue_free()
			
			timer = Timer.new()
			timer.wait_time = 0.016  # ~60 FPS polling
			timer.timeout.connect(_poll_websocket)
			
			# Add to scene tree using call_deferred for thread safety
			var main_loop = Engine.get_main_loop()
			
			if main_loop and main_loop.current_scene:
				main_loop.current_scene.call_deferred("add_child", timer)
				timer.call_deferred("start")
			else:
				trigger_event("error", {"message": "No scene available for WebSocket timer"})
				NetworkManager.call_deferred("update_websocket_connection", instance_id, "error", 0, "No scene available")
		else:
			trigger_event("error", {"message": "Failed to connect to " + url + " (error: " + str(error) + ")"})
			NetworkManager.call_deferred("update_websocket_connection", instance_id, "error", 0, "Connection failed: " + str(error))
	
	func _poll_websocket():
		if not websocket:
			return
		
		websocket.poll()
		var state = websocket.get_ready_state()
		
		match state:
			WebSocketPeer.STATE_OPEN:
				if not connection_status:
					connection_status = true
					trigger_event("open", {})
					# Update NetworkManager with successful connection
					NetworkManager.call_deferred("update_websocket_connection", instance_id, "open", 200, "Connected")
				
				# Check for messages
				while websocket.get_available_packet_count() > 0:
					var packet = websocket.get_packet()
					var message = packet.get_string_from_utf8()
					trigger_event("message", {"data": message})
					# Track received message in NetworkManager
					NetworkManager.call_deferred("add_websocket_message", url, instance_id, "received", message)
			
			WebSocketPeer.STATE_CLOSED:
				if connection_status:
					connection_status = false
					trigger_event("close", {})
					# Update NetworkManager with closed connection
					var close_code = websocket.get_close_code()
					var close_reason = websocket.get_close_reason()
					NetworkManager.call_deferred("update_websocket_connection", instance_id, "closed", close_code, close_reason)
				
				# Clean up timer
				if timer:
					timer.queue_free()
					timer = null
			
			WebSocketPeer.STATE_CONNECTING:
				# Still connecting, keep polling
				pass
			
			WebSocketPeer.STATE_CLOSING:
				# Connection is closing
				if connection_status:
					connection_status = false
					NetworkManager.call_deferred("update_websocket_connection", instance_id, "closing", 0, "Closing")
			
			_:
				# Unknown state or connection failed
				if connection_status:
					connection_status = false
					trigger_event("close", {})
					NetworkManager.call_deferred("update_websocket_connection", instance_id, "closed", 0, "Unexpected disconnection")
				elif not connection_status:
					# This might be a connection failure
					trigger_event("error", {"message": "Connection failed or was rejected by server"})
					NetworkManager.call_deferred("update_websocket_connection", instance_id, "error", 0, "Connection failed or rejected")
	
	func send_message(message: String):
		if connection_status and websocket:
			websocket.send_text(message)
			# Track sent message in NetworkManager
			NetworkManager.call_deferred("add_websocket_message", url, instance_id, "sent", message)
	
	func close_connection():
		if websocket:
			websocket.close()
		connection_status = false
		
		# Update NetworkManager with manual close
		NetworkManager.call_deferred("update_websocket_connection", instance_id, "closed", 1000, "Manually closed")
		
		if timer:
			timer.queue_free()
			timer = null
	
	func trigger_event(event_name: String, data: Dictionary):
		if not vm or not event_handlers.has(event_name):
			return
		
		var func_ref = event_handlers[event_name]
		
		# Get the function from the reference
		vm.lua_getref(func_ref)
		
		if vm.lua_isfunction(-1):
			# Create event data table
			vm.lua_newtable()
			for key in data:
				vm.lua_pushvariant(data[key])
				vm.lua_setfield(-2, key)
			
			# Call the function
			var result = vm.lua_pcall(1, 0, 0)
			if result != vm.LUA_OK:
				var error_msg = vm.lua_tostring(-1)
				print("WebSocket event error: ", error_msg)
				vm.lua_pop(1)
		else:
			vm.lua_pop(1)  # Pop the non-function value

static func setup_websocket_api(vm: LuauVM):
	vm.lua_newtable()
	vm.lua_pushcallable(_websocket_new, "WebSocket.new")
	vm.lua_setfield(-2, "new")
	vm.lua_setglobal("WebSocket")

static func _websocket_new(vm: LuauVM) -> int:
	# handle both WebSocket:new(url) and WebSocket.new(url) syntax
	var url: String
	if vm.lua_gettop() == 2 and vm.lua_istable(1):
		url = vm.luaL_checkstring(2)
	else:
		url = vm.luaL_checkstring(1)
	
	# Generate unique instance ID
	instance_counter += 1
	var instance_id = "ws_" + str(instance_counter)
	
	# Create WebSocket wrapper object
	var wrapper = WebSocketWrapper.new()
	wrapper.instance_id = instance_id
	wrapper.vm = vm
	wrapper.url = url
	
	# Store in global instances to keep it alive
	websocket_instances[instance_id] = wrapper
	
	# Create Lua table for the WebSocket
	vm.lua_newtable()
	
	# Store instance ID
	vm.lua_pushstring(instance_id)
	vm.lua_setfield(-2, "_instance_id")
	
	# Store URL
	vm.lua_pushstring(url)
	vm.lua_setfield(-2, "_url")
	
	# Store connection state
	vm.lua_pushboolean(false)
	vm.lua_setfield(-2, "_connected")
	
	# Initialize event handlers table
	vm.lua_newtable()
	vm.lua_setfield(-2, "_event_handlers")
	
	# Add methods
	vm.lua_pushcallable(_websocket_on, "websocket.on")
	vm.lua_setfield(-2, "on")
	
	vm.lua_pushcallable(_websocket_send, "websocket.send")
	vm.lua_setfield(-2, "send")
	
	vm.lua_pushcallable(_websocket_close, "websocket.close")
	vm.lua_setfield(-2, "close")
	
	vm.lua_pushcallable(_websocket_connect, "websocket.connect")
	vm.lua_setfield(-2, "connect")
	
	# Auto-connect
	wrapper.connect_to_url()
	
	return 1

static func _websocket_on(vm: LuauVM) -> int:
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var event_name: String = vm.luaL_checkstring(2)
	vm.luaL_checktype(3, vm.LUA_TFUNCTION)
	
	# Get instance ID
	vm.lua_getfield(1, "_instance_id")
	var instance_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	# Get wrapper instance
	var wrapper: WebSocketWrapper = websocket_instances.get(instance_id)
	if wrapper:
		# Store the function reference in wrapper
		var func_ref = vm.lua_ref(3)
		wrapper.event_handlers[event_name] = func_ref
	
	return 0

static func _websocket_send(vm: LuauVM) -> int:
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var message: String = vm.luaL_checkstring(2)
	
	# Get instance ID
	vm.lua_getfield(1, "_instance_id")
	var instance_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	# Get wrapper instance
	var wrapper: WebSocketWrapper = websocket_instances.get(instance_id)
	if wrapper and wrapper.connection_status:
		wrapper.send_message(message)
	else:
		vm.luaL_error("WebSocket is not connected")
	
	return 0

static func _websocket_close(vm: LuauVM) -> int:
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	
	# Get instance ID
	vm.lua_getfield(1, "_instance_id")
	var instance_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	# Get wrapper instance
	var wrapper: WebSocketWrapper = websocket_instances.get(instance_id)
	if wrapper:
		wrapper.close_connection()
	
	return 0

static func _websocket_connect(vm: LuauVM) -> int:
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	
	# Get instance ID
	vm.lua_getfield(1, "_instance_id")
	var instance_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	# Get wrapper instance
	var wrapper: WebSocketWrapper = websocket_instances.get(instance_id)
	if wrapper:
		wrapper.connect_to_url()
	
	return 0
