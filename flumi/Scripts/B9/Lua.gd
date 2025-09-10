class_name LuaAPI
extends Node

var threaded_vm: ThreadedLuaVM
var script_start_time: float = 0.0

class EventSubscription:
	var id: int
	var element_id: String
	var event_name: String
	var callback_ref: int
	var vm: LuauVM
	var lua_api: LuaAPI
	var connected_signal: String = ""
	var connected_node: Node = null
	var callback_func: Callable
	var wrapper_func: Callable

var dom_parser: HTMLParser
var event_subscriptions: Dictionary = {}
var next_subscription_id: int = 1
var next_callback_ref: int = 1

var element_id_counter: int = 1
var element_id_registry: Dictionary = {}
var pending_event_registrations: Array = []

func _init():
	timeout_manager = LuaTimeoutManager.new()
	threaded_vm = ThreadedLuaVM.new()
	threaded_vm.script_completed.connect(_on_threaded_script_completed)
	threaded_vm.script_error.connect(_on_threaded_script_error)
	threaded_vm.dom_operation_request.connect(_handle_dom_operation)
	threaded_vm.print_output.connect(_on_print_output)

func get_or_assign_element_id(element: HTMLParser.HTMLElement) -> String:
	var existing_id = element.get_attribute("id")
	if not existing_id.is_empty():
		element_id_registry[element] = existing_id
		return existing_id
	
	if element_id_registry.has(element):
		return element_id_registry[element]
	
	var new_id = "auto_" + str(element_id_counter)
	element_id_counter += 1
	
	element.set_attribute("id", new_id)
	element_id_registry[element] = new_id
	
	return new_id

func _gurt_select_handler(vm: LuauVM) -> int:
	var selector: String = vm.luaL_checkstring(1)
	
	var element = SelectorUtils.find_first_matching(selector, dom_parser.parse_result.all_elements)
	if not element:
		vm.lua_pushnil()
		return 1
	
	var element_id = get_or_assign_element_id(element)
	
	vm.lua_newtable()
	vm.lua_pushstring(element_id)
	vm.lua_setfield(-2, "_element_id")
	vm.lua_pushstring(element.tag_name)
	vm.lua_setfield(-2, "_tag_name")
	
	LuaDOMUtils.add_element_methods(vm, self)
	return 1

# selectAll() function to find multiple elements
func _gurt_select_all_handler(vm: LuauVM) -> int:
	var selector: String = vm.luaL_checkstring(1)
	
	var elements = SelectorUtils.find_all_matching(selector, dom_parser.parse_result.all_elements)
	
	vm.lua_newtable()
	var index = 1
	
	for element in elements:
		var element_id = get_or_assign_element_id(element)
		
		# Create element wrapper
		vm.lua_newtable()
		vm.lua_pushstring(element_id)
		vm.lua_setfield(-2, "_element_id")
		vm.lua_pushstring(element.tag_name)
		vm.lua_setfield(-2, "_tag_name")
		
		LuaDOMUtils.add_element_methods(vm, self)
		
		# Add to array at index
		vm.lua_rawseti(-2, index)
		index += 1
	
	return 1

# create() function to create HTML element
func _gurt_create_handler(vm: LuauVM) -> int:
	var tag_name: String = vm.luaL_checkstring(1)
	var options: Dictionary = {}
	
	if vm.lua_gettop() >= 2 and vm.lua_istable(2):
		options = vm.lua_todictionary(2)
	
	var element = HTMLParser.HTMLElement.new(tag_name)
	
	# Apply options as attributes and content
	for key in options:
		if key == "text":
			element.text_content = str(options[key])
		else:
			element.attributes[str(key)] = str(options[key])
	
	# Add to parser's element collection first
	dom_parser.parse_result.all_elements.append(element)
	
	# Get or assign stable ID
	var unique_id = get_or_assign_element_id(element)
	
	# Create Lua element wrapper with methods
	vm.lua_newtable()
	vm.lua_pushstring(unique_id)
	vm.lua_setfield(-2, "_element_id")
	vm.lua_pushstring(tag_name)
	vm.lua_setfield(-2, "_tag_name")
	vm.lua_pushboolean(true)
	vm.lua_setfield(-2, "_is_dynamic")
	
	LuaDOMUtils.add_element_methods(vm, self)
	return 1

var timeout_manager: LuaTimeoutManager

func _ensure_timeout_manager():
	if not timeout_manager:
		timeout_manager = LuaTimeoutManager.new()

# Timeout management handlers
func _gurt_set_timeout_handler(vm: LuauVM) -> int:
	_ensure_timeout_manager()
	return timeout_manager.set_threaded_timeout_handler(vm, self, threaded_vm)

func _gurt_clear_timeout_handler(vm: LuauVM) -> int:
	_ensure_timeout_manager()
	return timeout_manager.clear_timeout_handler(vm)

func _gurt_set_interval_handler(vm: LuauVM) -> int:
	_ensure_timeout_manager()
	return timeout_manager.set_threaded_interval_handler(vm, self, threaded_vm)

func _gurt_clear_interval_handler(vm: LuauVM) -> int:
	_ensure_timeout_manager()
	return timeout_manager.clear_interval_handler(vm)

# Location API handlers
func _gurt_location_reload_handler(_vm: LuauVM) -> int:
	call_deferred("_reload_current_page")
	return 0

func _gurt_location_goto_handler(vm: LuauVM) -> int:
	var url: String = vm.luaL_checkstring(1)
	call_deferred("_navigate_to_url", url)
	return 0

func _gurt_location_get_href_handler(vm: LuauVM) -> int:
	var main_node = Engine.get_main_loop().current_scene
	if main_node and main_node.has_method("get_current_url"):
		var current_url = main_node.get_current_url()
		vm.lua_pushstring(current_url)
	else:
		vm.lua_pushstring("")
	return 1

func _gurt_location_query_get_handler(vm: LuauVM) -> int:
	var key: String = vm.luaL_checkstring(1)
	var query_params = get_current_query_params()
	
	if query_params.has(key):
		vm.lua_pushstring(query_params[key])
	else:
		vm.lua_pushnil()
	return 1

func _gurt_location_query_has_handler(vm: LuauVM) -> int:
	var key: String = vm.luaL_checkstring(1)
	var query_params = get_current_query_params()
	
	vm.lua_pushboolean(query_params.has(key))
	return 1

func _gurt_location_query_getAll_handler(vm: LuauVM) -> int:
	var key: String = vm.luaL_checkstring(1)
	var query_params = get_current_query_params()
	
	vm.lua_newtable()
	
	if query_params.has(key):
		var value = query_params[key]
		if value is Array:
			for i in range(value.size()):
				vm.lua_pushstring(str(value[i]))
				vm.lua_rawseti(-2, i + 1)
		else:
			vm.lua_pushstring(str(value))
			vm.lua_rawseti(-2, 1)
	
	return 1

func get_current_query_params() -> Dictionary:
	var main_node = Engine.get_main_loop().current_scene
	var current_url = ""
	
	if main_node and main_node.has_method("get_current_url"):
		current_url = main_node.get_current_url()
	elif main_node and main_node.has_property("current_domain"):
		current_url = main_node.current_domain
	
	var query_params = {}
	
	if "?" in current_url:
		var query_string = current_url.split("?")[1]
		if "#" in query_string:
			query_string = query_string.split("#")[0]
		
		for param in query_string.split("&"):
			if "=" in param:
				var key_value = param.split("=", false, 1)
				var key = key_value[0].uri_decode()
				var value = key_value[1].uri_decode() if key_value.size() > 1 else ""
				
				if query_params.has(key):
					if query_params[key] is Array:
						query_params[key].append(value)
					else:
						query_params[key] = [query_params[key], value]
				else:
					query_params[key] = value
			else:
				var key = param.uri_decode()
				query_params[key] = ""
	
	return query_params

func _reload_current_page():
	var main_node = Engine.get_main_loop().current_scene
	if main_node and main_node.has_method("reload_current_page"):
		main_node.reload_current_page()

func _navigate_to_url(url: String):
	var main_node = Engine.get_main_loop().current_scene
	if main_node and main_node.has_method("navigate_to_url"):
		main_node.navigate_to_url(url)

# Event system handlers
func _element_on_event_handler(vm: LuauVM) -> int:
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var event_name: String = vm.luaL_checkstring(2)
	vm.luaL_checktype(3, vm.LUA_TFUNCTION)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	# Create a proper subscription with real ID
	var subscription = _create_subscription(vm, element_id, event_name)
	event_subscriptions[subscription.id] = subscription
	
	# Register the event on main thread
	call_deferred("_register_event_on_main_thread", element_id, event_name, subscription.callback_ref, subscription.id)
	
	# Return subscription with proper unsubscribe method
	vm.lua_newtable()
	vm.lua_pushinteger(subscription.id)
	vm.lua_setfield(-2, "_subscription_id")
	
	vm.lua_pushcallable(_subscription_unsubscribe_handler, "subscription.unsubscribe")
	vm.lua_setfield(-2, "unsubscribe")
	
	return 1

func _body_on_event_handler(vm: LuauVM) -> int:
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var event_name: String = vm.luaL_checkstring(2)
	vm.luaL_checktype(3, vm.LUA_TFUNCTION)
	
	var subscription = _create_subscription(vm, "body", event_name)
	event_subscriptions[subscription.id] = subscription
	
	var success = LuaEventUtils.connect_body_event(event_name, subscription, self)
	
	return _handle_subscription_result(vm, subscription, success)

func _subscription_unsubscribe_handler(vm: LuauVM) -> int:
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	
	vm.lua_getfield(1, "_subscription_id")
	var subscription_id: int = vm.lua_tointeger(-1)
	vm.lua_pop(1)
	
	var subscription = event_subscriptions.get(subscription_id, null)
	if subscription:
		LuaEventUtils.disconnect_subscription(subscription, self)
		event_subscriptions.erase(subscription_id)
		vm.lua_pushnil()
		vm.lua_rawseti(vm.LUA_REGISTRYINDEX, subscription.callback_ref)
	
	return 0

# Subscription management
func _create_subscription(vm: LuauVM, element_id: String, event_name: String) -> EventSubscription:
	var subscription_id = next_subscription_id
	next_subscription_id += 1
	var callback_ref = next_callback_ref
	next_callback_ref += 1
	
	vm.lua_pushvalue(3)
	vm.lua_rawseti(vm.LUA_REGISTRYINDEX, callback_ref)
	
	var subscription = EventSubscription.new()
	subscription.id = subscription_id
	subscription.element_id = element_id
	subscription.event_name = event_name
	subscription.callback_ref = callback_ref
	subscription.vm = vm
	subscription.lua_api = self
	
	return subscription

func _handle_subscription_result(vm: LuauVM, subscription: EventSubscription, success: bool) -> int:
	if success:
		vm.lua_newtable()
		vm.lua_pushinteger(subscription.id)
		vm.lua_setfield(-2, "_subscription_id")
		
		vm.lua_pushcallable(_subscription_unsubscribe_handler, "subscription.unsubscribe")
		vm.lua_setfield(-2, "unsubscribe")
		
		return 1
	else:
		vm.lua_pushnil()
		vm.lua_rawseti(vm.LUA_REGISTRYINDEX, subscription.callback_ref)
		event_subscriptions.erase(subscription.id)
		vm.lua_pushnil()
		return 1

# Event callbacks
func _on_event_triggered(subscription: EventSubscription) -> void:
	if not event_subscriptions.has(subscription.id):
		return
	
	_execute_lua_callback(subscription)

func _on_gui_input_click(event: InputEvent, subscription: EventSubscription) -> void:
	if not event_subscriptions.has(subscription.id):
		return
	
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			var mouse_info = _get_element_relative_mouse_position(mouse_event, subscription.element_id)
			_execute_lua_callback(subscription, [mouse_info])

func _on_gui_input_mouse_universal(event: InputEvent, signal_node: Node) -> void:
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			# Find all subscriptions for this node with mouse events
			for subscription_id in event_subscriptions:
				var subscription = event_subscriptions[subscription_id]
				if subscription.connected_node == signal_node and subscription.connected_signal == "gui_input_mouse":
					var should_trigger = false
					if subscription.event_name == "mousedown" and mouse_event.pressed:
						should_trigger = true
					elif subscription.event_name == "mouseup" and not mouse_event.pressed:
						should_trigger = true
					
					if should_trigger:
						var mouse_info = _get_element_relative_mouse_position(mouse_event, subscription.element_id)
						_execute_lua_callback(subscription, [mouse_info])

# Event callback handlers
func _on_gui_input_mousemove(event: InputEvent, subscription: EventSubscription) -> void:
	if not event_subscriptions.has(subscription.id):
		return
	
	if event is InputEventMouseMotion:
		var mouse_event = event as InputEventMouseMotion
		_handle_mousemove_event(mouse_event, subscription)

func _on_focus_gui_input(event: InputEvent, subscription: EventSubscription) -> void:
	if not event_subscriptions.has(subscription.id):
		return
	
	if event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			if subscription.event_name == "focusin":
				_execute_lua_callback(subscription)

func _handle_body_event(subscription: EventSubscription, event_name: String, event_data: Dictionary = {}) -> void:
	if event_subscriptions.has(subscription.id) and subscription.event_name == event_name:
		_execute_lua_callback(subscription, [event_data])

func _on_body_mouse_enter(subscription: EventSubscription) -> void:
	_handle_body_event(subscription, "mouseenter", {})

func _on_body_mouse_exit(subscription: EventSubscription) -> void:
	_handle_body_event(subscription, "mouseexit", {})

func _execute_lua_callback(subscription: EventSubscription, args: Array = []) -> void:
	threaded_vm.execute_callback_async(subscription.callback_ref, args)

func _execute_input_event_callback(subscription: EventSubscription, event_data: Dictionary) -> void:
	if not event_subscriptions.has(subscription.id):
		return
	_execute_lua_callback(subscription, [event_data])

# Global input processing
func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event = event as InputEventKey
		for subscription_id in event_subscriptions:
			var subscription = event_subscriptions[subscription_id]
			if subscription.element_id == "body" and subscription.connected_signal == "input":
				var should_trigger = false
				match subscription.event_name:
					"keydown":
						should_trigger = key_event.pressed
					"keyup": 
						should_trigger = not key_event.pressed
					"keypress":
						should_trigger = key_event.pressed
				
				if should_trigger:
					var key_info = {
						"key": OS.get_keycode_string(key_event.keycode),
						"keycode": key_event.keycode,
						"ctrl": key_event.ctrl_pressed,
						"shift": key_event.shift_pressed,
						"alt": key_event.alt_pressed
					}
					_execute_lua_callback(subscription, [key_info])
	
	elif event is InputEventMouseButton:
		var mouse_event = event as InputEventMouseButton
		for subscription_id in event_subscriptions:
			var subscription = event_subscriptions[subscription_id]
			if subscription.element_id == "body" and subscription.connected_signal == "input":
				var should_trigger = false
				match subscription.event_name:
					"mousedown":
						should_trigger = mouse_event.pressed
					"mouseup":
						should_trigger = not mouse_event.pressed
				
				if should_trigger:
					var mouse_info = {"x": 0, "y": 0, "button": mouse_event.button_index}
					var body_container = _get_body_container()
					
					if body_container:
						var control = body_container as Control
						var global_pos = mouse_event.global_position
						var element_rect = control.get_global_rect()
						mouse_info["x"] = global_pos.x - element_rect.position.x
						mouse_info["y"] = global_pos.y - element_rect.position.y
					
					_execute_lua_callback(subscription, [mouse_info])
	
	elif event is InputEventMouseMotion:
		var mouse_event = event as InputEventMouseMotion
		for subscription_id in event_subscriptions:
			var subscription = event_subscriptions[subscription_id]
			if subscription.element_id == "body" and subscription.connected_signal == "input_mousemove":
				if subscription.event_name == "mousemove":
					_handle_mousemove_event(mouse_event, subscription)

func _get_element_relative_mouse_position(mouse_event: InputEvent, element_id: String) -> Dictionary:
	var dom_node = dom_parser.parse_result.dom_nodes.get(element_id, null)
	if not dom_node or not dom_node is Control:
		return {"x": 0, "y": 0}
	
	var control = dom_node as Control
	var global_pos: Vector2
	
	if mouse_event is InputEventMouseButton:
		global_pos = (mouse_event as InputEventMouseButton).global_position
	elif mouse_event is InputEventMouseMotion:
		global_pos = (mouse_event as InputEventMouseMotion).global_position
	else:
		return {"x": 0, "y": 0}
	
	var element_rect = control.get_global_rect()
	var local_x = global_pos.x - element_rect.position.x
	var local_y = global_pos.y - element_rect.position.y
	
	return {
		"x": local_x,
		"y": local_y
	}

func _handle_mousemove_event(mouse_event: InputEventMouseMotion, subscription: EventSubscription) -> void:
	var body_container = _get_body_container()
	if not body_container:
		return
	
	var control = body_container as Control
	var global_pos = mouse_event.global_position
	var element_rect = control.get_global_rect()
	var local_x = global_pos.x - element_rect.position.x
	var local_y = global_pos.y - element_rect.position.y
	
	var mouse_info = {
		"x": local_x,
		"y": local_y,
		"deltaX": mouse_event.relative.x,
		"deltaY": mouse_event.relative.y
	}
	_execute_lua_callback(subscription, [mouse_info])

func _get_body_container() -> Control:
	# Try to get body from DOM registry first
	var body_container = dom_parser.parse_result.dom_nodes.get("body", null)
	
	# We fallback to finding the active website container, as it seems theres a bug where body can be null in this context
	if not body_container:
		var main_scene = Engine.get_main_loop().current_scene
		if main_scene and main_scene.has_method("get_active_website_container"):
			body_container = main_scene.get_active_website_container()
		else:
			body_container = Engine.get_main_loop().current_scene.website_container
			if body_container and body_container.get_parent() is MarginContainer:
				body_container = body_container.get_parent()
	
	if body_container and body_container is Control:
		return body_container as Control
	
	return null

# Input event handlers
func _on_input_text_changed(new_text: String, subscription: EventSubscription) -> void:
	_execute_input_event_callback(subscription, {"value": new_text})

func _on_input_focus_lost(subscription: EventSubscription) -> void:
	if not event_subscriptions.has(subscription.id):
		return
	
	# Get the current text value from the input node
	var dom_node = dom_parser.parse_result.dom_nodes.get(subscription.element_id, null)
	if dom_node:
		var current_text = ""
		if dom_node.has_method("get_text"):
			current_text = dom_node.get_text()
		elif "text" in dom_node:
			current_text = dom_node.text
		else:
			var element = dom_parser.find_by_id(subscription.element_id)
			if element:
				current_text = element.text_content
		
		var event_info = {"value": current_text}
		_execute_lua_callback(subscription, [event_info])

func _on_input_value_changed(new_value, subscription: EventSubscription) -> void:
	_execute_input_event_callback(subscription, {"value": new_value})

func _on_input_color_changed(new_color: Color, subscription: EventSubscription) -> void:
	_execute_input_event_callback(subscription, {"value": "#" + new_color.to_html(false)})

func _on_input_toggled(pressed: bool, subscription: EventSubscription) -> void:
	_execute_input_event_callback(subscription, {"value": pressed})

func _on_input_item_selected(index: int, subscription: EventSubscription) -> void:
	if not event_subscriptions.has(subscription.id):
		return
	
	# Get value from OptionButton
	var dom_node = dom_parser.parse_result.dom_nodes.get(subscription.element_id, null)
	var value = ""
	var text = ""
	
	if dom_node and dom_node is OptionButton:
		var option_button = dom_node as OptionButton
		text = option_button.get_item_text(index)
		# Get actual value attribute (stored as metadata)
		var metadata = option_button.get_item_metadata(index)
		value = str(metadata) if metadata != null else text
	
	var event_info = {"index": index, "value": value, "text": text}
	_execute_lua_callback(subscription, [event_info])

func _on_file_selected(file_path: String, subscription: EventSubscription) -> void:
	if not event_subscriptions.has(subscription.id):
		return
	
	var dom_node = dom_parser.parse_result.dom_nodes.get(subscription.element_id, null)
	
	if dom_node:
		var file_container = dom_node.get_parent() # FileContainer (HBoxContainer)
		if file_container:
			var input_element = file_container.get_parent() # Input Control
			if input_element and input_element.has_method("get_file_info"):
				var file_info = input_element.get_file_info()
				if not file_info.is_empty():
					_execute_lua_callback(subscription, [file_info])
					return
	
	# Fallback
	var file_name = file_path.get_file()
	_execute_lua_callback(subscription, [{"fileName": file_name}])

func _on_date_selected_text(date_text: String, subscription: EventSubscription) -> void:
	if not event_subscriptions.has(subscription.id):
		return

	var event_info = {"value": date_text}
	_execute_lua_callback(subscription, [event_info])

func _on_form_submit(subscription: EventSubscription) -> void:
	if not event_subscriptions.has(subscription.id):
		return
	
	# Find parent form
	var form_data = {}
	var element = dom_parser.find_by_id(subscription.element_id)
	if element:
		var form_element = element.parent
		while form_element and form_element.tag_name != "form":
			form_element = form_element.parent
		
		if form_element:
			var form_dom_node = dom_parser.parse_result.dom_nodes.get(form_element.get_attribute("id"), null)
			if form_dom_node and form_dom_node.has_method("submit_form"):
				form_data = form_dom_node.submit_form()
	
	var event_info = {"data": form_data}
	_execute_lua_callback(subscription, [event_info])

func _on_text_submit(text: String, subscription: EventSubscription) -> void:
	if not event_subscriptions.has(subscription.id):
		return
	
	var event_info = {"value": text}
	_execute_lua_callback(subscription, [event_info])

# DOM node utilities
func get_dom_node(node: Node, purpose: String = "general") -> Node:
	if not node:
		return null
	
	if node is MarginContainer and node.get_child_count() > 0: 
		node = node.get_child(0)
	
	if not node:
		return null
	
	match purpose:
		"signal":
			if node is HTMLButton:
				return node.get_node_or_null("ButtonNode")
			elif node is HBoxContainer and node.get_node_or_null("ButtonNode"):
				return node.get_node_or_null("ButtonNode")
			elif node is RichTextLabel:
				return node
			elif node.has_method("get") and node.get("rich_text_label"):
				return node.get("rich_text_label")
			elif node.get_node_or_null("RichTextLabel"):
				return node.get_node_or_null("RichTextLabel")
			elif node is LineEdit or node is TextEdit or node is SpinBox or node is HSlider:
				return node
			elif node is CheckBox or node is ColorPickerButton or node is OptionButton:
				return node
			else:
				return node
		"text":
			if node.has_method("set_text") and node.has_method("get_text"):
				return node
			elif node is RichTextLabel:
				return node
			elif node.has_method("get") and node.get("rich_text_label"):
				return node.get("rich_text_label")
			elif node.get_node_or_null("RichTextLabel"):
				return node.get_node_or_null("RichTextLabel")
			else:
				if "text" in node:
					return node
				return null
		"general":
			if node is HTMLButton:
				return node.get_node_or_null("ButtonNode")
			elif node is RichTextLabel:
				return node
			elif node.get_node_or_null("RichTextLabel"):
				return node.get_node_or_null("RichTextLabel")
			else:
				return node
	
	return node

# Main execution function
func execute_lua_script(code: String, chunk_name: String = "dostring"):
	if not threaded_vm.lua_thread or not threaded_vm.lua_thread.is_alive():
		# Start the thread if it's not running
		threaded_vm.start_lua_thread(dom_parser, self)
	
	script_start_time = Time.get_ticks_msec() / 1000.0
	threaded_vm.execute_script_async(code, chunk_name)

func _on_threaded_script_completed(_result: Dictionary):
	pass

func _on_threaded_script_error(error_message: String):
	Trace.trace_error("RuntimeError: " + error_message)

func _on_print_output(message: Dictionary):
	var message_strings: Array[String] = []
	for part in message.parts:
		if part.type == "table":
			message_strings.append(str(part.data))
		else:
			message_strings.append(part.data)
	var formatted_message = "\t".join(message_strings)
	Trace.get_instance().log_message.emit(formatted_message, "lua", Time.get_ticks_msec() / 1000.0)

func kill_script_execution():
	threaded_vm.stop_lua_thread()
	# Restart a fresh thread for future scripts
	threaded_vm.start_lua_thread(dom_parser, self)

func is_script_hanging() -> bool:
	return threaded_vm.lua_thread != null and threaded_vm.lua_thread.is_alive()

func get_script_runtime() -> float:
	if script_start_time > 0 and is_script_hanging():
		return (Time.get_ticks_msec() / 1000.0) - script_start_time
	return 0.0

func _handle_dom_operation(operation: Dictionary):
	match operation.type:
		"register_event":
			_handle_event_registration(operation)
		"register_body_event":
			_handle_body_event_registration(operation)
		"set_text":
			_handle_text_setting(operation)
		"get_text":
			_handle_text_getting(operation)
		"append_element":
			LuaDOMUtils.handle_element_append(operation, dom_parser)
		"add_class":
			LuaClassListUtils.handle_add_class(operation, dom_parser)
		"remove_class":
			LuaClassListUtils.handle_remove_class(operation, dom_parser)
		"toggle_class":
			LuaClassListUtils.handle_toggle_class(operation, dom_parser)
		"remove_element":
			LuaDOMUtils.handle_element_remove(operation, dom_parser)
		"insert_before":
			LuaDOMUtils.handle_insert_before(operation, dom_parser)
		"insert_after":
			LuaDOMUtils.handle_insert_after(operation, dom_parser)
		"replace_child":
			LuaDOMUtils.handle_replace_child(operation, dom_parser, self)
		"focus_element":
			_handle_element_focus(operation)
		"unfocus_element":
			_handle_element_unfocus(operation)
		"canvas_fillRect":
			LuaCanvasUtils.handle_canvas_fillRect(operation, dom_parser)
		"canvas_strokeRect":
			LuaCanvasUtils.handle_canvas_strokeRect(operation, dom_parser)
		"canvas_clearRect":
			LuaCanvasUtils.handle_canvas_clearRect(operation, dom_parser)
		"canvas_drawCircle":
			LuaCanvasUtils.handle_canvas_drawCircle(operation, dom_parser)
		"canvas_drawText":
			LuaCanvasUtils.handle_canvas_drawText(operation, dom_parser)
		"canvas_source":
			LuaCanvasUtils.handle_canvas_source(operation, dom_parser)
		"canvas_beginPath":
			LuaCanvasUtils.handle_canvas_beginPath(operation, dom_parser)
		"canvas_closePath":
			LuaCanvasUtils.handle_canvas_closePath(operation, dom_parser)
		"canvas_moveTo":
			LuaCanvasUtils.handle_canvas_moveTo(operation, dom_parser)
		"canvas_lineTo":
			LuaCanvasUtils.handle_canvas_lineTo(operation, dom_parser)
		"canvas_arc":
			LuaCanvasUtils.handle_canvas_arc(operation, dom_parser)
		"canvas_stroke":
			LuaCanvasUtils.handle_canvas_stroke(operation, dom_parser)
		"canvas_fill":
			LuaCanvasUtils.handle_canvas_fill(operation, dom_parser)
		# Transformation operations
		"canvas_save":
			LuaCanvasUtils.handle_canvas_save(operation, dom_parser)
		"canvas_restore":
			LuaCanvasUtils.handle_canvas_restore(operation, dom_parser)
		"canvas_translate":
			LuaCanvasUtils.handle_canvas_translate(operation, dom_parser)
		"canvas_rotate":
			LuaCanvasUtils.handle_canvas_rotate(operation, dom_parser)
		"canvas_scale":
			LuaCanvasUtils.handle_canvas_scale(operation, dom_parser)
		"canvas_quadraticCurveTo":
			LuaCanvasUtils.handle_canvas_quadraticCurveTo(operation, dom_parser)
		"canvas_bezierCurveTo":
			LuaCanvasUtils.handle_canvas_bezierCurveTo(operation, dom_parser)
		# Style property operations
		"canvas_setStrokeStyle":
			LuaCanvasUtils.handle_canvas_setStrokeStyle(operation, dom_parser)
		"canvas_setFillStyle":
			LuaCanvasUtils.handle_canvas_setFillStyle(operation, dom_parser)
		"canvas_setLineWidth":
			LuaCanvasUtils.handle_canvas_setLineWidth(operation, dom_parser)
		"canvas_setFont":
			LuaCanvasUtils.handle_canvas_setFont(operation, dom_parser)
		"request_download":
			_handle_download_request(operation)
		_:
			pass # Unknown operation type, ignore

func _handle_event_registration(operation: Dictionary):
	var selector: String = operation.selector
	var event_name: String = operation.event_name
	var callback_ref: int = operation.callback_ref
	
	var element = SelectorUtils.find_first_matching(selector, dom_parser.parse_result.all_elements)
	if not element:
		return
	
	var element_id = get_or_assign_element_id(element)
	
	# Create subscription for threaded callback
	var subscription = EventSubscription.new()
	subscription.id = next_subscription_id
	next_subscription_id += 1
	subscription.element_id = element_id
	subscription.event_name = event_name
	subscription.callback_ref = callback_ref
	subscription.vm = threaded_vm.lua_vm if threaded_vm else null
	subscription.lua_api = self
	
	event_subscriptions[subscription.id] = subscription
	
	# Connect to DOM element
	var dom_node = dom_parser.parse_result.dom_nodes.get(element_id, null)
	if dom_node:
		var signal_node = get_dom_node(dom_node, "signal")
		LuaEventUtils.connect_element_event(signal_node, event_name, subscription)

func _handle_text_setting(operation: Dictionary):
	var selector: String = operation.selector
	var text: String = operation.text
	
	var element = SelectorUtils.find_first_matching(selector, dom_parser.parse_result.all_elements)
	if element:
		# If the element has a DOM node, update it directly without updating text_content
		var element_id = get_or_assign_element_id(element)
		var dom_node = dom_parser.parse_result.dom_nodes.get(element_id, null)
		
		if not dom_node:
			dom_node = dom_parser.parse_result.dom_nodes.get(element, null)
		
		if dom_node:
			if element.tag_name == "button":
				var button_node = dom_node.get_node_or_null("ButtonNode")
				if button_node and button_node is Button:
					button_node.text = text
					element.text_content = text
					return
			
			if element.tag_name == "p" and dom_node.has_method("set_text"):
				dom_node.set_text(text)
				element.text_content = text
				return
		
		element.text_content = text
		
		if dom_node:
			var text_node = get_dom_node(dom_node, "text")
			if text_node:
				if text_node is RichTextLabel:
					element.text_content = text
					StyleManager.apply_styles_to_label(text_node, dom_parser.get_element_styles_with_inheritance(element, "", []), element, dom_parser, text)
					try_apply_auto_resize(text_node)
				elif text_node.has_method("set_text"):
					text_node.set_text(text)
				elif "text" in text_node:
					text_node.text = text
					try_apply_auto_resize(text_node)
			else:
				var rich_text_label = _find_rich_text_label_recursive(dom_node)
				if rich_text_label:
					StyleManager.apply_styles_to_label(rich_text_label, dom_parser.get_element_styles_with_inheritance(element, "", []), element, dom_parser, text)
					try_apply_auto_resize(rich_text_label)

func try_apply_auto_resize(text_node: Node) -> void:
	var parent = text_node.get_parent()
	if parent and parent.has_method("_apply_auto_resize_to_label"):
		parent.call_deferred("_apply_auto_resize_to_label", text_node)

func _find_rich_text_label_recursive(node: Node) -> RichTextLabel:
	if node is RichTextLabel:
		return node
	
	for child in node.get_children():
		var result = _find_rich_text_label_recursive(child)
		if result:
			return result
	
	return null

func _handle_text_getting(operation: Dictionary):
	var selector: String = operation.selector
	
	var element = SelectorUtils.find_first_matching(selector, dom_parser.parse_result.all_elements)
	if element:
		return element.text_content
	return ""

func _handle_element_focus(operation: Dictionary):
	var element_id: String = operation.element_id
	
	var dom_node = dom_parser.parse_result.dom_nodes.get(element_id, null)
	if not dom_node:
		return
	
	var focusable_control = _find_focusable_control(dom_node)
	if focusable_control and focusable_control.has_method("grab_focus"):
		focusable_control.call_deferred("grab_focus")

func _handle_element_unfocus(operation: Dictionary):
	var element_id: String = operation.element_id
	
	var dom_node = dom_parser.parse_result.dom_nodes.get(element_id, null)
	if not dom_node:
		return
	
	var focusable_control = _find_focusable_control(dom_node)
	if focusable_control and focusable_control.has_method("release_focus"):
		focusable_control.call_deferred("release_focus")

func _find_focusable_control(node: Node) -> Control:
	if not node:
		return null
	
	if node is Control and node.focus_mode != Control.FOCUS_NONE and node.has_method("grab_focus"):
		return node
	
	if node.has_method("get_children"):
		for child in node.get_children():
			if child.visible and child is Control:
				if child is LineEdit or child is TextEdit or child is SpinBox or child is OptionButton:
					if child.focus_mode != Control.FOCUS_NONE:
						return child
				
				if child is SpinBox:
					var line_edit = child.get_line_edit()
					if line_edit and line_edit.focus_mode != Control.FOCUS_NONE:
						return line_edit
				
				var focusable_child = _find_focusable_control(child)
				if focusable_child:
					return focusable_child
	
	return null

func _handle_body_event_registration(operation: Dictionary):
	var event_name: String = operation.event_name
	var callback_ref: int = operation.callback_ref
	var subscription_id: int = operation.get("subscription_id", -1)
	
	# Use provided subscription_id or generate a new one
	if subscription_id == -1:
		subscription_id = next_subscription_id
		next_subscription_id += 1
	
	# Create subscription for threaded callback
	var subscription = EventSubscription.new()
	subscription.id = subscription_id
	subscription.element_id = "body"
	subscription.event_name = event_name
	subscription.callback_ref = callback_ref
	subscription.vm = threaded_vm.lua_vm if threaded_vm else null
	subscription.lua_api = self
	
	event_subscriptions[subscription.id] = subscription
	
	# Connect to body events
	LuaEventUtils.connect_body_event(event_name, subscription, self)

func _register_event_on_main_thread(element_id: String, event_name: String, callback_ref: int, subscription_id: int = -1):
	# This runs on the main thread - safe to access DOM nodes
	var dom_node = dom_parser.parse_result.dom_nodes.get(element_id, null)
	if not dom_node:
		var pending_registration = {
			"element_id": element_id,
			"event_name": event_name,
			"callback_ref": callback_ref,
			"subscription_id": subscription_id if subscription_id != -1 else next_subscription_id
		}
		
		if subscription_id == -1:
			next_subscription_id += 1
		
		pending_event_registrations.append(pending_registration)
		
		call_deferred("_process_pending_event_registrations")
		return
	
	# Use provided subscription_id or generate a new one
	if subscription_id == -1:
		subscription_id = next_subscription_id
		next_subscription_id += 1
	
	# Create subscription using the threaded VM's callback reference
	var subscription = EventSubscription.new()
	subscription.id = subscription_id
	subscription.element_id = element_id
	subscription.event_name = event_name
	subscription.callback_ref = callback_ref
	subscription.vm = threaded_vm.lua_vm if threaded_vm else null
	subscription.lua_api = self
	
	event_subscriptions[subscription.id] = subscription
	
	var signal_node = get_dom_node(dom_node, "signal")
	LuaEventUtils.connect_element_event(signal_node, event_name, subscription)

func _process_pending_event_registrations():
	
	var i = 0
	while i < pending_event_registrations.size():
		var registration = pending_event_registrations[i]
		var element_id = registration.element_id
		var dom_node = dom_parser.parse_result.dom_nodes.get(element_id, null)
		
		if dom_node:
			pending_event_registrations.remove_at(i)
			
			_register_event_on_main_thread(
				registration.element_id,
				registration.event_name, 
				registration.callback_ref,
				registration.subscription_id
			)
		else:
			i += 1
	
	if pending_event_registrations.size() > 0:
		call_deferred("_process_pending_event_registrations")

func _unsubscribe_event_on_main_thread(subscription_id: int):
	# This runs on the main thread - safe to cleanup event subscriptions
	var subscription = event_subscriptions.get(subscription_id, null)
	if subscription:
		LuaEventUtils.disconnect_subscription(subscription, self)
		event_subscriptions.erase(subscription_id)
		
		# Clean up Lua callback reference
		if subscription.callback_ref and subscription.vm:
			subscription.vm.lua_pushnil()
			subscription.vm.lua_rawseti(subscription.vm.LUA_REGISTRYINDEX, subscription.callback_ref)

func _notification(what: int):
	if what == NOTIFICATION_PREDELETE:
		if timeout_manager:
			timeout_manager.cleanup_all_timeouts()
		threaded_vm.stop_lua_thread()

func _handle_download_request(operation: Dictionary):
	var download_data = operation.get("download_data", {})
	
	var main_node = Engine.get_main_loop().current_scene
	main_node.download_manager.handle_download_request(download_data)

func _get_element_size_sync(result: Array, element_id: String):
	var dom_node = dom_parser.parse_result.dom_nodes.get(element_id, null)
	if dom_node and dom_node is Control:
		var control = dom_node as Control
		result[0] = control.size.x
		result[1] = control.size.y
		result[2] = true # completion flag
		return
	
	# Fallback
	result[0] = 0.0
	result[1] = 0.0
	result[2] = true # completion flag

func _get_element_position_sync(result: Array, element_id: String):
	var dom_node = dom_parser.parse_result.dom_nodes.get(element_id, null)
	if dom_node and dom_node is Control:
		var control = dom_node as Control
		result[0] = control.position.x
		result[1] = control.position.y
		result[2] = true # completion flag
		return
	
	# Fallback
	result[0] = 0.0
	result[1] = 0.0
	result[2] = true # completion flag
