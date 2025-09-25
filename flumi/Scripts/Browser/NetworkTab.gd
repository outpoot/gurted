class_name NetworkTab
extends VBoxContainer

const NetworkRequestItemScene = preload("res://Scenes/NetworkRequestItem.tscn")

@onready var filter_dropdown: OptionButton = %FilterDropdown

# Details panel components
@onready var close_button: Button = %CloseButton
@onready var details_tab_container: TabContainer = $MainContainer/RightPanel/PanelContainer/HBoxContainer/TabContainer
@onready var headers_tab: VBoxContainer = $MainContainer/RightPanel/PanelContainer/HBoxContainer/TabContainer/Headers
@onready var preview_tab: Control = $MainContainer/RightPanel/PanelContainer/HBoxContainer/TabContainer/Preview
@onready var response_tab: Control = $MainContainer/RightPanel/PanelContainer/HBoxContainer/TabContainer/Response
@onready var messages_tab: Control = $MainContainer/RightPanel/PanelContainer/HBoxContainer/TabContainer/Messages

# Header components
@onready var status_header: Label = %StatusHeader
@onready var type_header: Label = %TypeHeader
@onready var size_header: Label = %SizeHeader
@onready var time_header: Label = %TimeHeader

# Main components
@onready var main_container: HSplitContainer = $MainContainer
@onready var request_list: VBoxContainer = $MainContainer/LeftPanel/ScrollContainer/RequestList
@onready var scroll_container: ScrollContainer = $MainContainer/LeftPanel/ScrollContainer
@onready var details_panel: Control = $MainContainer/RightPanel
@onready var status_bar: HBoxContainer = $HBoxContainer/StatusBar
@onready var request_count_label: Label = $HBoxContainer/StatusBar/RequestCount
@onready var transfer_label: Label = $HBoxContainer/StatusBar/Transfer
@onready var loaded_label: Label = $HBoxContainer/StatusBar/Loaded

@onready var syntax_highlighter = preload("res://Resources/LuaSyntaxHighlighter.tres")

var network_requests: Array[NetworkRequest] = []
var current_filter: int = -1 # -1 means all, otherwise NetworkRequest.RequestType
var selected_request: NetworkRequest = null
var request_items: Dictionary = {}

signal request_selected(request: NetworkRequest)

func _ready():
	details_panel.visible = false
	
	if main_container and main_container.size.x > 0:
		main_container.split_offset = int(main_container.size.x)
	
	update_status_bar()
	
	NetworkManager.register_dev_tools_network_tab(self)
	for req in NetworkManager.get_all_requests():
		add_network_request(req)

func add_network_request(request: NetworkRequest):
	network_requests.append(request)
	
	var request_item = NetworkRequestItemScene.instantiate() as NetworkRequestItem
	request_list.add_child(request_item)
	request_item.init(request, self)
	request_item.item_clicked.connect(_on_request_item_clicked)

	request_items[request.id] = request_item
	
	apply_filter()
	update_status_bar()

func apply_filter():
	for request in network_requests:
		var item = request_items.get(request.id)
		if item:
			var should_show = (current_filter == -1) or (int(request.type) == current_filter)
			item.visible = should_show

func update_request_item(request: NetworkRequest):
	var request_item = request_items.get(request.id) as NetworkRequestItem
	if not request_item:
		return
	
	request_item.update_display()
	
	if selected_request == request and details_panel.visible:
		update_details_panel(request)
	
	apply_filter()
	update_status_bar()

func update_details_panel(request: NetworkRequest):
	clear_details_panel()
	update_headers_tab(request)
	update_preview_tab(request)
	update_response_tab(request)
	update_messages_tab(request)

	if request.type == NetworkRequest.RequestType.SOCKET:
		messages_tab.visible = true
		details_tab_container.set_tab_title(3, "Messages (" + str(request.websocket_messages.size()) + ")")
	else:
		messages_tab.visible = false

func clear_details_panel():
	for child in headers_tab.get_children(): child.queue_free()
	for child in preview_tab.get_children(): child.queue_free()
	for child in response_tab.get_children(): child.queue_free()
	for child in messages_tab.get_children(): child.queue_free()

func create_collapsible_section(title: String, expanded: bool = false) -> VBoxContainer:
	var section = VBoxContainer.new()
	
	# Header w/ toggle button
	var header = HBoxContainer.new()
	header.custom_minimum_size.y = 28
	
	var toggle_button = Button.new()
	toggle_button.text = "▼" if expanded else "▶"
	toggle_button.custom_minimum_size = Vector2(20, 20)
	toggle_button.flat = true
	toggle_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	header.add_child(toggle_button)
	
	var title_label = Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 14)
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title_label)
	
	section.add_child(header)
	
	# Content container
	var content = VBoxContainer.new()
	content.visible = expanded
	section.add_child(content)
	
	toggle_button.pressed.connect(func():
		content.visible = !content.visible
		toggle_button.text = "▼" if content.visible else "▶"
	)
	
	return section

func add_header_row(parent: VBoxContainer, header_name: String, value: String):
	var row = HBoxContainer.new()
	
	var name_label = Label.new()
	name_label.text = header_name
	name_label.custom_minimum_size.x = 200
	name_label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(name_label)
	
	var value_label = Label.new()
	value_label.text = value
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	row.add_child(value_label)
	
	parent.add_child(row)

func update_headers_tab(request: NetworkRequest):
	var general_section = create_collapsible_section("General", true)
	headers_tab.add_child(general_section)
	
	var general_content = general_section.get_child(1)
	add_header_row(general_content, "Request URL:", request.url)
	add_header_row(general_content, "Request Method:", request.method)
	add_header_row(general_content, "Status Code:", str(request.status_code) + " " + request.status_text)
	
	# WebSocket information
	if request.type == NetworkRequest.RequestType.SOCKET:
		var ws_section = create_collapsible_section("WebSocket Information", true)
		headers_tab.add_child(ws_section)
		
		var ws_content = ws_section.get_child(1)
		add_header_row(ws_content, "WebSocket ID:", request.websocket_id)
		add_header_row(ws_content, "Event Type:", request.websocket_event_type)
		add_header_row(ws_content, "Connection Status:", request.connection_status)
		add_header_row(ws_content, "Total Messages:", str(request.websocket_messages.size()))
	
	# Request Headers section
	if not request.request_headers.is_empty():
		var request_headers_section = create_collapsible_section("Request Headers", false)
		headers_tab.add_child(request_headers_section)
		
		var request_headers_content = request_headers_section.get_child(1)
		for header_name in request.request_headers:
			add_header_row(request_headers_content, header_name + ":", str(request.request_headers[header_name]))
	
	# Response Headers section
	if not request.response_headers.is_empty():
		var response_headers_section = create_collapsible_section("Response Headers", false)
		headers_tab.add_child(response_headers_section)
		
		var response_headers_content = response_headers_section.get_child(1)
		for header_name in request.response_headers:
			add_header_row(response_headers_content, header_name + ":", str(request.response_headers[header_name]))

func update_preview_tab(request: NetworkRequest):
	if request.type == NetworkRequest.RequestType.SOCKET:
		var content_to_show = ""
		
		match request.websocket_event_type:
			"connection":
				content_to_show = "WebSocket connection event\n"
				content_to_show += "URL: " + request.url + "\n"
				content_to_show += "Status: " + request.connection_status + "\n"
				if request.status_code > 0:
					content_to_show += "Status Code: " + str(request.status_code) + " " + request.status_text + "\n"
				content_to_show += "Messages exchanged: " + str(request.websocket_messages.size())
			"close", "error":
				content_to_show = "WebSocket " + request.websocket_event_type + " event\n"
				content_to_show += "Status Code: " + str(request.status_code) + "\n"
				content_to_show += "Reason: " + request.status_text
		
		if not content_to_show.is_empty():
			var code_edit = CodeEditUtils.create_code_edit({
				"text": content_to_show,
				"editable": false,
				"show_line_numbers": false,
				"syntax_highlighter": null
			})
			preview_tab.add_child(code_edit)
		return
	
	# For images, show the image in the preview tab
	if request.type == NetworkRequest.RequestType.IMG and request.status == NetworkRequest.RequestStatus.SUCCESS:
		var image = Image.new()
		var response_bytes = request.response_body_bytes
		var load_error = ERR_UNAVAILABLE
		
		load_error = image.load_png_from_buffer(response_bytes)
		if load_error != OK:
			load_error = image.load_jpg_from_buffer(response_bytes)
		if load_error != OK:
			load_error = image.load_webp_from_buffer(response_bytes)
		if load_error != OK:
			load_error = image.load_bmp_from_buffer(response_bytes)
		if load_error != OK:
			load_error = image.load_tga_from_buffer(response_bytes)
		
		if load_error == OK:
			var texture = ImageTexture.create_from_image(image)
			
			var container = VBoxContainer.new()
			container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			container.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			
			var texture_rect = TextureRect.new()
			texture_rect.texture = texture
			texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			texture_rect.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			texture_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			
			var img_size = image.get_size()
			var max_size = 200.0
			var scale_factor = min(max_size / img_size.x, max_size / img_size.y, 1.0)
			texture_rect.custom_minimum_size = Vector2(img_size.x * scale_factor, img_size.y * scale_factor)
			
			container.add_child(texture_rect)
			preview_tab.add_child(container)
			return
		else:
			var label = Label.new()
			label.text = "Failed to load image data (Error: " + str(load_error) + ")"
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			preview_tab.add_child(label)
			return
	
	# For non-images, show request body
	if request.request_body.is_empty():
		var label = Label.new()
		label.text = "No request body"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		preview_tab.add_child(label)
		return
	
	# CodeEdit for request body
	# TODO: Syntax highlight based on Content-Type, we need a JSON, HTML and CSS highlighter too
	var code_edit = CodeEditUtils.create_code_edit({
		"text": request.request_body,
		"editable": false,
		"show_line_numbers": true,
		"syntax_highlighter": syntax_highlighter.duplicate()
	})
	
	preview_tab.add_child(code_edit)

func update_response_tab(request: NetworkRequest):
	if request.type == NetworkRequest.RequestType.SOCKET:
		var content_to_show = ""
		
		match request.websocket_event_type:
			"connection":
				content_to_show = "WebSocket Connection Details\n\n"
				content_to_show += "This is a WebSocket connection request.\n"
				content_to_show += "Connection Status: " + request.connection_status + "\n"
				content_to_show += "WebSocket ID: " + request.websocket_id + "\n"
				content_to_show += "Total Messages: " + str(request.websocket_messages.size()) + "\n"
				if request.status_code > 0:
					content_to_show += "Status Code: " + str(request.status_code) + " " + request.status_text + "\n"
				content_to_show += "\nNote: Individual messages can be viewed in the 'Messages' tab."
			"close", "error":
				content_to_show = "WebSocket " + request.websocket_event_type.capitalize() + " Event\n\n"
				content_to_show += "Status Code: " + str(request.status_code) + "\n"
				content_to_show += "Reason: " + request.status_text + "\n"
				content_to_show += "WebSocket ID: " + request.websocket_id + "\n"
				content_to_show += "Total Messages Exchanged: " + str(request.websocket_messages.size())
		
		if not content_to_show.is_empty():
			var code_edit = CodeEditUtils.create_code_edit({
				"text": content_to_show,
				"editable": false,
				"show_line_numbers": false,
				"syntax_highlighter": null
			})
			response_tab.add_child(code_edit)
		else:
			var label = Label.new()
			label.text = "No WebSocket data to display"
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			response_tab.add_child(label)
		return
	
	if request.type == NetworkRequest.RequestType.IMG:
		var label = Label.new()
		label.text = "This response contains image data. See the \"Preview\" tab to view the image."
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		response_tab.add_child(label)
		return
	
	if request.response_body.is_empty():
		var label = Label.new()
		label.text = "No response body"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		response_tab.add_child(label)
		return
	
	# Check if we can display the content
	var can_display = true
	if request.mime_type.begins_with("video/") or request.mime_type.begins_with("audio/"):
		can_display = false
	
	if not can_display:
		var label = Label.new()
		label.text = "Cannot preview this content type: " + request.mime_type
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		response_tab.add_child(label)
		return
	
	# Create CodeEdit for response body
	var code_edit = CodeEditUtils.create_code_edit({
		"text": request.response_body,
		"editable": false,
		"show_line_numbers": true,
		"syntax_highlighter": syntax_highlighter.duplicate()
	})
	
	response_tab.add_child(code_edit)

func update_messages_tab(request: NetworkRequest):
	if request.type != NetworkRequest.RequestType.SOCKET:
		return
	
	if request.websocket_messages.is_empty():
		var label = Label.new()
		label.text = "No WebSocket messages yet"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		messages_tab.add_child(label)
		return
	
	var scroll_container = ScrollContainer.new()
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	var messages_container = VBoxContainer.new()
	messages_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(messages_container)
	
	var header_container = VBoxContainer.new()
	header_container.add_theme_constant_override("separation", 8)
	
	var search_container = HBoxContainer.new()
	search_container.add_theme_constant_override("separation", 8)

	var search_input = LineEdit.new()
	search_input.placeholder_text = "Filter"
	search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var focus_style = StyleBoxFlat.new()
	focus_style.content_margin_left = 16.0
	focus_style.content_margin_right = 8.0
	focus_style.bg_color = Color(0.168627, 0.168627, 0.168627, 1)
	focus_style.border_width_left = 1
	focus_style.border_width_top = 1
	focus_style.border_width_right = 1
	focus_style.border_width_bottom = 1
	focus_style.border_color = Color(0.247059, 0.466667, 0.807843, 1)
	focus_style.corner_radius_top_left = 15
	focus_style.corner_radius_top_right = 15
	focus_style.corner_radius_bottom_right = 15
	focus_style.corner_radius_bottom_left = 15
	search_input.add_theme_stylebox_override("focus", focus_style)

	var normal_style = StyleBoxFlat.new()
	normal_style.content_margin_left = 16.0
	normal_style.content_margin_right = 8.0
	normal_style.bg_color = Color(0.168627, 0.168627, 0.168627, 1)
	normal_style.corner_radius_top_left = 15
	normal_style.corner_radius_top_right = 15
	normal_style.corner_radius_bottom_right = 15
	normal_style.corner_radius_bottom_left = 15
	search_input.add_theme_stylebox_override("normal", normal_style)

	search_container.add_child(search_input)
	
	header_container.add_child(search_container)

	var spacer = Control.new()
	spacer.custom_minimum_size.y = 8
	header_container.add_child(spacer)

	messages_container.add_child(header_container)
	
	var message_rows: Array[Control] = []
	var search_term = ""
	
	var update_search = func():
		var filter_text = search_input.text.to_lower()

		for row_index in range(message_rows.size()):
			var row = message_rows[row_index]
			var message = request.websocket_messages[row_index]
			var should_show = filter_text.is_empty() or message.content.to_lower().contains(filter_text)
			row.visible = should_show
	
	search_input.text_changed.connect(func(_text): update_search.call())
	
	for i in range(request.websocket_messages.size()):
		var message = request.websocket_messages[i]
		
		var message_panel = PanelContainer.new()
		message_panel.custom_minimum_size.y = 32

		var button = Button.new()
		button.flat = true
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.focus_mode = Control.FOCUS_NONE

		button.anchors_preset = Control.PRESET_FULL_RECT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		
		var panel_style = StyleBoxFlat.new()
		if message.direction == "sent":
			panel_style.bg_color = Color(0.2, 0.3, 0.5, 0.3)
		else:
			panel_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
		
		panel_style.content_margin_left = 6
		panel_style.content_margin_right = 6
		panel_style.content_margin_top = 2
		panel_style.content_margin_bottom = 2
		message_panel.add_theme_stylebox_override("panel", panel_style)
		
		var message_row = HBoxContainer.new()
		message_row.add_theme_constant_override("separation", 8)
		
		var direction_label = Label.new()
		var direction_icon = "↑" if message.direction == "sent" else "↓"
		var direction_color = Color(0.7, 0.9, 1.0) if message.direction == "sent" else Color(1.0, 0.7, 0.7)
		
		direction_label.text = direction_icon
		direction_label.add_theme_font_size_override("font_size", 16)
		direction_label.add_theme_color_override("font_color", direction_color)
		direction_label.custom_minimum_size.x = 16
		direction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		message_row.add_child(direction_label)
		
		var timestamp_label = Label.new()
		timestamp_label.text = message.get_formatted_time()
		timestamp_label.add_theme_font_size_override("font_size", 14)
		timestamp_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
		timestamp_label.custom_minimum_size.x = 80
		message_row.add_child(timestamp_label)
		
		var content_label = Label.new()
		var content_text = message.content
		if content_text.length() > 60:
			content_text = content_text.substr(0, 57) + "..."
		content_text = content_text.replace("\n", " ").replace("\r", " ")
		
		content_label.text = content_text
		content_label.add_theme_font_size_override("font_size", 16)
		content_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
		content_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content_label.clip_contents = true
		content_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		message_row.add_child(content_label)
		
		var size_label = Label.new()
		size_label.text = str(message.size) + "b"
		size_label.add_theme_font_size_override("font_size", 14)
		size_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
		size_label.custom_minimum_size.x = 40
		size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		message_row.add_child(size_label)
		
		button.pressed.connect(func(): DisplayServer.clipboard_set(message.content))

		message_panel.add_child(message_row)
		message_panel.add_child(button)

		messages_container.add_child(message_panel)
		message_rows.append(message_panel)
	
	messages_tab.add_child(scroll_container)

func update_status_bar():
	var total_requests = network_requests.size()
	var total_size = 0
	var loaded_resources = 0
	
	for request in network_requests:
		total_size += request.size
		if request.status == NetworkRequest.RequestStatus.SUCCESS:
			loaded_resources += 1
	
	request_count_label.text = str(total_requests) + " requests"
	transfer_label.text = NetworkRequest.format_bytes(total_size) + " transferred"
	loaded_label.text = str(loaded_resources) + " resources loaded"

func hide_details_panel():
	# Hide details panel and show columns again
	details_panel.visible = false
	hide_columns(false)
	selected_request = null
	if main_container.size.x > 0:
		main_container.split_offset = int(main_container.size.x)
	
	# Clear selection visual
	for req_id in request_items:
		var request_item = request_items[req_id] as NetworkRequestItem
		request_item.set_selected(false)

func hide_columns(should_hide: bool):
	# Hide/show header labels
	status_header.visible = !should_hide
	type_header.visible = !should_hide
	size_header.visible = !should_hide
	time_header.visible = !should_hide
	
	# Hide/show status, type, size, time columns for all request items
	for request_item in request_items.values():
		var network_request_item = request_item as NetworkRequestItem
		network_request_item.hide_columns(should_hide)

func clear_all_requests():
	for item in request_items.values():
		item.queue_free()
	
	network_requests.clear()
	request_items.clear()
	selected_request = null
	
	# Hide details panel and show columns again
	details_panel.visible = false
	hide_columns(false)
	if main_container.size.x > 0:
		main_container.split_offset = int(main_container.size.x)
	
	update_status_bar()

func clear_all_requests_except(preserve_request_id: String):
	# Remove all items except the preserved one
	var preserved_request = null
	var preserved_item = null
	
	for request in network_requests:
		if request.id == preserve_request_id:
			preserved_request = request
			preserved_item = request_items.get(preserve_request_id)
			break
	
	# Clear all items except preserved one
	for item_id in request_items:
		if item_id != preserve_request_id:
			var item = request_items[item_id]
			item.queue_free()
	
	network_requests.clear()
	request_items.clear()
	
	# Re-add preserved request and item
	if preserved_request and preserved_item:
		network_requests.append(preserved_request)
		request_items[preserve_request_id] = preserved_item
	
	selected_request = null
	
	# Hide details panel and show columns again
	details_panel.visible = false
	hide_columns(false)
	if main_container.size.x > 0:
		main_container.split_offset = int(main_container.size.x)
	
	update_status_bar()

func _on_request_item_clicked(request: NetworkRequest):
	if selected_request == request:
		hide_details_panel()
		return
	
	selected_request = request
	request_selected.emit(request)
	
	for req_id in request_items:
		var request_item = request_items[req_id] as NetworkRequestItem
		request_item.set_selected(req_id == request.id)
	
	details_panel.visible = true
	if main_container.size.x > 0:
		# Give 6/8 (3/4) of space to details panel, 2/8 (1/4) to left panel
		main_container.split_offset = int(main_container.size.x * 0.25)

	hide_columns(true)
	update_details_panel(request)

func _on_filter_selected(index: int):
	var filter_type = index - 1 # 0 -> -1 (All), 1 -> 0 (Fetch)...
	
	if current_filter == filter_type:
		return
	
	current_filter = filter_type
	apply_filter()
