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
var file_resources: Dictionary = {}
var selected_file: Dictionary = {}

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
	
	# Connect to network manager signals
	NetworkManager.request_completed.connect(_on_network_request_completed)
	
	# Get existing requests
	for request in NetworkManager.get_all_requests():
		_on_network_request_completed(request)

func set_current_tab(tab: Tab):
	if current_tab and current_tab != tab:
		file_resources.clear()
	
	if current_tab:
		disconnect_tab_signals()
	
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

func disconnect_tab_signals():
	if current_tab:
		if current_tab.has_signal("content_updated"):
			current_tab.content_updated.disconnect(_on_content_updated)
		if current_tab.has_signal("tab_pressed"):
			current_tab.tab_pressed.disconnect(_on_tab_pressed)

func disconnect_network_signals():
	if NetworkManager.request_completed.is_connected(_on_network_request_completed):
		NetworkManager.request_completed.disconnect(_on_network_request_completed)

func _on_content_updated():
	update_file_tree()

func _on_tab_pressed():
	if current_tab and current_tab.lua_apis.size() > 0:
		current_parser = current_tab.lua_apis[0].dom_parser
		update_file_tree()

func refresh_sources():
	update_file_tree()

func _on_visibility_changed():
	if visible:
		refresh_sources()

func _on_network_request_completed(request: NetworkRequest):
	if not request:
		return
	
	var file_info = {
		"name": request.name,
		"url": request.url,
		"type": get_resource_type_from_request(request),
		"content": request.response_body if request.response_body else "",
		"size": request.size,
		"status": request.status_code,
		"mime_type": request.mime_type,
		"request": request
	}
	
	var file_key = request.url
	file_resources[file_key] = file_info
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
			var url = request.url.to_lower()
			var mime_type = request.mime_type.to_lower()
			if "script" in mime_type or url.ends_with(".js"):
				return "script"
			elif "css" in mime_type or url.ends_with(".css"):
				return "css"
			elif "image" in mime_type or url.ends_with(".png") or url.ends_with(".jpg") or url.ends_with(".jpeg") or url.ends_with(".gif") or url.ends_with(".svg"):
				return "image"
			elif "audio" in mime_type or url.ends_with(".mp3") or url.ends_with(".wav") or url.ends_with(".ogg"):
				return "audio"
			elif "font" in mime_type or url.ends_with(".ttf") or url.ends_with(".woff") or url.ends_with(".woff2"):
				return "font"
			elif url.ends_with(".html") or url.ends_with(".htm"):
				return "html"
			else:
				return "other"
		_:
			return "other"

func update_file_tree():
	clear_file_tree()
	
	if not current_parser or not current_parser.parse_result:
		var root = file_tree.create_item()
		root.set_text(0, "Resources")
		root.set_icon(0, get_icon_for_type("html"))
		add_network_resources_to_tree(root)
		root.set_collapsed(false)
		return
	
	var root = file_tree.create_item()
	root.set_text(0, current_tab.current_url.get_file() if current_tab else "Document")
	root.set_icon(0, get_icon_for_type("html"))
	
	add_inline_resources_to_tree(root)
	add_network_resources_to_tree(root)
	
	root.set_collapsed(false)

func add_inline_resources_to_tree(root: TreeItem):
	# Don't show inline CSS or JS files anymore
	# Only show the main HTML document
	pass

func add_network_resources_to_tree(root: TreeItem):
	var resources_by_type = {}
	var current_domain = get_current_domain()
	
	for file_key in file_resources.keys():
		var resource = file_resources[file_key]
		var url = resource.get("url", "")
		
		# Only show resources from current domain
		if not is_from_current_domain(url, current_domain):
			continue
			
		var type = resource.get("type", "other")
		if not resources_by_type.has(type):
			resources_by_type[type] = []
		resources_by_type[type].append(resource)
	
	# Add HTML Documents first (including main document)
	var html_item = file_tree.create_item(root)
	html_item.set_text(0, "HTML Documents")
	html_item.set_icon(0, get_icon_for_type("html"))
	
	# Add main document
	var main_doc_item = file_tree.create_item(html_item)
	main_doc_item.set_text(0, current_tab.current_url.get_file() if current_tab else "Document")
	main_doc_item.set_icon(0, get_icon_for_type("html"))
	main_doc_item.set_metadata(0, {
		"type": "html",
		"content": get_full_html_content(),
		"url": current_tab.current_url if current_tab else ""
	})
	
	# Don't add other HTML documents - we already have the main one
	# This prevents showing duplicate HTML documents
	
	# Add other categories in specific order
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
				var url = resource.get("url", "")
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

func get_current_domain() -> String:
	if current_tab and current_tab.current_url:
		var url = current_tab.current_url
		if url.begins_with("gurt://"):
			return "gurt://" + url.split("/")[2] if url.split("/").size() > 2 else url
		elif url.begins_with("http://") or url.begins_with("https://"):
			return url.split("/")[0] + "//" + url.split("/")[2] if url.split("/").size() > 2 else url
	return ""

func is_from_current_domain(url: String, current_domain: String) -> bool:
	if current_domain.is_empty():
		return true
	
	# Filter out internal Flumi resources
	if url.begins_with("res://") or url.begins_with("user://"):
		return false
	
	# Filter out common browser internal resources
	var internal_patterns = [
		"256px-Skull_danger.svg.png",
		"295128.png", 
		"126472.png",
		"46-512.png",
		"logo.png",
		"gronk2.png",
		"mEg1mYf.png",
		"ezgif-3ee8f21908313a.webp",
		"32x32",
		"www.example.com"
	]
	
	for pattern in internal_patterns:
		if url.ends_with(pattern) or url.contains(pattern):
			return false
	
	# For gurt:// URLs, be more permissive - allow any gurt:// resource
	if url.begins_with("gurt://"):
		return true
	elif url.begins_with("http://") or url.begins_with("https://"):
		var url_domain = url.split("/")[0] + "//" + url.split("/")[2] if url.split("/").size() > 2 else url
		return url_domain == current_domain
	
	return true

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

func get_full_html_content() -> String:
	if not current_parser or not current_parser.parse_result:
		return ""
	
	var html = "<!DOCTYPE html>\n<html>\n"
	
	var head = current_parser.find_first("head")
	if head:
		html += "<head>\n"
		html += element_to_html_with_children(head, 1)
		html += "</head>\n"
	
	var body = current_parser.find_first("body")
	if body:
		html += "<body>\n"
		html += element_to_html_with_children(body, 1)
		html += "</body>\n"
	
	html += "</html>"
	return html

func clear_file_tree():
	file_tree.clear()
	# Don't clear file_resources - we want to keep network resources
	clear_preview()

func clear_preview():
	preview_image.visible = false
	preview_text.visible = false
	preview_audio.stop()
	preview_label.visible = true
	preview_label.text = "Select a file to preview"

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
			preview_label.text = "No preview available for " + type

func show_text_preview(content: String, title: String):
	preview_label.visible = false
	preview_image.visible = false
	preview_audio.stop()
	preview_text.visible = true
	
	preview_text.text = content
	preview_text.editable = false
	preview_text.selecting_enabled = true

func show_image_preview(url: String):
	preview_label.visible = false
	preview_text.visible = false
	preview_audio.stop()
	preview_image.visible = true
	
	preview_image.texture = null
	preview_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	
	var file_info = file_resources.get(url)
	if file_info and file_info.has("request"):
		var request = file_info["request"]
		if request.response_body_bytes.size() > 0:
			load_image_from_bytes(request.response_body_bytes)
		else:
			load_image_directly(url)
	else:
		for key in file_resources.keys():
			var resource = file_resources[key]
			if resource.get("url", "") == url:
				file_info = resource
				break
		
		if file_info and file_info.has("request"):
			var request = file_info["request"]
			if request.response_body_bytes.size() > 0:
				load_image_from_bytes(request.response_body_bytes)
			else:
				preview_label.visible = true
				preview_label.text = "No image data available"
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
	
	var file_info = file_resources.get(url)
	if file_info and file_info.has("request"):
		var request = file_info["request"]
		if request.response_body_bytes.size() > 0:
			load_audio_from_bytes(request.response_body_bytes)
			show_audio_info(file_info)
		else:
			preview_label.visible = true
			preview_label.text = "No audio data available"
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

func load_image_from_bytes(body: PackedByteArray):
	var image = Image.new()
	var error = OK
	
	# Try PNG first
	error = image.load_png_from_buffer(body)
	if error == OK:
		var texture = ImageTexture.new()
		texture.create_from_image(image)
		preview_image.texture = texture
		show_image_resolution(image)
		return
	
	# Try JPEG
	error = image.load_jpg_from_buffer(body)
	if error == OK:
		var texture = ImageTexture.new()
		texture.create_from_image(image)
		preview_image.texture = texture
		show_image_resolution(image)
		return
	
	# Try WebP
	error = image.load_webp_from_buffer(body)
	if error == OK:
		var texture = ImageTexture.new()
		texture.create_from_image(image)
		preview_image.texture = texture
		show_image_resolution(image)
		return
	
	# Try BMP
	error = image.load_bmp_from_buffer(body)
	if error == OK:
		var texture = ImageTexture.new()
		texture.create_from_image(image)
		preview_image.texture = texture
		show_image_resolution(image)
		return
	
	# If all else fails, try to create a texture directly from the raw data
	var texture = ImageTexture.new()
	var raw_image = Image.create_from_data(100, 100, false, Image.FORMAT_RGBA8, body)
	if raw_image:
		texture.create_from_image(raw_image)
		preview_image.texture = texture
		show_image_resolution(raw_image)
		return
	
	preview_label.visible = true
	preview_label.text = "Failed to load image data (unsupported format)"

func show_image_resolution(image: Image):
	preview_label.visible = true
	preview_label.text = str(image.get_width()) + " × " + str(image.get_height())

func load_image_directly(url: String):
	if url.begins_with("gurt://"):
		var gurt_body = await Network.fetch_gurt_resource(url, true)
		if not gurt_body.is_empty():
			load_image_from_bytes(gurt_body)
			return
	elif url.begins_with("http://") or url.begins_with("https://"):
		var http_request = HTTPRequest.new()
		add_child(http_request)
		
		var request_error = http_request.request(url)
		if request_error == OK:
			var response = await http_request.request_completed
			var result = response[0]
			var response_code = response[1]
			var body = response[3]
			
			if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
				load_image_from_bytes(body)
				http_request.queue_free()
				return
		
		http_request.queue_free()
	
	preview_label.visible = true
	preview_label.text = "Failed to load image: " + url

func load_audio_from_bytes(body: PackedByteArray):
	var audio_stream = AudioStreamWAV.new()
	audio_stream.data = body
	preview_audio.stream = audio_stream
	preview_audio.play()
	
	preview_label.visible = true
	preview_label.text = "Playing audio file..."

func element_to_html_with_children(element: HTMLParser.HTMLElement, indent_level: int = 0) -> String:
	var indent = ""
	for i in indent_level:
		indent += "  "
	
	var html = indent + "<" + element.tag_name
	
	for attr_name in element.attributes:
		var attr_value = element.attributes[attr_name]
		html += " " + attr_name + "=\"" + attr_value + "\""
	
	if element.is_self_closing:
		html += " />\n"
	else:
		html += ">"
		var text_content = element.text_content.strip_edges()
		
		if text_content.length() > 0:
			if element.children.size() > 0:
				html += "\n" + indent + "  " + text_content + "\n"
			else:
				html += text_content
		elif element.children.size() > 0:
			html += "\n"
		
		for child in element.children:
			html += element_to_html_with_children(child, indent_level + 1)
		
		if element.children.size() > 0:
			html += indent
		html += "</" + element.tag_name + ">\n"
	
	return html

func beautify_css(css: String) -> String:
	var result = ""
	var indent_level = 0
	var i = 0
	
	while i < css.length():
		var char = css[i]
		
		if char == "{":
			result += " {\n"
			indent_level += 1
			result += "  ".repeat(indent_level)
		elif char == "}":
			indent_level = max(0, indent_level - 1)
			result += "\n" + "  ".repeat(indent_level) + "}\n"
			if indent_level > 0:
				result += "  ".repeat(indent_level)
		elif char == ";":
			result += ";\n" + "  ".repeat(indent_level)
		elif char == "\n":
			result += "\n" + "  ".repeat(indent_level)
		else:
			result += char
		
		i += 1
	
	return result

func beautify_javascript(js: String) -> String:
	var result = ""
	var indent_level = 0
	var in_string = false
	var string_char = ""
	
	for i in js.length():
		var char = js[i]
		
		if not in_string:
			if char == '"' or char == "'":
				in_string = true
				string_char = char
				result += char
			elif char == "{":
				result += char + "\n"
				indent_level += 1
				result += "  ".repeat(indent_level)
			elif char == "}":
				indent_level = max(0, indent_level - 1)
				result += "\n" + "  ".repeat(indent_level) + char
			elif char == ";":
				result += char + "\n" + "  ".repeat(indent_level)
			else:
				result += char
		else:
			result += char
			if char == string_char and (i == 0 or js[i-1] != "\\"):
				in_string = false
	
	return result

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
	disconnect_network_signals()
