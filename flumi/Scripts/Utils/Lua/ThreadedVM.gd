class_name ThreadedLuaVM
extends RefCounted

signal script_completed(result: Dictionary)
signal script_error(error: String)
signal print_output(print_data: Dictionary)
signal dom_operation_request(operation: Dictionary)

var lua_thread: Thread
var lua_vm: LuauVM
var lua_api: LuaAPI
var dom_parser: HTMLParser
var command_queue: Array = []
var queue_mutex: Mutex
var should_exit: bool = false
var thread_semaphore: Semaphore

# Sleep system
var sleep_mutex: Mutex
var sleep_condition: bool = false
var sleep_end_time: float = 0.0

func _init():
	queue_mutex = Mutex.new()
	sleep_mutex = Mutex.new()
	thread_semaphore = Semaphore.new()

func start_lua_thread(dom_parser_ref: HTMLParser, lua_api_ref: LuaAPI) -> bool:
	if lua_thread and lua_thread.is_alive():
		return false
		
	dom_parser = dom_parser_ref
	lua_api = lua_api_ref
	should_exit = false
	
	lua_thread = Thread.new()
	var error = lua_thread.start(_lua_thread_worker)
	
	if error != OK:
		return false
		
	return true

func stop_lua_thread():
	if not lua_thread or not lua_thread.is_alive():
		return
		
	should_exit = true
	thread_semaphore.post() # Wake up BRO
	
	# short time to exit gracefully
	var timeout_start = Time.get_ticks_msec()
	while lua_thread.is_alive() and (Time.get_ticks_msec() - timeout_start) < 500:
		OS.delay_msec(10)
	
	lua_thread.wait_to_finish()
	lua_thread = null

func execute_script_async(script_code: String):
	queue_mutex.lock()
	command_queue.append({
		"type": "execute_script",
		"code": script_code
	})
	queue_mutex.unlock()
	thread_semaphore.post()

func execute_callback_async(callback_ref: int, args: Array = []):
	if not lua_thread or not lua_thread.is_alive():
		return
		
	queue_mutex.lock()
	command_queue.append({
		"type": "execute_callback",
		"callback_ref": callback_ref,
		"args": args
	})
	queue_mutex.unlock()
	thread_semaphore.post()

func execute_timeout_callback_async(timeout_id: int):
	if not lua_thread or not lua_thread.is_alive():
		return
		
	queue_mutex.lock()
	command_queue.append({
		"type": "execute_timeout",
		"timeout_id": timeout_id
	})
	queue_mutex.unlock()
	thread_semaphore.post()

func sleep_lua(duration_seconds: float):
	sleep_mutex.lock()
	sleep_end_time = Time.get_ticks_msec() / 1000.0 + duration_seconds
	sleep_condition = true
	sleep_mutex.unlock()
	
	while true:
		sleep_mutex.lock()
		var current_time = Time.get_ticks_msec() / 1000.0
		var should_continue = sleep_condition and current_time < sleep_end_time
		sleep_mutex.unlock()
		
		if not should_continue:
			break
		# Yield to allow other threads to run
		OS.delay_msec(1)

func _lua_thread_worker():
	lua_vm = LuauVM.new()
	
	lua_vm.open_libraries([lua_vm.LUA_BASE_LIB, lua_vm.LUA_BIT32_LIB,
		lua_vm.LUA_COROUTINE_LIB, lua_vm.LUA_MATH_LIB, lua_vm.LUA_UTF8_LIB,
		lua_vm.LUA_TABLE_LIB, lua_vm.LUA_STRING_LIB, lua_vm.LUA_VECTOR_LIB])
	
	lua_vm.lua_pushcallable(_print_handler, "print")
	lua_vm.lua_setglobal("print")
	
	# Setup threaded Time.sleep function
	lua_vm.lua_newtable()
	lua_vm.lua_pushcallable(_time_sleep_handler, "Time.sleep")
	lua_vm.lua_setfield(-2, "sleep")
	lua_vm.lua_setglobal("Time")
	
	_setup_threaded_gurt_api()
	_setup_additional_lua_apis()
	
	while not should_exit:
		if thread_semaphore.try_wait():
			_process_command_queue()
		else:
			OS.delay_msec(10)
	
	lua_vm = null

func _process_command_queue():
	queue_mutex.lock()
	var commands_to_process = command_queue.duplicate()
	command_queue.clear()
	queue_mutex.unlock()
	
	for command in commands_to_process:
		match command.type:
			"execute_script":
				_execute_script_in_thread(command.code)
			"execute_callback":
				_execute_callback_in_thread(command.callback_ref, command.args)
			"execute_timeout":
				_execute_timeout_in_thread(command.timeout_id)

func _execute_script_in_thread(script_code: String):
	if not lua_vm:
		call_deferred("_emit_script_error", "Lua VM not initialized")
		return
	
	var result = lua_vm.lua_dostring(script_code)
	
	if result == lua_vm.LUA_OK:
		call_deferred("_emit_script_completed", {"success": true})
	else:
		var error_msg = lua_vm.lua_tostring(-1)
		lua_vm.lua_pop(1)
		call_deferred("_emit_script_error", error_msg)

func _call_lua_function_with_args(args: Array) -> bool:
	# Push arguments
	for arg in args:
		lua_vm.lua_pushvariant(arg)
	
	# Execute the callback with proper error handling
	if lua_vm.lua_pcall(args.size(), 0, 0) != lua_vm.LUA_OK:
		var error_msg = lua_vm.lua_tostring(-1)
		lua_vm.lua_pop(1)
		call_deferred("_emit_script_error", "Callback error: " + error_msg)
		return false
	return true

func _execute_callback_in_thread(callback_ref: int, args: Array):
	if not lua_vm:
		return
	
	lua_vm.lua_pushstring("THREADED_CALLBACKS")
	lua_vm.lua_rawget(lua_vm.LUA_REGISTRYINDEX)
	if not lua_vm.lua_isnil(-1):
		lua_vm.lua_pushinteger(callback_ref)
		lua_vm.lua_rawget(-2)
		if lua_vm.lua_isfunction(-1):
			lua_vm.lua_remove(-2) # Remove the table, keep the function
			if _call_lua_function_with_args(args):
				return
		else:
			lua_vm.lua_pop(1) # Pop non-function value
	
	lua_vm.lua_pop(1) # Pop the table
	
	# Fallback to regular registry lookup
	lua_vm.lua_rawgeti(lua_vm.LUA_REGISTRYINDEX, callback_ref)
	if lua_vm.lua_isfunction(-1):
		_call_lua_function_with_args(args)
	else:
		lua_vm.lua_pop(1)

func _execute_timeout_in_thread(timeout_id: int):
	if not lua_vm:
		return
	
	# Check if this is an interval by looking at the timeout manager
	var timeout_info = lua_api.timeout_manager.active_timeouts.get(timeout_id, null)
	var is_interval = timeout_info != null and timeout_info.is_interval
	
	# Retrieve timeout callback from the special timeout registry
	lua_vm.lua_pushstring("GURT_THREADED_TIMEOUTS")
	lua_vm.lua_rawget(lua_vm.LUA_REGISTRYINDEX)
	if not lua_vm.lua_isnil(-1):
		lua_vm.lua_pushinteger(timeout_id)
		lua_vm.lua_rawget(-2)
		if lua_vm.lua_isfunction(-1):
			lua_vm.lua_remove(-2) # Remove the table, keep the function
			if _call_lua_function_with_args([]):
				# Only clean up the callback if it's a timeout (not an interval)
				if not is_interval:
					lua_vm.lua_pushstring("GURT_THREADED_TIMEOUTS")
					lua_vm.lua_rawget(lua_vm.LUA_REGISTRYINDEX)
					if not lua_vm.lua_isnil(-1):
						lua_vm.lua_pushinteger(timeout_id)
						lua_vm.lua_pushnil()
						lua_vm.lua_rawset(-3)
					lua_vm.lua_pop(1)
				return
		else:
			lua_vm.lua_pop(1) # Pop non-function value
	
	lua_vm.lua_pop(1) # Pop the table

func _print_handler(vm: LuauVM) -> int:
	var message_parts: Array = []
	var num_args = vm.lua_gettop()
	
	for i in range(1, num_args + 1):
		var lua_type = vm.lua_type(i)
		if lua_type == vm.LUA_TTABLE:
			var table_data = vm.lua_todictionary(i)
			message_parts.append({
				"type": "table",
				"data": table_data
			})
		else:
			var value_str = LuaPrintUtils.lua_value_to_string(vm, i)
			message_parts.append({
				"type": "primitive",
				"data": value_str
			})
	
	var print_data = {
		"parts": message_parts,
		"count": message_parts.size()
	}
	
	call_deferred("_emit_print_output", print_data)
	
	return 0

func _time_sleep_handler(vm: LuauVM) -> int:
	vm.luaL_checknumber(1)
	var seconds = vm.lua_tonumber(1)
	
	if seconds > 0:
		sleep_lua(seconds)
	
	return 0

func _trace_log_handler(vm: LuauVM) -> int:
	var message = vm.luaL_checkstring(1)
	call_deferred("_emit_trace_message", message, "lua")
	return 0

func _trace_warning_handler(vm: LuauVM) -> int:
	var message = vm.luaL_checkstring(1)
	call_deferred("_emit_trace_message", message, "warning")
	return 0

func _trace_error_handler(vm: LuauVM) -> int:
	var message = vm.luaL_checkstring(1)
	call_deferred("_emit_trace_message", message, "error")
	return 0

func _setup_threaded_gurt_api():
	lua_vm.lua_pushcallable(_print_handler, "print")
	lua_vm.lua_setglobal("print")
	
	# Setup trace functions
	lua_vm.lua_pushcallable(_trace_log_handler, "_trace_log")
	lua_vm.lua_setglobal("_trace_log")
	
	lua_vm.lua_pushcallable(_trace_warning_handler, "_trace_warning") 
	lua_vm.lua_setglobal("_trace_warning")
	
	lua_vm.lua_pushcallable(_trace_error_handler, "_trace_error")
	lua_vm.lua_setglobal("_trace_error")
	
	LuaTimeUtils.setup_time_api(lua_vm)
	
	lua_vm.lua_getglobal("Time")
	if not lua_vm.lua_isnil(-1):
		lua_vm.lua_pushcallable(_time_sleep_handler, "Time.sleep")
		lua_vm.lua_setfield(-2, "sleep")
	lua_vm.lua_pop(1)
	
	lua_vm.lua_newtable()
	
	lua_vm.lua_pushcallable(_gurt_select_handler, "gurt.select")
	lua_vm.lua_setfield(-2, "select")
	
	lua_vm.lua_pushcallable(_gurt_select_all_handler, "gurt.selectAll")
	lua_vm.lua_setfield(-2, "selectAll")
	
	lua_vm.lua_pushcallable(_gurt_create_handler, "gurt.create")
	lua_vm.lua_setfield(-2, "create")
	
	# Add timer functions as global functions
	lua_vm.lua_pushcallable(_set_timeout_handler, "setTimeout")
	lua_vm.lua_setglobal("setTimeout")
	
	lua_vm.lua_pushcallable(lua_api._gurt_clear_timeout_handler, "clearTimeout")
	lua_vm.lua_setglobal("clearTimeout")
	
	lua_vm.lua_pushcallable(_set_interval_handler, "setInterval")
	lua_vm.lua_setglobal("setInterval")
	
	lua_vm.lua_pushcallable(lua_api._gurt_clear_interval_handler, "clearInterval")
	lua_vm.lua_setglobal("clearInterval")
	
	lua_vm.lua_newtable()
	lua_vm.lua_pushcallable(lua_api._gurt_location_reload_handler, "gurt.location.reload")
	lua_vm.lua_setfield(-2, "reload")
	lua_vm.lua_pushcallable(lua_api._gurt_location_goto_handler, "gurt.location.goto")
	lua_vm.lua_setfield(-2, "goto")
	
	var current_href = get_current_href()
	lua_vm.lua_pushstring(current_href)
	lua_vm.lua_setfield(-2, "href")
	
	lua_vm.lua_newtable()
	lua_vm.lua_pushcallable(lua_api._gurt_location_query_get_handler, "gurt.location.query.get")
	lua_vm.lua_setfield(-2, "get")
	lua_vm.lua_pushcallable(lua_api._gurt_location_query_has_handler, "gurt.location.query.has")
	lua_vm.lua_setfield(-2, "has")
	lua_vm.lua_pushcallable(lua_api._gurt_location_query_getAll_handler, "gurt.location.query.getAll")
	lua_vm.lua_setfield(-2, "getAll")
	lua_vm.lua_setfield(-2, "query")
	
	lua_vm.lua_setfield(-2, "location")
	
	var body_element = dom_parser.find_first("body")
	if body_element:
		LuaDOMUtils.create_element_wrapper(lua_vm, body_element, lua_api)
		lua_vm.lua_pushcallable(_body_on_handler, "body.on")
		lua_vm.lua_setfield(-2, "on")
		lua_vm.lua_setfield(-2, "body")
	
	lua_vm.lua_pushcallable(_gurt_get_width_handler, "gurt.width")
	lua_vm.lua_setfield(-2, "width")
	
	lua_vm.lua_pushcallable(_gurt_get_height_handler, "gurt.height")
	lua_vm.lua_setfield(-2, "height")
	
	lua_vm.lua_setglobal("gurt")

func _setup_additional_lua_apis():
	lua_vm.lua_getglobal("table")
	if lua_vm.lua_isnil(-1):
		lua_vm.lua_pop(1)
		lua_vm.lua_newtable()
		lua_vm.lua_setglobal("table")
		lua_vm.lua_getglobal("table")
	
	lua_vm.lua_pushcallable(_table_tostring_handler, "table.tostring")
	lua_vm.lua_setfield(-2, "tostring")
	lua_vm.lua_pop(1)
	
	LuaSignalUtils.setup_signal_api(lua_vm)
	LuaClipboardUtils.setup_clipboard_api(lua_vm)
	LuaNetworkUtils.setup_network_api(lua_vm)
	LuaJSONUtils.setup_json_api(lua_vm)
	LuaWebSocketUtils.setup_websocket_api(lua_vm)
	LuaAudioUtils.setup_audio_api(lua_vm)
	LuaDownloadUtils.setup_download_api(lua_vm)
	LuaCrumbsUtils.setup_crumbs_api(lua_vm)
	LuaRegexUtils.setup_regex_api(lua_vm)
	LuaURLUtils.setup_url_api(lua_vm)
	Trace.setup_trace_api(lua_vm)

func _table_tostring_handler(vm: LuauVM) -> int:
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var table_string = LuaPrintUtils.table_to_string(vm, 1)
	vm.lua_pushstring(table_string)
	return 1

func _emit_script_completed(result: Dictionary):
	script_completed.emit(result)

func _emit_script_error(error: String):
	script_error.emit(error)

func _emit_print_output(print_data: Dictionary):
	print_output.emit(print_data)

func _gurt_select_all_handler(vm: LuauVM) -> int:
	var selector: String = vm.luaL_checkstring(1)
	
	if not dom_parser or not dom_parser.parse_result:
		vm.lua_newtable()
		return 1
	
	var elements = SelectorUtils.find_all_matching(selector, dom_parser.parse_result.all_elements)
	
	vm.lua_newtable()
	for i in range(elements.size()):
		vm.lua_pushinteger(i + 1)
		LuaDOMUtils.create_element_wrapper(vm, elements[i], lua_api)
		vm.lua_rawset(-3)
	
	return 1

func _gurt_create_handler(vm: LuauVM) -> int:
	var tag_name: String = vm.luaL_checkstring(1)
	var attributes = {}
	
	if vm.lua_gettop() >= 2 and not vm.lua_isnil(2):
		vm.luaL_checktype(2, vm.LUA_TTABLE)
		attributes = vm.lua_todictionary(2)
	
	var new_element = HTMLParser.HTMLElement.new(tag_name)
	
	for attr_name in attributes:
		if attr_name == "text":
			new_element.text_content = str(attributes[attr_name])
		else:
			new_element.set_attribute(attr_name, str(attributes[attr_name]))
	
	var element_id = lua_api.get_or_assign_element_id(new_element)
	new_element.set_attribute("id", element_id)
	
	dom_parser.parse_result.all_elements.append(new_element)
	
	LuaDOMUtils.create_element_wrapper(vm, new_element, lua_api)
	return 1

func _set_timeout_handler(vm: LuauVM) -> int:
	vm.luaL_checktype(1, vm.LUA_TFUNCTION)
	var delay_ms: int = vm.luaL_checkint(2)
	
	var timeout_id = lua_api.timeout_manager.next_timeout_id
	lua_api.timeout_manager.next_timeout_id += 1
	
	vm.lua_pushstring("GURT_THREADED_TIMEOUTS")
	vm.lua_rawget(vm.LUA_REGISTRYINDEX)
	if vm.lua_isnil(-1):
		vm.lua_pop(1)
		vm.lua_newtable()
		vm.lua_pushstring("GURT_THREADED_TIMEOUTS")
		vm.lua_pushvalue(-2)
		vm.lua_rawset(vm.LUA_REGISTRYINDEX)
	
	vm.lua_pushinteger(timeout_id)
	vm.lua_pushvalue(1)
	vm.lua_rawset(-3)
	vm.lua_pop(1)
	
	call_deferred("_create_threaded_timeout", timeout_id, delay_ms)
	
	vm.lua_pushinteger(timeout_id)
	return 1

func _clear_timeout_handler(vm: LuauVM) -> int:
	return lua_api._gurt_clear_timeout_handler(vm)

func _set_interval_handler(vm: LuauVM) -> int:
	vm.luaL_checktype(1, vm.LUA_TFUNCTION)
	var delay_ms: int = vm.luaL_checkint(2)
	
	var interval_id = lua_api.timeout_manager.next_timeout_id
	lua_api.timeout_manager.next_timeout_id += 1
	
	vm.lua_pushstring("GURT_THREADED_TIMEOUTS")
	vm.lua_rawget(vm.LUA_REGISTRYINDEX)
	if vm.lua_isnil(-1):
		vm.lua_pop(1)
		vm.lua_newtable()
		vm.lua_pushstring("GURT_THREADED_TIMEOUTS")
		vm.lua_pushvalue(-2)
		vm.lua_rawset(vm.LUA_REGISTRYINDEX)
	
	vm.lua_pushinteger(interval_id)
	vm.lua_pushvalue(1)
	vm.lua_rawset(-3)
	vm.lua_pop(1)
	
	call_deferred("_create_threaded_interval", interval_id, delay_ms)
	
	vm.lua_pushinteger(interval_id)
	return 1

func get_current_href() -> String:
	var main_node = Engine.get_main_loop().current_scene
	
	return main_node.current_domain

func _gurt_get_width_handler(vm: LuauVM) -> int:
	var result = [0.0]
	call_deferred("_get_width_sync", result)
	while result[0] == 0.0:
		OS.delay_msec(1)
	vm.lua_pushnumber(result[0])
	return 1

func _gurt_get_height_handler(vm: LuauVM) -> int:
	var result = [0.0]
	call_deferred("_get_height_sync", result)
	while result[0] == 0.0:
		OS.delay_msec(1)
	vm.lua_pushnumber(result[0])
	return 1

func _get_width_sync(result: Array):
	var main_node = Engine.get_main_loop().current_scene
	if main_node:
		var active_tab = main_node.get_active_tab()
		if active_tab and active_tab.website_container:
			result[0] = active_tab.website_container.size.x
		else:
			result[0] = 1024.0
	else:
		result[0] = 1024.0

func _get_height_sync(result: Array):
	var main_node = Engine.get_main_loop().current_scene
	if main_node:
		var active_tab = main_node.get_active_tab()
		if active_tab and active_tab.website_container:
			result[0] = active_tab.website_container.size.y
		else:
			result[0] = 768.0
	else:
		result[0] = 768.0


func _gurt_select_handler(vm: LuauVM) -> int:
	var selector: String = vm.luaL_checkstring(1)
	
	if not dom_parser or not dom_parser.parse_result:
		vm.lua_pushnil()
		return 1
	
	var element = SelectorUtils.find_first_matching(selector, dom_parser.parse_result.all_elements)
	if element:
		LuaDOMUtils.create_element_wrapper(vm, element, lua_api)
		return 1
	else:
		vm.lua_pushnil()
		return 1

func _body_on_handler(vm: LuauVM) -> int:
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var event_name: String = vm.luaL_checkstring(2)
	vm.luaL_checktype(3, vm.LUA_TFUNCTION)
	
	vm.lua_pushstring("THREADED_CALLBACKS")
	vm.lua_rawget(vm.LUA_REGISTRYINDEX)
	if vm.lua_isnil(-1):
		vm.lua_pop(1)
		vm.lua_newtable()
		vm.lua_pushstring("THREADED_CALLBACKS")
		vm.lua_pushvalue(-2)
		vm.lua_rawset(vm.LUA_REGISTRYINDEX)
	
	var callback_ref = lua_api.next_callback_ref
	lua_api.next_callback_ref += 1
	
	var subscription_id = lua_api.next_subscription_id
	lua_api.next_subscription_id += 1
	
	vm.lua_pushinteger(callback_ref)
	vm.lua_pushvalue(3)
	vm.lua_rawset(-3)
	vm.lua_pop(1)
	
	var operation = {
		"type": "register_body_event",
		"event_name": event_name,
		"callback_ref": callback_ref,
		"subscription_id": subscription_id
	}
	
	call_deferred("_emit_dom_operation_request", operation)
	
	vm.lua_newtable()
	vm.lua_pushinteger(subscription_id)
	vm.lua_setfield(-2, "_subscription_id")
	
	vm.lua_pushcallable(LuaDOMUtils._unsubscribe_wrapper, "subscription.unsubscribe")
	vm.lua_setfield(-2, "unsubscribe")
	return 1

func _emit_dom_operation_request(operation: Dictionary):
	dom_operation_request.emit(operation)

func _create_threaded_timeout(timeout_id: int, delay_ms: int):
	lua_api._ensure_timeout_manager()
	
	var timeout_info = lua_api.timeout_manager.TimeoutInfo.new(timeout_id, timeout_id, lua_vm, lua_api.timeout_manager, false, delay_ms)
	lua_api.timeout_manager.active_timeouts[timeout_id] = timeout_info
	lua_api.timeout_manager.threaded_vm = self
	
	var timer = Timer.new()
	timer.wait_time = delay_ms / 1000.0
	timer.one_shot = true
	timer.timeout.connect(lua_api.timeout_manager._on_timeout_triggered.bind(timeout_info))
	
	timeout_info.timer = timer
	lua_api.add_child(timer)
	timer.start()

func _create_threaded_interval(interval_id: int, delay_ms: int):
	lua_api._ensure_timeout_manager()
	
	var timeout_info = lua_api.timeout_manager.TimeoutInfo.new(interval_id, interval_id, lua_vm, lua_api.timeout_manager, true, delay_ms)
	lua_api.timeout_manager.active_timeouts[interval_id] = timeout_info
	lua_api.timeout_manager.threaded_vm = self
	
	var timer = Timer.new()
	timer.wait_time = delay_ms / 1000.0
	timer.one_shot = false
	timer.timeout.connect(lua_api.timeout_manager._on_timeout_triggered.bind(timeout_info))
	
	timeout_info.timer = timer
	lua_api.add_child(timer)
	timer.start()

func _emit_trace_message(message: String, level: String):
	match level:
		"lua", "log":
			Trace.trace_log(message)
		"warning":
			Trace.trace_warning(message)
		"error":
			Trace.trace_error(message)
