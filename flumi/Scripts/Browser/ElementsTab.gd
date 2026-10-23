class_name ElementsTab
extends VBoxContainer

@onready var filter_input: LineEdit = $FilterContainer/FilterInput
@onready var clear_filter_button: Button = $FilterContainer/ClearFilterButton
@onready var elements_tree: Tree = $ScrollContainer/ElementsTree
@onready var scroll_container: ScrollContainer = $ScrollContainer

var current_tab: Tab = null
var current_parser: HTMLParser = null
var selected_element: HTMLParser.HTMLElement = null
var selected_dom_node: Node = null
var element_items: Dictionary = {}
var highlight_style: StyleBoxFlat = null
var filter_text: String = ""
var update_timer: Timer = null
var is_loading: bool = false

func _ready():
	setup_highlight_style()
	setup_update_timer()
	elements_tree.item_selected.connect(_on_element_selected)
	elements_tree.item_activated.connect(_on_element_activated)
	elements_tree.gui_input.connect(_on_tree_gui_input)
	filter_input.text_changed.connect(_on_filter_changed)
	clear_filter_button.pressed.connect(_on_clear_filter_pressed)
	visibility_changed.connect(_on_visibility_changed)

func _on_visibility_changed():
	if visible:
		# If we have a current tab, update the tree
		if current_tab and current_tab.lua_apis.size() > 0:
			current_parser = current_tab.lua_apis[0].dom_parser
			call_deferred("update_elements_tree")

func setup_update_timer():
	update_timer = Timer.new()
	update_timer.wait_time = 0.5
	update_timer.timeout.connect(_on_update_timer_timeout)
	update_timer.one_shot = false
	add_child(update_timer)
	update_timer.start()

func _on_update_timer_timeout():
	if not visible:
		return

	if current_tab and current_tab.lua_apis.size() > 0:
		var parser = current_tab.lua_apis[0].dom_parser
		if parser != current_parser:
			current_parser = parser
			call_deferred("update_elements_tree")
		elif current_parser and current_parser.parse_result and not current_parser.parse_result.all_elements.is_empty():
			var body_element = current_parser.find_first("body")
			if body_element:
				var current_element_count = count_elements_recursive(body_element)
				if current_element_count != element_items.size():
					call_deferred("update_elements_tree")

func count_elements_recursive(element: HTMLParser.HTMLElement) -> int:
	var count = 1
	for child in element.children:
		count += count_elements_recursive(child)
	return count

func setup_highlight_style():
	highlight_style = StyleBoxFlat.new()
	highlight_style.bg_color = Color(0, 0, 1, 0.3)
	highlight_style.border_width_left = 2
	highlight_style.border_width_right = 2
	highlight_style.border_width_top = 2
	highlight_style.border_width_bottom = 2
	highlight_style.border_color = Color(0, 0, 1, 1)

func set_current_tab(tab: Tab):
	if current_tab:
		disconnect_tab_signals()

	current_tab = tab
	if tab and tab.lua_apis.size() > 0:
		current_parser = tab.lua_apis[0].dom_parser
		connect_tab_signals()
		show_loading_state("Loading page structure...")
		call_deferred("update_elements_tree")
	else:
		current_parser = null
		show_loading_state("No page content available")

func connect_tab_signals():
	if current_tab:
		if current_tab.has_signal("content_updated"):
			current_tab.content_updated.connect(_on_content_updated)
		if current_tab.has_signal("tab_pressed"):
			current_tab.tab_pressed.connect(_on_tab_pressed)
		if current_tab.has_signal("url_changed"):
			current_tab.url_changed.connect(_on_url_changed)

func disconnect_tab_signals():
	if current_tab:
		if current_tab.has_signal("content_updated"):
			current_tab.content_updated.disconnect(_on_content_updated)
		if current_tab.has_signal("tab_pressed"):
			current_tab.tab_pressed.disconnect(_on_tab_pressed)
		if current_tab.has_signal("url_changed"):
			current_tab.url_changed.disconnect(_on_url_changed)

func _on_content_updated():
	update_elements_tree()

func _on_url_changed():
	clear_elements_tree()
	if current_tab and current_tab.lua_apis.size() > 0:
		current_parser = current_tab.lua_apis[0].dom_parser
	update_elements_tree()

func _on_tab_pressed():
	if current_tab and current_tab.lua_apis.size() > 0:
		current_parser = current_tab.lua_apis[0].dom_parser
		update_elements_tree()

func _on_filter_changed(new_text: String):
	filter_text = new_text
	apply_filter()

func _on_clear_filter_pressed():
	filter_input.text = ""
	filter_text = ""
	show_all_items()

func apply_filter():
	if filter_text.is_empty():
		show_all_items()
		return
	
	var root = elements_tree.get_root()
	if not root:
		return
	
	hide_items_recursive(root)

func hide_items_recursive(item: TreeItem):
	if not item:
		return
	
	var element = item.get_metadata(0)
	var should_show = false
	
	if element:
		var display_text = element.tag_name
		if element.get_id():
			display_text += "#" + element.get_id()
		
		var class_names = HTMLParser.extract_class_names(element)
		if class_names.size() > 0:
			display_text += "." + ".".join(class_names)
		
		should_show = display_text.to_lower().contains(filter_text.to_lower())
	
	item.visible = should_show
	
	for child in item.get_children():
		hide_items_recursive(child)

func show_all_items():
	var root = elements_tree.get_root()
	if not root:
		return
	
	show_items_recursive(root)

func show_items_recursive(item: TreeItem):
	if not item:
		return
	
	item.visible = true
	
	for child in item.get_children():
		show_items_recursive(child)

func scroll_to_element(element: HTMLParser.HTMLElement):
	if not element or not current_parser or not current_parser.parse_result:
		return
	
	var dom_node = null
	var element_id = element.get_id()
	
	if element_id and element_id != "":
		dom_node = current_parser.parse_result.dom_nodes.get(element_id, null)
	
	if not dom_node and element == current_parser.find_first("body"):
		dom_node = current_tab.website_container
	
	if not dom_node:
		var temp_key = "_element_" + str(element.get_instance_id())
		dom_node = current_parser.parse_result.dom_nodes.get(temp_key, null)
	
	if dom_node and dom_node.get_parent():
		var scroll_container = dom_node.get_parent()
		if scroll_container is ScrollContainer:
			scroll_container.scroll_to_item(dom_node)

func update_elements_tree():
	if not current_tab:
		return

	if not current_parser:
		show_loading_state("Waiting for page content...")
		return

	if not current_parser.parse_result:
		show_loading_state("Parsing page content...")
		call_deferred("update_elements_tree")
		return

	if current_parser.parse_result.all_elements.is_empty():
		show_loading_state("Loading page structure...")
		call_deferred("update_elements_tree")
		return

	is_loading = true
	clear_elements_tree()

	var body_element = current_parser.find_first("body")
	if body_element:
		build_tree_recursive(body_element, null, 0)
		apply_filter()
		show_loading_state("")
	else:
		var root = elements_tree.create_item()
		root.set_text(0, "No content to display")
		root.set_icon(0, null)
		show_loading_state("")

	is_loading = false

func show_loading_state(message: String):
	if message.is_empty():
		if elements_tree.get_root():
			var root = elements_tree.get_root()
			if root.get_text(0).begins_with("Loading") or root.get_text(0).begins_with("Waiting") or root.get_text(0).begins_with("Parsing"):
				elements_tree.clear()
	else:
		elements_tree.clear()
		var root = elements_tree.create_item()
		root.set_text(0, message)
		root.set_icon(0, null)

func clear_elements_tree():
	elements_tree.clear()
	element_items.clear()
	clear_highlight()

func build_tree_recursive(element: HTMLParser.HTMLElement, parent_item: TreeItem, depth: int = 0):
	if not element:
		return

	var open_item = elements_tree.create_item()
	var indent = "  ".repeat(depth)
	var open_text = indent + "<" + element.tag_name
	for attr_name in element.attributes.keys():
		var attr_value = element.attributes[attr_name]
		if attr_value != "":
			open_text += " " + attr_name + "=\"" + attr_value + "\""
		else:
			open_text += " " + attr_name

	open_text += ">"
	open_item.set_text(0, open_text)
	open_item.set_metadata(0, element)

	element_items[element] = open_item

	var text_content = element.text_content.strip_edges()
	if text_content.length() > 0:
		var text_item = elements_tree.create_item()
		var text_indent = "  ".repeat(depth + 1)
		text_item.set_text(0, text_indent + text_content)
		text_item.set_metadata(0, element)

	for child in element.children:
		if child.tag_name == "#text" or child.tag_name == "":
			var child_text_content = child.text_content.strip_edges()
			if child_text_content.length() > 0:
				var text_item = elements_tree.create_item()
				var text_indent = "  ".repeat(depth + 1)
				text_item.set_text(0, text_indent + child_text_content)
				text_item.set_metadata(0, child)
		else:
			build_tree_recursive(child, open_item, depth + 1)

	var has_children = element.children.size() > 0
	var has_text = element.text_content.strip_edges().length() > 0

	if has_children or has_text:
		var close_item = elements_tree.create_item()
		var close_indent = "  ".repeat(depth)
		close_item.set_text(0, close_indent + "</" + element.tag_name + ">")
		close_item.set_metadata(0, element)

func _on_element_selected():
	var selected_item = elements_tree.get_selected()
	if not selected_item:
		return

	var metadata = selected_item.get_metadata(0)
	if not metadata:
		return

	var element = null
	if metadata is HTMLParser.HTMLElement:
		element = metadata
	else:
		var current_item = selected_item
		while current_item and not element:
			var current_metadata = current_item.get_metadata(0)
			if current_metadata is HTMLParser.HTMLElement:
				element = current_metadata
				break
			current_item = current_item.get_parent()

	if element:
		selected_element = element
		highlight_element(element)

func _on_element_activated():
	_on_element_selected()

func _on_tree_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var selected_item = elements_tree.get_selected()
		if not selected_item:
			return

		var metadata = selected_item.get_metadata(0)
		if not metadata:
			return

		var element = null
		if metadata is HTMLParser.HTMLElement:
			element = metadata
		else:
			var current_item = selected_item
			while current_item and not element:
				var current_metadata = current_item.get_metadata(0)
				if current_metadata is HTMLParser.HTMLElement:
					element = current_metadata
					break
				current_item = current_item.get_parent()

		if element:
			var context_menu = PopupMenu.new()
			context_menu.add_item("Copy Element", 0)
			context_menu.size = Vector2(140, 30)
			context_menu.position = get_global_mouse_position()
			add_child(context_menu)

			context_menu.id_pressed.connect(_on_context_menu_selected.bind(context_menu, element))
			context_menu.popup()

func _on_context_menu_selected(id: int, context_menu: PopupMenu, element: HTMLParser.HTMLElement):
	match id:
		0:
			copy_element_html(element, true)
	
	context_menu.queue_free()

func copy_element_html(element: HTMLParser.HTMLElement, include_children: bool):
	var html = ""
	
	if include_children:
		html = element_to_html_with_children(element)
	else:
		html = element_to_html(element)
	
	DisplayServer.clipboard_set(html)

func element_to_html(element: HTMLParser.HTMLElement) -> String:
	var html = "<" + element.tag_name
	
	for attr_name in element.attributes:
		var attr_value = element.attributes[attr_name]
		html += " " + attr_name + "=\"" + attr_value + "\""
	
	if element.is_self_closing:
		html += " />"
	else:
		html += ">"
		if element.text_content.strip_edges().length() > 0:
			html += element.text_content.strip_edges()
		html += "</" + element.tag_name + ">"
	
	return html

func element_to_html_with_children(element: HTMLParser.HTMLElement) -> String:
	var html = "<" + element.tag_name
	
	for attr_name in element.attributes:
		var attr_value = element.attributes[attr_name]
		html += " " + attr_name + "=\"" + attr_value + "\""
	
	if element.is_self_closing:
		html += " />"
	else:
		html += ">"
		if element.text_content.strip_edges().length() > 0:
			html += element.text_content.strip_edges()
		
		for child in element.children:
			html += element_to_html_with_children(child)
		
		html += "</" + element.tag_name + ">"
	
	return html

func highlight_element(element: HTMLParser.HTMLElement):
	clear_highlight()
	
	if not element or not current_parser or not current_parser.parse_result:
		return
	
	var dom_node = null
	var element_id = element.get_id()
	
	if element_id and element_id != "":
		dom_node = current_parser.parse_result.dom_nodes.get(element_id, null)
	
	if not dom_node and element == current_parser.find_first("body"):
		dom_node = current_tab.website_container
	
	if not dom_node:
		var temp_key = "_element_" + str(element.get_instance_id())
		dom_node = current_parser.parse_result.dom_nodes.get(temp_key, null)
	
	if dom_node:
		selected_dom_node = dom_node
		dom_node.add_theme_stylebox_override("panel", highlight_style)

func clear_highlight():
	if selected_dom_node:
		selected_dom_node.remove_theme_stylebox_override("panel")
		selected_dom_node = null
	
	selected_element = null

func _on_tab_changed():
	if current_tab:
		set_current_tab(current_tab)

func _exit_tree():
	clear_highlight()
	if current_tab:
		disconnect_tab_signals()
	if update_timer:
		update_timer.stop()
		update_timer.queue_free()
