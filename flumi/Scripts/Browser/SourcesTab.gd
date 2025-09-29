class_name SourcesTab
extends HSplitContainer

@onready var file_tree: Tree = $FileTree
@onready var preview_container: VBoxContainer = $PreviewContainer
@onready var preview_label: Label = $PreviewContainer/PreviewLabel
@onready var preview_image: TextureRect = $PreviewContainer/PreviewImage
@onready var preview_text: TextEdit = $PreviewContainer/PreviewText
@onready var preview_audio: AudioStreamPlayer = $PreviewContainer/PreviewAudio

var current_tab: Tab = null
var current_parser: HTMLParser = null
var selected_file: Dictionary = {}
var last_update_url: String = ""
var last_update_count: int = 0
var tab_network_requests: Dictionary = {}  # Store requests per tab

func _ready():
	file_tree.item_selected.connect(_on_file_selected)
	file_tree.item_activated.connect(_on_file_activated)
	file_tree.gui_input.connect(_on_tree_gui_input)
	visibility_changed.connect(_on_visibility_changed)
	
	preview_image.visible = false
	preview_text.visible = false
	preview_audio.stop()
	preview_label.visible = true
	preview_label.text = "Select a file to preview"

func set_current_tab(tab: Tab):
	if current_tab:
		disconnect_tab_signals()
	
	last_update_url = ""
	last_update_count = -1
	
	current_tab = tab
	if tab and tab.lua_apis.size() > 0:
		current_parser = tab.lua_apis[0].dom_parser
		connect_tab_signals()
		call_deferred("update_file_tree")
	else:
		current_parser = null
		clear_file_tree()

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
	if current_tab:
		var tab_id = str(current_tab.get_instance_id())
		var current_requests = NetworkManager.get_all_requests()
		tab_network_requests[tab_id] = current_requests.duplicate()
	update_file_tree()

func _on_tab_pressed():
	if current_tab and current_tab.lua_apis.size() > 0:
		current_parser = current_tab.lua_apis[0].dom_parser
		update_file_tree()

func _on_url_changed():
	last_update_url = ""
	last_update_count = -1
	update_file_tree()

func _on_visibility_changed():
	if visible and current_tab:
		if file_tree.get_root() == null:
			update_file_tree()

func get_resource_type_from_request(request: NetworkRequest) -> String:
	match request.type:
		NetworkRequest.RequestType.DOC:
			return "html"
		NetworkRequest.RequestType.CSS:
			return "css"
		NetworkRequest.RequestType.LUA:
			return "script"
		NetworkRequest.RequestType.IMG:
			return "image"
		NetworkRequest.RequestType.FONT:
			return "font"
		NetworkRequest.RequestType.FETCH:
			# Skip FETCH requests that are API calls (no file extension or not actual files)
			# These are now properly classified as FETCH only if they're not file-like
			return "skip"
		_:
			return "other"

func update_file_tree():
	if not current_tab:
		clear_file_tree()
		return
	
	var current_url = current_tab.current_url.get_file() if not current_tab.current_url.is_empty() else ""
	var tab_id = str(current_tab.get_instance_id())
	
	var network_requests: Array[NetworkRequest] = []
	if tab_network_requests.has(tab_id):
		network_requests = tab_network_requests[tab_id]
	else:
		network_requests = NetworkManager.get_all_requests()
	
	var current_count = network_requests.size()
	
	if file_tree.get_root() == null or last_update_count == -1:
		last_update_url = current_url
		last_update_count = current_count
		build_file_tree_with_requests(current_url, network_requests)
		return
	
	if last_update_url != current_url or last_update_count != current_count:
		last_update_url = current_url
		last_update_count = current_count
		build_file_tree_with_requests(current_url, network_requests)

func build_file_tree(title: String):
	var network_requests = NetworkManager.get_all_requests()
	build_file_tree_with_requests(title, network_requests)

func build_file_tree_with_requests(title: String, network_requests: Array[NetworkRequest]):
	clear_file_tree()
	
	var root = file_tree.create_item()
	var display_title = "Resources"
	if not title.is_empty():
		display_title = title
	root.set_text(0, display_title)
	root.set_icon(0, get_icon_for_type("html"))
	
	add_network_resources_to_tree_with_requests(root, network_requests)
	root.set_collapsed(false)

func add_network_resources_to_tree(root: TreeItem):
	var network_requests = NetworkManager.get_all_requests()
	add_network_resources_to_tree_with_requests(root, network_requests)

func add_network_resources_to_tree_with_requests(root: TreeItem, network_requests: Array[NetworkRequest]):
	var resources_by_type = {}
	
	for request in network_requests:
		var type = get_resource_type_from_request(request)
		if type == "skip":
			continue 

		if not resources_by_type.has(type):
			resources_by_type[type] = []

		var file_info = {
			"name": request.name,
			"url": request.url,
			"type": type,
			"content": request.response_body if request.response_body else "",
			"size": request.size,
			"status": request.status_code,
			"mime_type": request.mime_type,
			"request": request
		}
		resources_by_type[type].append(file_info)
	
	var html_item = file_tree.create_item(root)
	html_item.set_text(0, "HTML Documents")
	html_item.set_icon(0, get_icon_for_type("html"))
	
	if resources_by_type.has("html"):
		for resource in resources_by_type["html"]:
			var resource_item = file_tree.create_item(html_item)
			var name = resource.get("name", "Unknown")
			var size = resource.get("size", 0)
			var status = resource.get("status", 0)
			
			var display_text = name
			if size > 0:
				display_text += " (" + format_file_size(size) + ")"
			if status > 0:
				display_text += " [" + str(status) + "]"
			
			resource_item.set_text(0, display_text)
			resource_item.set_icon(0, get_icon_for_type("html"))
			resource_item.set_metadata(0, resource)
	
	var category_order = ["script", "image", "other"]
	for type in category_order:
		if resources_by_type.has(type) and resources_by_type[type].size() > 0:
			var type_item = file_tree.create_item(root)
			var type_display_name = get_type_display_name(type)
			type_item.set_text(0, type_display_name)
			type_item.set_icon(0, get_icon_for_type(type))
			
			for resource in resources_by_type[type]:
				var resource_item = file_tree.create_item(type_item)
				var name = resource.get("name", "Unknown")
				var size = resource.get("size", 0)
				var status = resource.get("status", 0)
				
				var display_text = name
				if size > 0:
					display_text += " (" + format_file_size(size) + ")"
				if status > 0:
					display_text += " [" + str(status) + "]"
				
				resource_item.set_text(0, display_text)
				resource_item.set_icon(0, get_icon_for_type(type))
				resource_item.set_metadata(0, resource)


func get_type_display_name(type: String) -> String:
	match type:
		"html":
			return "HTML Documents"
		"css":
			return "Stylesheets"
		"script":
			return "Scripts"
		"image":
			return "Images"
		"audio":
			return "Audio Files"
		"font":
			return "Fonts"
		_:
			return type.capitalize() + " Files"

func get_icon_for_type(type: String) -> Texture2D:
	return null

func clear_file_tree():
	file_tree.clear()
	clear_preview()

func clear_preview():
	preview_image.visible = false
	preview_text.visible = false
	preview_audio.stop()
	preview_label.visible = true
	preview_label.text = "Select a file to preview"
	
	for child in preview_container.get_children():
		if child != preview_label and child != preview_image and child != preview_text and child != preview_audio:
			child.queue_free()

func _on_file_selected():
	var selected_item = file_tree.get_selected()
	if not selected_item:
		return
	
	var metadata = selected_item.get_metadata(0)
	if not metadata:
		return
	
	selected_file = metadata
	show_preview(metadata)

func _on_file_activated():
	_on_file_selected()

func _on_tree_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var selected_item = file_tree.get_selected()
		if not selected_item:
			return
		
		var metadata = selected_item.get_metadata(0)
		if not metadata:
			return
		
		var context_menu = PopupMenu.new()
		context_menu.add_item("Copy Content", 0)
		context_menu.add_item("Copy URL", 1)
		context_menu.size = Vector2(140, 30)
		context_menu.position = get_global_mouse_position()
		add_child(context_menu)
		
		context_menu.id_pressed.connect(_on_context_menu_selected.bind(context_menu, metadata))
		context_menu.popup()

func _on_context_menu_selected(id: int, context_menu: PopupMenu, metadata: Dictionary):
	match id:
		0:
			copy_content(metadata)
		1:
			copy_url(metadata)
	
	context_menu.queue_free()

func copy_content(metadata: Dictionary):
	var content = metadata.get("content", "")
	if content.length() > 0:
		DisplayServer.clipboard_set(content)

func copy_url(metadata: Dictionary):
	var url = metadata.get("url", "")
	if url.length() > 0:
		DisplayServer.clipboard_set(url)


func show_preview(metadata: Dictionary):
	clear_preview()
	
	var type = metadata.get("type", "")
	var content = metadata.get("content", "")
	var url = metadata.get("url", "")
	
	match type:
		"html":
			show_text_preview(str(content), "HTML")
		"css":
			show_text_preview(str(content), "CSS")
		"script":
			show_text_preview(str(content), "JavaScript")
		"image":
			if url.length() > 0:
				show_image_preview(str(url))
			else:
				preview_label.text = "No image URL available"
		"audio":
			if url.length() > 0:
				show_audio_preview(str(url))
			else:
				preview_label.text = "No audio URL available"
		"font":
			show_text_preview("Font: " + str(metadata.get("name", "")), "Font")
		_:
			var file_content = metadata.get("content", "")
			if file_content.length() > 0:
				show_text_preview(str(file_content), type.capitalize())
			else:
				preview_label.text = "No preview available for " + type

func show_text_preview(content: String, title: String):
	preview_label.visible = false
	preview_image.visible = false
	preview_audio.stop()
	preview_text.visible = false
	
	var syntax_highlighter = preload("res://Resources/LuaSyntaxHighlighter.tres")
	var code_edit = CodeEditUtils.create_code_edit({
		"text": content,
		"editable": false,
		"show_line_numbers": true,
		"syntax_highlighter": syntax_highlighter.duplicate()
	})
	preview_container.add_child(code_edit)

func show_image_preview(url: String):
	preview_label.visible = false
	preview_text.visible = false
	preview_audio.stop()
	preview_image.visible = false
	
	var found_request = null
	for request in NetworkManager.get_all_requests():
		if request.url == url:
			found_request = request
			break
		
	if found_request and found_request.response_body_bytes.size() > 0:
		var image = Image.new()
		var response_bytes = found_request.response_body_bytes
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
			
			var img_size = image.get_size()
			var max_size = 300.0
			var scale_factor = min(max_size / img_size.x, max_size / img_size.y, 1.0)
			
			preview_image.texture = texture
			preview_image.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
			preview_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			preview_image.custom_minimum_size = Vector2(img_size.x * scale_factor, img_size.y * scale_factor)
			preview_image.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			preview_image.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			preview_image.visible = true
			
			preview_label.visible = true
			preview_label.text = str(img_size.x) + " × " + str(img_size.y)
			preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			preview_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		else:
			preview_label.visible = true
			preview_label.text = "Failed to load image data (Error: " + str(load_error) + ")"
	else:
		preview_label.visible = true
		preview_label.text = "Image not loaded yet"

func show_image_info(file_info: Dictionary):
	var request = file_info.get("request")
	if not request:
		return
	
	var info_text = "Image: " + file_info.get("name", "Unknown") + "\n"
	info_text += "Size: " + format_file_size(file_info.get("size", 0)) + "\n"
	info_text += "Dimensions: " + get_image_dimensions(request.response_body_bytes) + "\n"
	info_text += "Format: " + get_image_format(request.response_body_bytes) + "\n"
	info_text += "URL: " + file_info.get("url", "")
	
	preview_label.visible = true
	preview_label.text = info_text

func get_image_dimensions(body: PackedByteArray) -> String:
	var image = Image.new()
	var error = image.load_png_from_buffer(body)
	if error == OK:
		return str(image.get_width()) + "x" + str(image.get_height())
	
	error = image.load_jpg_from_buffer(body)
	if error == OK:
		return str(image.get_width()) + "x" + str(image.get_height())
	
	error = image.load_webp_from_buffer(body)
	if error == OK:
		return str(image.get_width()) + "x" + str(image.get_height())
	
	error = image.load_bmp_from_buffer(body)
	if error == OK:
		return str(image.get_width()) + "x" + str(image.get_height())
	
	return "Unknown"

func get_image_format(body: PackedByteArray) -> String:
	if body.size() >= 8:
		var png_header = PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
		if body.slice(0, 8) == png_header:
			return "PNG"
		elif body.slice(0, 2) == PackedByteArray([0xFF, 0xD8]):
			return "JPEG"
		elif body.slice(0, 4) == PackedByteArray([0x52, 0x49, 0x46, 0x46]) and body.slice(8, 12) == PackedByteArray([0x57, 0x45, 0x42, 0x50]):
			return "WebP"
		elif body.slice(0, 2) == PackedByteArray([0x42, 0x4D]):
			return "BMP"
	
	return "Unknown"

func show_audio_preview(url: String):
	preview_label.visible = false
	preview_text.visible = false
	preview_image.visible = false
	
	preview_audio.stop()
	
	var found_request = null
	for request in NetworkManager.get_all_requests():
		if request.url == url:
			found_request = request
			break
	
	if found_request and found_request.response_body_bytes.size() > 0:
		load_audio_from_bytes(found_request.response_body_bytes)
		show_audio_info({"request": found_request})
	else:
		preview_label.visible = true
		preview_label.text = "Audio not loaded yet"

func show_audio_info(file_info: Dictionary):
	var request = file_info.get("request")
	if not request:
		return
	
	var info_text = "Audio: " + file_info.get("name", "Unknown") + "\n"
	info_text += "Size: " + format_file_size(file_info.get("size", 0)) + "\n"
	info_text += "Format: " + get_audio_format(request.response_body_bytes) + "\n"
	info_text += "Duration: " + get_audio_duration(request.response_body_bytes) + "\n"
	info_text += "URL: " + file_info.get("url", "")
	
	preview_label.visible = true
	preview_label.text = info_text

func get_audio_format(body: PackedByteArray) -> String:
	if body.size() >= 12:
		if body.slice(0, 4) == PackedByteArray([0x52, 0x49, 0x46, 0x46]) and body.slice(8, 12) == PackedByteArray([0x57, 0x41, 0x56, 0x45]):
			return "WAV"
		elif body.slice(0, 4) == PackedByteArray([0x4F, 0x67, 0x67, 0x53]):
			return "OGG"
		elif body.slice(0, 3) == PackedByteArray([0xFF, 0xFB, 0x90]) or body.slice(0, 3) == PackedByteArray([0xFF, 0xFA, 0x90]):
			return "MP3"
	
	return "Unknown"

func get_audio_duration(body: PackedByteArray) -> String:
	var audio_stream = AudioStreamWAV.new()
	audio_stream.data = body
	if audio_stream.get_length() > 0:
		var duration = audio_stream.get_length()
		var minutes = int(duration) / 60
		var seconds = int(duration) % 60
		return str(minutes) + ":" + str(seconds).pad_zeros(2)
	
	return "Unknown"



func load_audio_from_bytes(body: PackedByteArray):
	var audio_stream = AudioStreamWAV.new()
	audio_stream.data = body
	preview_audio.stream = audio_stream
	preview_audio.play()
	
	preview_label.visible = true
	preview_label.text = "Playing audio file..."

func format_file_size(bytes: int) -> String:
	if bytes < 1024:
		return str(bytes) + " B"
	elif bytes < 1024 * 1024:
		return str(bytes / 1024) + " KB"
	else:
		return str(bytes / (1024 * 1024)) + " MB"

func _exit_tree():
	clear_preview()
	if current_tab:
		disconnect_tab_signals()
