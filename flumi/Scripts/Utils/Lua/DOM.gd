class_name LuaDOMUtils
extends RefCounted

# DOM traversal properties (read-only)
static func get_element_parent_handler(vm: LuauVM, dom_parser: HTMLParser, lua_api: LuaAPI) -> int:
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var element = find_element_by_id(element_id, dom_parser)
	if not element or not element.parent:
		vm.lua_pushnil()
		return 1
	
	create_element_wrapper(vm, element.parent, lua_api)
	return 1

static func get_element_next_sibling_handler(vm: LuauVM, dom_parser: HTMLParser, lua_api: LuaAPI) -> int:
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var element = find_element_by_id(element_id, dom_parser)
	if not element or not element.parent:
		vm.lua_pushnil()
		return 1
	
	var siblings = element.parent.children
	var current_index = siblings.find(element)
	
	if current_index >= 0 and current_index < siblings.size() - 1:
		var next_sibling = siblings[current_index + 1]
		create_element_wrapper(vm, next_sibling, lua_api)
	else:
		vm.lua_pushnil()
	
	return 1

static func get_element_previous_sibling_handler(vm: LuauVM, dom_parser: HTMLParser, lua_api: LuaAPI) -> int:
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var element = find_element_by_id(element_id, dom_parser)
	if not element or not element.parent:
		vm.lua_pushnil()
		return 1
	
	var siblings = element.parent.children
	var current_index = siblings.find(element)
	
	if current_index > 0:
		var prev_sibling = siblings[current_index - 1]
		create_element_wrapper(vm, prev_sibling, lua_api)
	else:
		vm.lua_pushnil()
	
	return 1

static func get_element_first_child_handler(vm: LuauVM, dom_parser: HTMLParser, lua_api: LuaAPI) -> int:
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var element = find_element_by_id(element_id, dom_parser)
	if not element or element.children.is_empty():
		vm.lua_pushnil()
		return 1
	
	create_element_wrapper(vm, element.children[0], lua_api)
	return 1

static func get_element_last_child_handler(vm: LuauVM, dom_parser: HTMLParser, lua_api: LuaAPI) -> int:
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var element = find_element_by_id(element_id, dom_parser)
	if not element or element.children.is_empty():
		vm.lua_pushnil()
		return 1
	
	create_element_wrapper(vm, element.children[-1], lua_api)
	return 1

# DOM Manipulation Methods

static func handle_element_append(operation: Dictionary, dom_parser: HTMLParser) -> void:
	var parent_id: String = operation.parent_id
	var child_id: String = operation.child_id
	
	# Find the parent and child elements
	var parent_element = dom_parser.find_by_id(parent_id) if parent_id != "body" else dom_parser.find_first("body")
	var child_element = dom_parser.find_by_id(child_id) if child_id != "body" else dom_parser.find_first("body")
	
	if not parent_element or not child_element:
		return
	
	# Remove child from its current parent if it has one
	if child_element.parent:
		var current_parent = child_element.parent
		var current_index = current_parent.children.find(child_element)
		if current_index >= 0:
			current_parent.children.remove_at(current_index)
	
	# Append child to new parent
	child_element.parent = parent_element
	parent_element.children.append(child_element)
	
	# Handle visual rendering if parent is already rendered
	var parent_dom_node: Node = null
	if parent_id == "body":
		var main_scene = Engine.get_main_loop().current_scene
		parent_dom_node = main_scene.website_container
	else:
		parent_dom_node = dom_parser.parse_result.dom_nodes.get(parent_id, null)
	
	if parent_dom_node:
		# Render the appended element
		render_new_element.call_deferred(child_element, parent_dom_node, dom_parser)

static func handle_element_remove(operation: Dictionary, dom_parser: HTMLParser) -> void:
	var element_id: String = operation.element_id
	
	var element = dom_parser.find_by_id(element_id) if element_id != "body" else dom_parser.find_first("body")
	if element and element.parent:
		# Remove element from HTML parser tree
		var parent_element = element.parent
		var element_index = parent_element.children.find(element)
		if element_index >= 0:
			parent_element.children.remove_at(element_index)
			element.parent = null
		
	# Remove element from DOM tree
	var dom_node = dom_parser.parse_result.dom_nodes.get(element_id, null)
	if dom_node and dom_node.get_parent():
		dom_node.get_parent().remove_child(dom_node)
		dom_node.queue_free()
		dom_parser.parse_result.dom_nodes.erase(element_id)
	
	# Remove from parser's all_elements list
	var all_elements_index = dom_parser.parse_result.all_elements.find(element)
	if all_elements_index >= 0:
		dom_parser.parse_result.all_elements.remove_at(all_elements_index)

static func handle_insert_before(operation: Dictionary, dom_parser: HTMLParser) -> void:
	var parent_id: String = operation.parent_id
	var new_child_id: String = operation.new_child_id
	var reference_child_id: String = operation.reference_child_id
	
	# Find the elements
	var parent_element = dom_parser.find_by_id(parent_id) if parent_id != "body" else dom_parser.find_first("body")
	var new_child_element = dom_parser.find_by_id(new_child_id) if new_child_id != "body" else dom_parser.find_first("body")
	var reference_child_element = dom_parser.find_by_id(reference_child_id) if reference_child_id != "body" else dom_parser.find_first("body")
	
	if not parent_element or not new_child_element or not reference_child_element:
		return
	
	# Remove new child from its current parent if it has one
	if new_child_element.parent:
		var current_parent = new_child_element.parent
		var current_index = current_parent.children.find(new_child_element)
		if current_index >= 0:
			current_parent.children.remove_at(current_index)
	
	# Find reference child position in parent
	var reference_index = parent_element.children.find(reference_child_element)
	if reference_index >= 0:
		# Insert new child before reference child
		new_child_element.parent = parent_element
		parent_element.children.insert(reference_index, new_child_element)
		
		# Handle visual rendering
		var parent_dom_node: Node = null
		if parent_id == "body":
			var main_scene = Engine.get_main_loop().current_scene
			if main_scene:
				parent_dom_node = main_scene.website_container
		else:
			parent_dom_node = dom_parser.parse_result.dom_nodes.get(parent_id, null)
		
		if parent_dom_node:
			handle_visual_insertion_by_reference(parent_id, new_child_element, reference_child_id, true, dom_parser)

static func handle_insert_after(operation: Dictionary, dom_parser: HTMLParser) -> void:
	var parent_id: String = operation.parent_id
	var new_child_id: String = operation.new_child_id
	var reference_child_id: String = operation.reference_child_id
	
	# Find the elements
	var parent_element = dom_parser.find_by_id(parent_id) if parent_id != "body" else dom_parser.find_first("body")
	var new_child_element = dom_parser.find_by_id(new_child_id) if new_child_id != "body" else dom_parser.find_first("body")
	var reference_child_element = dom_parser.find_by_id(reference_child_id) if reference_child_id != "body" else dom_parser.find_first("body")
	
	if not parent_element or not new_child_element or not reference_child_element:
		return
	
	# Remove new child from its current parent if it has one
	if new_child_element.parent:
		var current_parent = new_child_element.parent
		var current_index = current_parent.children.find(new_child_element)
		if current_index >= 0:
			current_parent.children.remove_at(current_index)
	
	# Find reference child position in parent
	var reference_index = parent_element.children.find(reference_child_element)
	if reference_index >= 0:
		# Insert new child after reference child
		new_child_element.parent = parent_element
		parent_element.children.insert(reference_index + 1, new_child_element)
		
		# Handle visual rendering
		var parent_dom_node: Node = null
		if parent_id == "body":
			var main_scene = Engine.get_main_loop().current_scene
			if main_scene:
				parent_dom_node = main_scene.website_container
		else:
			parent_dom_node = dom_parser.parse_result.dom_nodes.get(parent_id, null)
		
		if parent_dom_node:
			handle_visual_insertion_by_reference(parent_id, new_child_element, reference_child_id, false, dom_parser)

static func handle_replace_child(operation: Dictionary, dom_parser: HTMLParser, lua_api) -> void:
	var parent_id: String = operation.parent_id
	var new_child_id: String = operation.new_child_id
	var old_child_id: String = operation.old_child_id
	
	# Find the elements
	var parent_element = dom_parser.find_by_id(parent_id) if parent_id != "body" else dom_parser.find_first("body")
	var new_child_element = dom_parser.find_by_id(new_child_id) if new_child_id != "body" else dom_parser.find_first("body")
	var old_child_element = dom_parser.find_by_id(old_child_id) if old_child_id != "body" else dom_parser.find_first("body")
	
	if not parent_element or not new_child_element or not old_child_element:
		return
	
	# Remove new child from its current parent if it has one
	if new_child_element.parent:
		var current_parent = new_child_element.parent
		var current_index = current_parent.children.find(new_child_element)
		if current_index >= 0:
			current_parent.children.remove_at(current_index)
	
	# Find old child position in parent
	var old_index = parent_element.children.find(old_child_element)
	if old_index >= 0:
		# Replace old child with new child
		new_child_element.parent = parent_element
		parent_element.children[old_index] = new_child_element
		old_child_element.parent = null
		
		# Handle visual rendering
		handle_visual_replacement(old_child_id, new_child_element, parent_id, dom_parser, lua_api)

static func render_new_element(element: HTMLParser.HTMLElement, parent_node: Node, dom_parser: HTMLParser) -> void:
	# Get reference to main scene for rendering
	var main_scene = Engine.get_main_loop().current_scene
	if not main_scene:
		return
	
	
	# Create the visual node for the element
	var element_node = await main_scene.create_element_node(element, dom_parser)
	if not element_node:
		Trace.trace_log("Failed to create visual node for element: " + str(element))
		return

	# Set metadata so ul/ol can detect dynamically added li elements
	element_node.set_meta("html_element", element)

	# Register the DOM node
	dom_parser.register_dom_node(element, element_node)
	# Add to parent - handle body special case
	var container_node = parent_node
	if parent_node is MarginContainer and parent_node.get_child_count() > 0:
		container_node = parent_node.get_child(0)
	elif parent_node == main_scene.website_container:
		container_node = parent_node

	main_scene.safe_add_child(container_node, element_node)

static func _get_input_value(element: HTMLParser.HTMLElement, dom_node: Node) -> Variant:
	var input_type = element.get_attribute("type").to_lower()
	
	match input_type:
		"checkbox", "radio":
			if dom_node is CheckBox:
				return dom_node.button_pressed
			return false
		"color":
			if dom_node is ColorPickerButton:
				return "#" + dom_node.color.to_html(false)
			return "#ffffff"
		"range":
			if dom_node is HSlider:
				return dom_node.value
			return 0.0
		"number":
			if dom_node is SpinBox:
				return dom_node.value
			return 0.0
		"file":
			# For file inputs, need to find the input control that has get_file_info method
			var input_control = _find_input_control_with_file_info(dom_node)
			if input_control:
				var file_info = input_control.get_file_info()
				return file_info.get("fileName", "")
			return ""
		"date":
			if dom_node is DateButton:
				if dom_node.has_method("get_date_text"):
					return dom_node.get_date_text()
			return ""
		_: # text, password, email, etc.
			if dom_node is LineEdit:
				return dom_node.text
			elif dom_node is TextEdit:
				return dom_node.text
			return ""

static func _find_input_control_with_file_info(node: Node) -> Node:
	if node and node.has_method("get_file_info"):
		return node
	
	var current = node
	while current:
		current = current.get_parent()
		if current and current.has_method("get_file_info"):
			return current
	
	return null

static func _get_select_value(_element: HTMLParser.HTMLElement, dom_node: Node) -> String:
	if dom_node is OptionButton:
		var option_button = dom_node as OptionButton
		var selected_index = option_button.selected
		if selected_index >= 0 and selected_index < option_button.get_item_count():
			var metadata = option_button.get_item_metadata(selected_index)
			if metadata:
				return str(metadata)
			else:
				return option_button.get_item_text(selected_index)
	return ""

static func _set_select_value(_element: HTMLParser.HTMLElement, dom_node: Node, value: Variant) -> void:
	if dom_node is OptionButton:
		var option_button = dom_node as OptionButton
		var target_value = str(value)
		
		# Find the correct index to select
		var selected_index = -1
		
		# Find option with matching value
		for i in range(option_button.get_item_count()):
			var metadata = option_button.get_item_metadata(i)
			var option_value = str(metadata) if metadata else option_button.get_item_text(i)
			if option_value == target_value:
				selected_index = i
				break
		
		# If no matching value found, try to find by text
		if selected_index == -1:
			for i in range(option_button.get_item_count()):
				if option_button.get_item_text(i) == target_value:
					selected_index = i
					break
		
		# Use call_deferred to set the property on main thread
		if selected_index != -1:
			option_button.call_deferred("set", "selected", selected_index)

static func _set_input_value(element: HTMLParser.HTMLElement, dom_node: Node, value: Variant) -> void:
	var input_type = element.get_attribute("type").to_lower()
	
	match input_type:
		"checkbox", "radio":
			if dom_node is CheckBox:
				dom_node.call_deferred("set", "button_pressed", bool(value))
		"color":
			if dom_node is ColorPickerButton:
				var color_value = str(value)
				if color_value.begins_with("#"):
					var color = Color.from_string(color_value, Color.WHITE)
					dom_node.call_deferred("set", "color", color)
		"range":
			if dom_node is HSlider:
				dom_node.call_deferred("set", "value", float(value))
		"number":
			if dom_node is SpinBox:
				dom_node.call_deferred("set", "value", float(value))
		"date":
			if dom_node is DateButton and dom_node.has_method("set_date_from_string"):
				dom_node.call_deferred("set_date_from_string", str(value))
		_: # text, password, email, etc.
			if dom_node is LineEdit:
				dom_node.call_deferred("set", "text", str(value))
			elif dom_node is TextEdit:
				dom_node.call_deferred("set", "text", str(value))

# Helper functions
static func find_element_by_id(element_id: String, dom_parser: HTMLParser) -> HTMLParser.HTMLElement:
	if element_id == "body":
		return dom_parser.find_first("body")
	else:
		return dom_parser.find_by_id(element_id)

static func clone_element(element: HTMLParser.HTMLElement, deep: bool) -> HTMLParser.HTMLElement:
	var cloned = HTMLParser.HTMLElement.new(element.tag_name)
	
	for attr_name in element.attributes:
		if attr_name != "id":
			cloned.attributes[attr_name] = element.attributes[attr_name]
	
	cloned.text_content = element.text_content
	
	if deep:
		for child in element.children:
			var cloned_child = clone_element(child, true)
			cloned_child.parent = cloned
			cloned.children.append(cloned_child)
	
	return cloned


static func handle_visual_insertion_by_reference(parent_element_id: String, new_child_element: HTMLParser.HTMLElement, reference_element_id: String, insert_before: bool, dom_parser: HTMLParser) -> void:
	var parent_dom_node: Node = null
	if parent_element_id == "body":
		var main_scene = Engine.get_main_loop().current_scene
		if main_scene:
			parent_dom_node = main_scene.website_container
	else:
		parent_dom_node = dom_parser.parse_result.dom_nodes.get(parent_element_id, null)
	
	if parent_dom_node:
		render_new_element_by_reference.call_deferred(new_child_element, parent_dom_node, reference_element_id, insert_before, dom_parser)

static func handle_visual_replacement(old_child_element_id: String, new_child_element: HTMLParser.HTMLElement, parent_element_id: String, dom_parser: HTMLParser, lua_api) -> void:
	var old_dom_node = dom_parser.parse_result.dom_nodes.get(old_child_element_id, null)
	if not old_dom_node:
		return
	
	var parent_container = old_dom_node.get_parent()
	if not parent_container:
		return
	
	var old_position = -1
	for i in parent_container.get_child_count():
		if parent_container.get_child(i) == old_dom_node:
			old_position = i
			break
	
	old_dom_node.queue_free()
	dom_parser.parse_result.dom_nodes.erase(old_child_element_id)
	
	if old_position >= 0:
		var parent_dom_node: Node = null
		if parent_element_id == "body":
			var main_scene = lua_api.get_main_scene()
			if main_scene:
				parent_dom_node = main_scene.website_container
		else:
			parent_dom_node = dom_parser.parse_result.dom_nodes.get(parent_element_id, null)
		
		if parent_dom_node:
			render_new_element_at_position.call_deferred(new_child_element, parent_dom_node, old_position, dom_parser)



static func is_same_element_visual_node(node1: Node, node2: Node) -> bool:
	if node1 == node2:
		return true

	var current = node1
	var node1_grandparent = node1.get_parent()
	if node1_grandparent:
		node1_grandparent = node1_grandparent.get_parent()
	while current:
		if current == node2:
			return true
		var parent = current.get_parent()
		if not parent or (node1_grandparent and current == node1_grandparent):
			break
		current = parent

	current = node2
	var node2_grandparent = node2.get_parent()
	if node2_grandparent:
		node2_grandparent = node2_grandparent.get_parent()
	while current:
		if current == node1:
			return true
		var parent = current.get_parent()
		if not parent or (node2_grandparent and current == node2_grandparent):
			break
		current = parent

	return false

static func render_new_element_at_position(element: HTMLParser.HTMLElement, parent_node: Node, position: int, dom_parser: HTMLParser) -> void:
	var main_scene = Engine.get_main_loop().current_scene.Engine.get_main_loop().current_scene
	if not main_scene:
		return
	
	var element_node = await main_scene.create_element_node(element, dom_parser)
	if not element_node:
		return

	element_node.set_meta("html_element", element)
	dom_parser.register_dom_node(element, element_node)

	var container_node = parent_node
	if parent_node is MarginContainer and parent_node.get_child_count() > 0:
		container_node = parent_node.get_child(0)
	elif parent_node == main_scene.website_container:
		container_node = parent_node

	container_node.add_child(element_node)
	if position >= 0 and position < container_node.get_child_count():
		container_node.move_child(element_node, position)

static func render_new_element_by_reference(element: HTMLParser.HTMLElement, parent_node: Node, reference_element_id: String, insert_before: bool, dom_parser: HTMLParser) -> void:
	var main_scene = Engine.get_main_loop().current_scene.Engine.get_main_loop().current_scene
	if not main_scene:
		return
	
	var reference_dom_node = dom_parser.parse_result.dom_nodes.get(reference_element_id, null)
	if not reference_dom_node:
		return
	
	var container_node = parent_node
	if parent_node is MarginContainer and parent_node.get_child_count() > 0:
		container_node = parent_node.get_child(0)
	elif parent_node == main_scene.website_container:
		container_node = parent_node
	
	var reference_position = -1
	for i in container_node.get_child_count():
		var child = container_node.get_child(i)
		if child == reference_dom_node or is_same_element_visual_node(child, reference_dom_node):
			reference_position = i
			break
	
	if reference_position < 0:
		reference_position = container_node.get_child_count()
	
	var insert_position = reference_position
	if not insert_before:
		insert_position = reference_position + 1
	
	var element_node = await main_scene.create_element_node(element, dom_parser)
	if not element_node:
		return

	element_node.set_meta("html_element", element)
	dom_parser.register_dom_node(element, element_node)
	
	container_node.add_child(element_node)
	if insert_position >= 0 and insert_position < container_node.get_child_count() - 1:
		container_node.move_child(element_node, insert_position)

# Threaded-safe wrapper functions
static func emit_dom_operation(lua_api: LuaAPI, operation: Dictionary) -> void:
	lua_api.threaded_vm.call_deferred("_emit_dom_operation_request", operation)

static func create_element_wrapper(vm: LuauVM, element: HTMLParser.HTMLElement, lua_api: LuaAPI) -> void:
	vm.lua_newtable()
	
	var element_id: String
	if element.tag_name == "body":
		element_id = "body"
	else:
		element_id = element.get_attribute("id")
		if element_id.is_empty():
			element_id = lua_api.get_or_assign_element_id(element)
			element.set_attribute("id", element_id)
	
	vm.lua_pushstring(element_id)
	vm.lua_setfield(-2, "_element_id")
	vm.lua_pushstring(element.tag_name)
	vm.lua_setfield(-2, "_tag_name")
	
	add_element_methods(vm, lua_api)

static func add_element_methods(vm: LuauVM, lua_api: LuaAPI) -> void:
	vm.set_meta("lua_api", lua_api)
	
	vm.lua_pushcallable(LuaAudioUtils._dom_audio_play_handler, "_dom_audio_play")
	vm.lua_setglobal("_dom_audio_play")
	
	vm.lua_pushcallable(LuaAudioUtils._dom_audio_pause_handler, "_dom_audio_pause")
	vm.lua_setglobal("_dom_audio_pause")
	
	vm.lua_pushcallable(LuaDOMUtils._element_on_wrapper, "element.on")
	vm.lua_setfield(-2, "on")
	
	vm.lua_pushcallable(LuaDOMUtils._element_append_wrapper, "element.append")
	vm.lua_setfield(-2, "append")
	
	vm.lua_pushcallable(LuaDOMUtils._element_set_text_wrapper, "element.setText")
	vm.lua_setfield(-2, "setText")
	
	vm.lua_pushcallable(LuaDOMUtils._element_remove_wrapper, "element.remove")
	vm.lua_setfield(-2, "remove")
	
	vm.lua_pushcallable(LuaDOMUtils._element_insert_before_wrapper, "element.insertBefore")
	vm.lua_setfield(-2, "insertBefore")
	
	vm.lua_pushcallable(LuaDOMUtils._element_insert_after_wrapper, "element.insertAfter")
	vm.lua_setfield(-2, "insertAfter")
	
	vm.lua_pushcallable(LuaDOMUtils._element_replace_wrapper, "element.replace")
	vm.lua_setfield(-2, "replace")
	
	vm.lua_pushcallable(LuaDOMUtils._element_clone_wrapper, "element.clone")
	vm.lua_setfield(-2, "clone")

	vm.lua_pushcallable(LuaDOMUtils._element_get_attribute_wrapper, "element.getAttribute")
	vm.lua_setfield(-2, "getAttribute")
	
	vm.lua_pushcallable(LuaDOMUtils._element_set_attribute_wrapper, "element.setAttribute")
	vm.lua_setfield(-2, "setAttribute")
	
	vm.lua_pushcallable(LuaDOMUtils._element_create_tween_wrapper, "element.createTween")
	vm.lua_setfield(-2, "createTween")
	
	vm.lua_pushcallable(LuaDOMUtils._element_show_wrapper, "element.show")
	vm.lua_setfield(-2, "show")
	
	vm.lua_pushcallable(LuaDOMUtils._element_hide_wrapper, "element.hide")
	vm.lua_setfield(-2, "hide")
	
	vm.lua_pushcallable(LuaDOMUtils._element_focus_wrapper, "element.focus")
	vm.lua_setfield(-2, "focus")
	
	vm.lua_pushcallable(LuaDOMUtils._element_unfocus_wrapper, "element.unfocus")
	vm.lua_setfield(-2, "unfocus")
	
	vm.lua_pushcallable(LuaCanvasUtils._element_withContext_wrapper, "element.withContext")
	vm.lua_setfield(-2, "withContext")
	
	add_classlist_support(vm)
	
	vm.lua_newtable()
	vm.lua_pushcallable(LuaDOMUtils._element_index_wrapper, "element.__index")
	vm.lua_setfield(-2, "__index")
	vm.lua_pushcallable(LuaDOMUtils._element_newindex_wrapper, "element.__newindex")
	vm.lua_setfield(-2, "__newindex")
	vm.lua_setmetatable(-2)

static func _element_on_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var event_name: String = vm.luaL_checkstring(2)
	vm.luaL_checktype(3, vm.LUA_TFUNCTION)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var callback_ref = lua_api.next_callback_ref
	lua_api.next_callback_ref += 1
	
	var subscription_id = lua_api.next_subscription_id
	lua_api.next_subscription_id += 1
	
	vm.lua_pushvalue(3)
	vm.lua_rawseti(vm.LUA_REGISTRYINDEX, callback_ref)
	
	lua_api.call_deferred("_register_event_on_main_thread", element_id, event_name, callback_ref, subscription_id)
	
	vm.lua_newtable()
	vm.lua_pushinteger(subscription_id)
	vm.lua_setfield(-2, "_subscription_id")
	
	vm.lua_pushcallable(LuaDOMUtils._unsubscribe_wrapper, "subscription.unsubscribe")
	vm.lua_setfield(-2, "unsubscribe")
	return 1

static func _element_append_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	# Queue append operation for main thread
	vm.luaL_checktype(1, vm.LUA_TTABLE)  # parent
	vm.luaL_checktype(2, vm.LUA_TTABLE)  # child
	
	vm.lua_getfield(1, "_element_id")
	var parent_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	vm.lua_getfield(2, "_element_id")
	var child_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "append_element",
		"parent_id": parent_id,
		"child_id": child_id
	}
	
	emit_dom_operation(lua_api, operation)
	return 0

static func _element_set_text_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var text: String = vm.luaL_checkstring(2)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var element = lua_api.dom_parser.find_by_id(element_id) if element_id != "body" else lua_api.dom_parser.find_first("body")
	if element:
		element.text_content = text
	
	var operation = {
		"type": "set_text",
		"selector": "#" + element_id,
		"text": text
	}
	
	emit_dom_operation(lua_api, operation)
	return 0

static func _element_remove_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	# Get element ID from self table
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "remove_element",
		"element_id": element_id
	}
	
	# Queue operation for main thread
	emit_dom_operation(lua_api, operation)
	return 0

static func _element_insert_before_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	# Get parent element ID from self table
	vm.luaL_checktype(1, vm.LUA_TTABLE)  # parent
	vm.luaL_checktype(2, vm.LUA_TTABLE)  # new_child
	vm.luaL_checktype(3, vm.LUA_TTABLE)  # reference_child
	
	vm.lua_getfield(1, "_element_id")
	var parent_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	vm.lua_getfield(2, "_element_id")
	var new_child_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	vm.lua_getfield(3, "_element_id")
	var reference_child_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "insert_before",
		"parent_id": parent_id,
		"new_child_id": new_child_id,
		"reference_child_id": reference_child_id
	}
	
	emit_dom_operation(lua_api, operation)
	return 0

static func _element_insert_after_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	# Get parent element ID from self table
	vm.luaL_checktype(1, vm.LUA_TTABLE)  # parent
	vm.luaL_checktype(2, vm.LUA_TTABLE)  # new_child
	vm.luaL_checktype(3, vm.LUA_TTABLE)  # reference_child
	
	vm.lua_getfield(1, "_element_id")
	var parent_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	vm.lua_getfield(2, "_element_id")
	var new_child_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	vm.lua_getfield(3, "_element_id")
	var reference_child_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "insert_after",
		"parent_id": parent_id,
		"new_child_id": new_child_id,
		"reference_child_id": reference_child_id
	}
	
	emit_dom_operation(lua_api, operation)
	return 0

static func _element_replace_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	# Get parent element ID from self table
	vm.luaL_checktype(1, vm.LUA_TTABLE)  # parent
	vm.luaL_checktype(2, vm.LUA_TTABLE)  # new_child
	vm.luaL_checktype(3, vm.LUA_TTABLE)  # old_child
	
	vm.lua_getfield(1, "_element_id")
	var parent_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	vm.lua_getfield(2, "_element_id")
	var new_child_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	vm.lua_getfield(3, "_element_id")
	var old_child_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "replace_child",
		"parent_id": parent_id,
		"new_child_id": new_child_id,
		"old_child_id": old_child_id
	}
	
	emit_dom_operation(lua_api, operation)
	return 0

static func _element_clone_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	# Get element ID from self table
	vm.luaL_checktype(1, vm.LUA_TTABLE)  # element
	var deep: bool = true  # Default to deep clone
	
	if vm.lua_gettop() >= 2:
		deep = vm.lua_toboolean(2)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	# Find the element to clone
	var element = lua_api.dom_parser.find_by_id(element_id) if element_id != "body" else lua_api.dom_parser.find_first("body")
	if element:
		var cloned_element = clone_element(element, deep)
		
		# Assign new ID to cloned element
		lua_api.get_or_assign_element_id(cloned_element)
		
		# Add to parser's element collection
		lua_api.dom_parser.parse_result.all_elements.append(cloned_element)
		
		# Create element wrapper for the cloned element
		create_element_wrapper(vm, cloned_element, lua_api)
		return 1
	
	vm.lua_pushnil()
	return 1

static func _element_get_attribute_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		vm.lua_pushnil()
		return 1
	
	# Get element ID from self table
	vm.luaL_checktype(1, vm.LUA_TTABLE)  # element
	var attribute_name: String = vm.luaL_checkstring(2)  # attribute name
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	# Find the element
	var element: HTMLParser.HTMLElement = null
	if element_id == "body":
		element = lua_api.dom_parser.find_first("body")
	else:
		element = lua_api.dom_parser.find_by_id(element_id)
	
	if not element:
		vm.lua_pushnil()
		return 1
	
	# Get the attribute value
	var attribute_value = element.get_attribute(attribute_name)
	if attribute_value.is_empty():
		vm.lua_pushnil()
	else:
		vm.lua_pushstring(attribute_value)
	
	return 1

static func _element_set_attribute_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	# Get element ID from self table
	vm.luaL_checktype(1, vm.LUA_TTABLE)  # element
	var attribute_name: String = vm.luaL_checkstring(2)  # attribute name
	var attribute_value: String = vm.luaL_checkstring(3)  # attribute value
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	# Find the element
	var element: HTMLParser.HTMLElement = null
	if element_id == "body":
		element = lua_api.dom_parser.find_first("body")
	else:
		element = lua_api.dom_parser.find_by_id(element_id)
	
	if not element:
		return 0
	
	# Handle removing attribute when value is empty
	if attribute_value == "":
		element.attributes.erase(attribute_name)
	else:
		element.set_attribute(attribute_name, attribute_value)
	
	# Trigger visual update by calling init() again for DOM nodes (must be on main thread)
	var dom_node = lua_api.dom_parser.parse_result.dom_nodes.get(element_id, null)
	if dom_node and dom_node.has_method("init"):
		dom_node.call_deferred("init", element, lua_api.dom_parser)
	
	return 0

static func _element_index_wrapper(vm: LuauVM) -> int:
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var key: String = vm.luaL_checkstring(2)
	
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	
	vm.lua_getfield(1, "_tag_name")
	var tag_name: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
		
	if tag_name == "audio":
		vm.lua_getfield(1, "_element_id")
		var element_id: String = vm.lua_tostring(-1)
		vm.lua_pop(1)
		return LuaAudioUtils.handle_dom_audio_index(vm, element_id, key)
	
	match key:
		"value":
			if lua_api and (tag_name == "input" or tag_name == "select"):
				vm.lua_getfield(1, "_element_id")
				var element_id: String = vm.lua_tostring(-1)
				vm.lua_pop(1)
				
				var element = lua_api.dom_parser.find_by_id(element_id) if element_id != "body" else lua_api.dom_parser.find_first("body")
				var dom_node = lua_api.dom_parser.parse_result.dom_nodes.get(element_id, null)
				
				if element and dom_node:
					var value_result: String
					if tag_name == "input":
						value_result = str(_get_input_value(element, dom_node))
					elif tag_name == "select":
						value_result = _get_select_value(element, dom_node)
					
					vm.lua_pushstring(value_result)
					return 1
			
			# Fallback to empty string
			vm.lua_pushstring("")
			return 1
		"text":
			if lua_api:
				# Get element ID and find the element
				vm.lua_getfield(1, "_element_id")
				var element_id: String = vm.lua_tostring(-1)
				vm.lua_pop(1)
				
				var element = lua_api.dom_parser.find_by_id(element_id) if element_id != "body" else lua_api.dom_parser.find_first("body")
				if element:
					vm.lua_pushstring(element.text_content)
					return 1
			
			# Fallback to empty string
			vm.lua_pushstring("")
			return 1
		"children":
			if lua_api:
				# Get element ID and find the element
				vm.lua_getfield(1, "_element_id")
				var element_id: String = vm.lua_tostring(-1)
				vm.lua_pop(1)
				
				var element = lua_api.dom_parser.find_by_id(element_id) if element_id != "body" else lua_api.dom_parser.find_first("body")
				if element:
					# Create array of child elements
					vm.lua_newtable()
					var index = 1
					for child in element.children:
						create_element_wrapper(vm, child, lua_api)
						vm.lua_rawseti(-2, index)
						index += 1
					return 1
			
			# Fallback to empty array
			vm.lua_newtable()
			return 1
		"visible":
			if lua_api:
				# Get element ID and find the element
				vm.lua_getfield(1, "_element_id")
				var element_id: String = vm.lua_tostring(-1)
				vm.lua_pop(1)
				
				var element = lua_api.dom_parser.find_by_id(element_id) if element_id != "body" else lua_api.dom_parser.find_first("body")
				if element:
					# Check if element has display: none (hidden class)
					var class_attr = element.get_attribute("class")
					var is_hidden = "hidden" in class_attr or element.get_attribute("style").contains("display:none") or element.get_attribute("style").contains("display: none")
					vm.lua_pushboolean(not is_hidden)
					return 1
			
			# Fallback to true (visible by default)
			vm.lua_pushboolean(true)
			return 1
		"size":
			if lua_api:
				vm.lua_getfield(1, "_element_id")
				var element_id: String = vm.lua_tostring(-1)
				vm.lua_pop(1)
				
				var dom_node = lua_api.dom_parser.parse_result.dom_nodes.get(element_id, null)
				if dom_node and dom_node is Control:
					var result = [0.0, 0.0, false]
					lua_api.call_deferred("_get_element_size_sync", result, element_id)
					while not result[2]: # wait for completion flag
						OS.delay_msec(1)
					
					vm.lua_newtable()
					vm.lua_pushnumber(result[0])
					vm.lua_setfield(-2, "width")
					vm.lua_pushnumber(result[1])
					vm.lua_setfield(-2, "height")
					return 1
			
			# Fallback to zero size
			vm.lua_newtable()
			vm.lua_pushnumber(0)
			vm.lua_setfield(-2, "width")
			vm.lua_pushnumber(0)
			vm.lua_setfield(-2, "height")
			return 1
		"position":
			if lua_api:
				vm.lua_getfield(1, "_element_id")
				var element_id: String = vm.lua_tostring(-1)
				vm.lua_pop(1)
				
				var dom_node = lua_api.dom_parser.parse_result.dom_nodes.get(element_id, null)
				if dom_node and dom_node is Control:
					var result = [0.0, 0.0, false]
					lua_api.call_deferred("_get_element_position_sync", result, element_id)
					while not result[2]: # wait for completion flag
						OS.delay_msec(1)
					
					vm.lua_newtable()
					vm.lua_pushnumber(result[0])
					vm.lua_setfield(-2, "x")
					vm.lua_pushnumber(result[1])
					vm.lua_setfield(-2, "y")
					return 1
			
			# Fallback to zero position
			vm.lua_newtable()
			vm.lua_pushnumber(0)
			vm.lua_setfield(-2, "x")
			vm.lua_pushnumber(0)
			vm.lua_setfield(-2, "y")
			return 1
		_:
			# Check for DOM traversal properties first
			if lua_api:
				match key:
					"parent":
						return get_element_parent_handler(vm, lua_api.dom_parser, lua_api)
					"nextSibling":
						return get_element_next_sibling_handler(vm, lua_api.dom_parser, lua_api)
					"previousSibling":
						return get_element_previous_sibling_handler(vm, lua_api.dom_parser, lua_api)
					"firstChild":
						return get_element_first_child_handler(vm, lua_api.dom_parser, lua_api)
					"lastChild":
						return get_element_last_child_handler(vm, lua_api.dom_parser, lua_api)
			
			# Check if it's a method in the original table
			vm.lua_pushvalue(1)
			vm.lua_pushstring(key)
			vm.lua_rawget(-2)
			vm.lua_remove(-2)
			return 1

static func add_classlist_support(vm: LuauVM) -> void:
	vm.lua_newtable()
	
	vm.lua_getfield(-2, "_element_id")
	vm.lua_setfield(-2, "_element_id")
	
	# Add classList methods
	vm.lua_pushcallable(LuaDOMUtils._classlist_add_wrapper, "classList.add")
	vm.lua_setfield(-2, "add")
	
	vm.lua_pushcallable(LuaDOMUtils._classlist_remove_wrapper, "classList.remove")
	vm.lua_setfield(-2, "remove")
	
	vm.lua_pushcallable(LuaDOMUtils._classlist_toggle_wrapper, "classList.toggle")
	vm.lua_setfield(-2, "toggle")
	
	vm.lua_pushcallable(LuaDOMUtils._classlist_contains_wrapper, "classList.contains")
	vm.lua_setfield(-2, "contains")
	
	vm.lua_pushcallable(LuaDOMUtils._classlist_item_wrapper, "classList.item")
	vm.lua_setfield(-2, "item")
	
	vm.lua_newtable()
	vm.lua_pushcallable(LuaDOMUtils._classlist_index_wrapper, "classList.__index")
	vm.lua_setfield(-2, "__index")
	vm.lua_setmetatable(-2)
	
	# Set classList on the element
	vm.lua_setfield(-2, "classList")

static func _classlist_add_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var cls: String = vm.luaL_checkstring(2)
	
	# Get element_id from classList table
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "add_class",
		"element_id": element_id,
		"class_name": cls
	}
	
	emit_dom_operation(lua_api, operation)
	return 0

static func _classlist_remove_wrapper(vm: LuauVM) -> int:
	# Get lua_api from VM metadata
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)  # classList table
	var cls: String = vm.luaL_checkstring(2)
	
	# Get element_id from classList table
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "remove_class",
		"element_id": element_id,
		"class_name": cls
	}
	
	emit_dom_operation(lua_api, operation)
	return 0

static func _classlist_toggle_wrapper(vm: LuauVM) -> int:
	# Get lua_api from VM metadata
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)  # classList table
	var cls: String = vm.luaL_checkstring(2)
	
	# Get element_id from classList table
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "toggle_class",
		"element_id": element_id,
		"class_name": cls
	}
	
	emit_dom_operation(lua_api, operation)
	return 0

static func _classlist_contains_wrapper(vm: LuauVM) -> int:

	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		vm.lua_pushboolean(false)
		return 1
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var cls: String = vm.luaL_checkstring(2)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var element = lua_api.dom_parser.find_by_id(element_id) if element_id != "body" else lua_api.dom_parser.find_first("body")
	if element:
		var current_style = element.get_attribute("style", "")
		var style_classes = CSSParser.smart_split_utility_classes(current_style) if current_style.length() > 0 else []
		
		var has_class = cls in style_classes
		
		vm.lua_pushboolean(has_class)
		return 1
	
	vm.lua_pushboolean(false)
	return 1

static func _classlist_item_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		vm.lua_pushnil()
		return 1
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var index: int = vm.luaL_checkint(2) - 1 # Convert from 1-based to 0-based indexing
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var element = lua_api.dom_parser.find_by_id(element_id) if element_id != "body" else lua_api.dom_parser.find_first("body")
	if element:
		var current_style = element.get_attribute("style", "")
		var style_classes = CSSParser.smart_split_utility_classes(current_style) if current_style.length() > 0 else []
		if index >= 0 and index < style_classes.size():
			vm.lua_pushstring(style_classes[index])
			return 1
	
	vm.lua_pushnil()
	return 1

static func _classlist_index_wrapper(vm: LuauVM) -> int:
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var key: String = vm.luaL_checkstring(2)
	
	if key == "length":
		var lua_api = vm.get_meta("lua_api") as LuaAPI
		if not lua_api:
			vm.lua_pushinteger(0)
			return 1
		
		vm.lua_getfield(1, "_element_id")
		var element_id: String = vm.lua_tostring(-1)
		vm.lua_pop(1)
		
		var element = lua_api.dom_parser.find_by_id(element_id) if element_id != "body" else lua_api.dom_parser.find_first("body")
		if element:
			var current_style = element.get_attribute("style", "")
			var style_classes = CSSParser.smart_split_utility_classes(current_style) if current_style.length() > 0 else []
			vm.lua_pushinteger(style_classes.size())
			return 1
		
		vm.lua_pushinteger(0)
		return 1
	
	vm.lua_pushvalue(1)
	vm.lua_pushstring(key)
	vm.lua_rawget(-2)
	vm.lua_remove(-2)
	return 1

static func _element_newindex_wrapper(vm: LuauVM) -> int:
	# Get lua_api from VM metadata
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var key: String = vm.luaL_checkstring(2)
	var value = vm.lua_tovariant(3)
	
	vm.lua_getfield(1, "_tag_name")
	var tag_name: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	if tag_name == "audio":
		vm.lua_getfield(1, "_element_id")
		var element_id: String = vm.lua_tostring(-1)
		vm.lua_pop(1)
		return LuaAudioUtils.handle_dom_audio_newindex(vm, element_id, key, value)
	
	match key:
		"value":
			if tag_name == "input" or tag_name == "select":
				vm.lua_getfield(1, "_element_id")
				var element_id: String = vm.lua_tostring(-1)
				vm.lua_pop(1)
				
				var element = lua_api.dom_parser.find_by_id(element_id) if element_id != "body" else lua_api.dom_parser.find_first("body")
				var dom_node = lua_api.dom_parser.parse_result.dom_nodes.get(element_id, null)
				
				if element and dom_node:
					if tag_name == "input":
						element.set_attribute("value", str(value))
						_set_input_value(element, dom_node, value)
					elif tag_name == "select":
						element.set_attribute("value", str(value))
						_set_select_value(element, dom_node, value)
			return 0
		"text":
			var text: String = str(value)  # Convert value to string
			
			vm.lua_getfield(1, "_element_id")
			var element_id: String = vm.lua_tostring(-1)
			vm.lua_pop(1)
			
			var element = lua_api.dom_parser.find_by_id(element_id) if element_id != "body" else lua_api.dom_parser.find_first("body")
			if element:
				element.text_content = text
			
			# Also queue the DOM operation for visual updates if the element is already rendered
			var operation = {
				"type": "set_text",
				"selector": "#" + element_id,
				"text": text
			}
			
			emit_dom_operation(lua_api, operation)
			return 0
		"visible":
			var is_visible: bool = vm.lua_toboolean(3)
			
			vm.lua_getfield(1, "_element_id")
			var element_id: String = vm.lua_tostring(-1)
			vm.lua_pop(1)
			
			var element = lua_api.dom_parser.find_by_id(element_id) if element_id != "body" else lua_api.dom_parser.find_first("body")
			if element:
				var class_attr = element.get_attribute("class")
				var classes = class_attr.split(" ") if not class_attr.is_empty() else []
				
				if is_visible:
					# Remove hidden class if present
					var hidden_index = classes.find("hidden")
					if hidden_index >= 0:
						classes.remove_at(hidden_index)
						var new_class_attr = " ".join(classes).strip_edges()
						element.set_attribute("class", new_class_attr)
						
						# Update visual element
						var operation = {
							"type": "remove_class",
							"element_id": element_id,
							"class_name": "hidden"
						}
						emit_dom_operation(lua_api, operation)
				else:
					# Add hidden class if not present
					if not "hidden" in classes:
						classes.append("hidden")
						var new_class_attr = " ".join(classes).strip_edges()
						element.set_attribute("class", new_class_attr)
						
						# Update visual element
						var operation = {
							"type": "add_class",
							"element_id": element_id,
							"class_name": "hidden"
						}
						emit_dom_operation(lua_api, operation)
			return 0
		_:
			# Store in table normally
			vm.lua_pushvalue(2)
			vm.lua_pushvalue(3)
			vm.lua_rawset(1)
			return 0

static func _element_show_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var element = lua_api.dom_parser.find_by_id(element_id) if element_id != "body" else lua_api.dom_parser.find_first("body")
	if element:
		var class_attr = element.get_attribute("class")
		var classes = class_attr.split(" ") if not class_attr.is_empty() else []
		
		# Remove hidden class if present
		var hidden_index = classes.find("hidden")
		if hidden_index >= 0:
			classes.remove_at(hidden_index)
			var new_class_attr = " ".join(classes).strip_edges()
			element.set_attribute("class", new_class_attr)
			
			# Update visual element
			var operation = {
				"type": "remove_class",
				"element_id": element_id,
				"class_name": "hidden"
			}
			emit_dom_operation(lua_api, operation)
	
	return 0

static func _element_hide_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var element = lua_api.dom_parser.find_by_id(element_id) if element_id != "body" else lua_api.dom_parser.find_first("body")
	if element:
		var class_attr = element.get_attribute("class")
		var classes = class_attr.split(" ") if not class_attr.is_empty() else []
		
		# Add hidden class if not present
		if not "hidden" in classes:
			classes.append("hidden")
			var new_class_attr = " ".join(classes).strip_edges()
			element.set_attribute("class", new_class_attr)
			
			# Update visual element
			var operation = {
				"type": "add_class",
				"element_id": element_id,
				"class_name": "hidden"
			}
			emit_dom_operation(lua_api, operation)
	
	return 0

static func _element_focus_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		vm.lua_pushboolean(false)
		return 1
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "focus_element",
		"element_id": element_id
	}
	
	emit_dom_operation(lua_api, operation)
	vm.lua_pushboolean(true)
	return 1

static func _element_unfocus_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		vm.lua_pushboolean(false)
		return 1
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "unfocus_element",
		"element_id": element_id
	}
	
	emit_dom_operation(lua_api, operation)
	vm.lua_pushboolean(true)
	return 1

static func _element_create_tween_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		vm.lua_pushnil()
		return 1
	
	return LuaTweenUtils.create_element_tween(vm, lua_api)

static func _unsubscribe_wrapper(vm: LuauVM) -> int:
	# Get subscription ID from the subscription table
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	
	vm.lua_getfield(1, "_subscription_id")
	var subscription_id: int = vm.lua_tointeger(-1)
	vm.lua_pop(1)
	
	# Get lua_api from VM metadata
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		vm.lua_pushboolean(false)
		return 1
	
	# Handle unsubscribe on main thread
	if subscription_id > 0:
		lua_api.call_deferred("_unsubscribe_event_on_main_thread", subscription_id)
		vm.lua_pushboolean(true)
	else:
		vm.lua_pushboolean(false)
	
	return 1

static func _index_handler(vm: LuauVM, lua_api: LuaAPI) -> int:
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var key: String = vm.luaL_checkstring(2)
	
	match key:
		"parent":
			return get_element_parent_handler(vm, lua_api.dom_parser, lua_api)
		"nextSibling":
			return get_element_next_sibling_handler(vm, lua_api.dom_parser, lua_api)
		"previousSibling":
			return get_element_previous_sibling_handler(vm, lua_api.dom_parser, lua_api)
		"firstChild":
			return get_element_first_child_handler(vm, lua_api.dom_parser, lua_api)
		"lastChild":
			return get_element_last_child_handler(vm, lua_api.dom_parser, lua_api)
		_:
			return _element_index_wrapper(vm)
