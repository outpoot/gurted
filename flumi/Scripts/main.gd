class_name Main
extends Control

@onready var website_container: Control = %WebsiteContainer
@onready var tab_container: TabManager = $VBoxContainer/TabContainer
@onready var search_bar: LineEdit = $VBoxContainer/HBoxContainer/LineEdit
@onready var back_button: Button = $VBoxContainer/HBoxContainer/BackButton
@onready var forward_button: Button = $VBoxContainer/HBoxContainer/ForwardButton
@onready var refresh_button: Button = $VBoxContainer/HBoxContainer/RefreshButton

const LOADER_CIRCLE = preload("res://Assets/Icons/loader-circle.svg")
const AUTO_SIZING_FLEX_CONTAINER = preload("res://Scripts/Engine/AutoSizingFlexContainer.gd")

const P = preload("res://Scenes/Tags/p.tscn")
const IMG = preload("res://Scenes/Tags/img.tscn")
const SEPARATOR = preload("res://Scenes/Tags/separator.tscn")
const PRE = P
const BR = preload("res://Scenes/Tags/br.tscn")
const SPAN = preload("res://Scenes/Tags/span.tscn")
const H1 = P
const H2 = P
const H3 = P
const H4 = P
const H5 = P
const H6 = P
const FORM = preload("res://Scenes/Tags/form.tscn")
const INPUT = preload("res://Scenes/Tags/input.tscn")
const BUTTON = preload("res://Scenes/Tags/button.tscn")
const UL = preload("res://Scenes/Tags/ul.tscn")
const OL = preload("res://Scenes/Tags/ol.tscn")
const SELECT = preload("res://Scenes/Tags/select.tscn")
const TEXTAREA = preload("res://Scenes/Tags/textarea.tscn")
const DIV = preload("res://Scenes/Tags/div.tscn")
const AUDIO = preload("res://Scenes/Tags/audio.tscn")
const POSTPROCESS = preload("res://Scenes/Tags/postprocess.tscn")
const CANVAS = preload("res://Scenes/Tags/canvas.tscn")

const DOWNLOAD_MANAGER = preload("res://Scripts/Browser/DownloadManager.gd")

const MIN_SIZE = Vector2i(750, 200)

var font_dependent_elements: Array = []
var current_domain = ""
var main_navigation_request: NetworkRequest = null
var network_start_time: float = 0.0
var network_end_time: float = 0.0
var download_manager: DownloadManager = null

func should_group_as_inline(element: HTMLParser.HTMLElement) -> bool:
	if element.tag_name == "input":
		var parent = element.parent
		while parent:
			if parent.tag_name == "form":
				return true
			parent = parent.parent
		return false
	
	return element.is_inline_element()

func _ready():
	ProjectSettings.set_setting("display/window/size/min_width", MIN_SIZE.x)
	ProjectSettings.set_setting("display/window/size/min_height", MIN_SIZE.y)
	DisplayServer.window_set_min_size(MIN_SIZE)
	
	CertificateManager.initialize()
	
	download_manager = DOWNLOAD_MANAGER.new(self)
	add_child(download_manager)
	
	var original_scroll = website_container.get_parent()
	if original_scroll:
		original_scroll.visible = false
	
	call_deferred("render")
	call_deferred("update_navigation_buttons")
	call_deferred("_handle_startup_behavior")

func _input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("DevTools"):
		_toggle_dev_tools()
		get_viewport().set_input_as_handled()

func _toggle_dev_tools() -> void:
	var active_tab = get_active_tab()
	if active_tab:
		active_tab.toggle_dev_tools()

func resolve_url(href: String) -> String:
	return URLUtils.resolve_url(current_domain, href)

func handle_link_click(meta: Variant) -> void:
	var href = str(meta)
	
	var resolved_url = resolve_url(href)
	
	if URLUtils.is_local_file_url(resolved_url):
		_on_search_submitted(resolved_url)
	elif GurtProtocol.is_gurt_domain(resolved_url):
		_on_search_submitted(resolved_url)
	else:
		OS.shell_open(resolved_url)

func _on_search_submitted(url: String, add_to_history: bool = true) -> void:
	print("Search submitted: ", url)
	
	search_bar.release_focus()
	
	if URLUtils.is_local_file_url(url):
		var tab = tab_container.tabs[tab_container.active_tab]
		tab.start_loading()
		
		await fetch_local_file_content_async(url, tab, url, add_to_history)
	elif GurtProtocol.is_gurt_domain(url):
		print("Processing as GURT domain")
		
		var tab = tab_container.tabs[tab_container.active_tab]
		tab.start_loading()
		
		var gurt_url = url
		if not gurt_url.begins_with("gurt://"):
			gurt_url = "gurt://" + gurt_url
		
		await fetch_gurt_content_async(gurt_url, tab, url, add_to_history)
	else:
		print("Non-GURT URL entered, using search engine: ", url)
		
		if url.begins_with("http://") or url.begins_with("https://"):
			# It's already a web URL, open in system browser
			OS.shell_open(url)
		else:
			var search_engine_url = get_search_engine_url()
			var search_url = search_engine_url + url.uri_encode()
			_on_search_submitted(search_url, add_to_history)

func fetch_gurt_content_async(gurt_url: String, tab: Tab, original_url: String, add_to_history: bool = true) -> void:
	main_navigation_request = NetworkManager.start_request(gurt_url, "GET", false)
	main_navigation_request.type = NetworkRequest.RequestType.DOC
	network_start_time = Time.get_ticks_msec()
	
	var thread = Thread.new()
	var request_data = {"gurt_url": gurt_url}
	
	thread.start(_perform_gurt_request_threaded.bind(request_data))
	
	while thread.is_alive():
		await get_tree().process_frame
	
	var result = thread.wait_to_finish()
	
	_handle_gurt_result(result, tab, original_url, gurt_url, add_to_history)

func _perform_gurt_request_threaded(request_data: Dictionary) -> Dictionary:
	var gurt_url: String = request_data.gurt_url
	var client = GurtProtocolClient.new()
	
	for ca_cert in CertificateManager.trusted_ca_certificates:
		client.add_ca_certificate(ca_cert)
	
	if not client.create_client_with_dns(30, GurtProtocol.DNS_SERVER_IP, GurtProtocol.DNS_SERVER_PORT):
		client.disconnect()
		return {"success": false, "error": "Failed to connect to GURT DNS server at " + GurtProtocol.DNS_SERVER_IP + ":" + str(GurtProtocol.DNS_SERVER_PORT)}
	
	var response = client.request(gurt_url, {
		"method": "GET"
	})
	client.disconnect()
	
	if not response or not response.is_success:
		var error_msg = "Connection failed"
		if response:
			error_msg = "GURT %d: %s" % [response.status_code, response.status_message]
		else:
			error_msg = "Request timed out or connection failed"
		return {"success": false, "error": error_msg}
	
	return {"success": true, "html_bytes": response.body}

func fetch_local_file_content_async(file_url: String, tab: Tab, original_url: String, add_to_history: bool = true) -> void:
	var file_path = URLUtils.file_url_to_path(file_url)
	
	if FileUtils.is_directory(file_path):
		handle_local_file_error("Directory browsing is not supported. Please specify a file.", tab)
		return
	
	if not FileAccess.file_exists(file_path):
		handle_local_file_error("File not found: " + file_path, tab)
		return
	
	if not FileUtils.is_supported_file(file_path):
		handle_local_file_error("Unsupported file type: " + file_path.get_extension(), tab)
		return
	
	var result = FileUtils.read_local_file(file_path)
	
	if result.success:
		if FileUtils.is_html_file(file_path):
			handle_local_file_result({"success": true, "html_bytes": result.content}, tab, original_url, file_url, add_to_history)
		else:
			var content_str = result.content.get_string_from_utf8()
			var wrapped_html = """<head>
	<title>""" + file_path.get_file() + """</title>
	<style>
		body { bg-[#ffffff] text-[#202124] font-mono p-6 m-0 }
		.file-content { bg-[#f8f9fa] p-4 rounded-md overflow-auto }
	</style>
</head>
<body>
	<h1>""" + file_path.get_file() + """</h1>
	<div style="file-content">
		<pre>""" + content_str.xml_escape() + """</pre>
	</div>
</body>"""
			handle_local_file_result({"success": true, "html_bytes": wrapped_html.to_utf8_buffer()}, tab, original_url, file_url, add_to_history)
	else:
		handle_local_file_error(result.error, tab)

func handle_local_file_result(result: Dictionary, tab: Tab, original_url: String, file_url: String, add_to_history: bool = true) -> void:
	var html_bytes = result.html_bytes
	
	current_domain = file_url
	if not search_bar.has_focus():
		search_bar.text = original_url
	
	render_content(html_bytes)
	
	tab.stop_loading()
	
	if add_to_history:
		add_to_history(file_url, tab)
	else:
		update_navigation_buttons()

func handle_local_file_error(error_message: String, tab: Tab) -> void:
	var error_html = FileUtils.create_error_page("File Access Error", error_message)
	
	render_content(error_html)
	
	const FOLDER_ICON = preload("res://Assets/Icons/folder.svg")
	tab.stop_loading()
	if FOLDER_ICON:
		tab.set_icon(FOLDER_ICON)
	else:
		var GLOBE_ICON = preload("res://Assets/Icons/globe.svg")
		tab.set_icon(GLOBE_ICON)

func _handle_gurt_result(result: Dictionary, tab: Tab, original_url: String, gurt_url: String, add_to_history: bool = true) -> void:
	if not result.success:
		print("GURT request failed: ", result.error)
		handle_gurt_error(result.error, tab)
		return
	
	var html_bytes = result.html_bytes
	network_end_time = Time.get_ticks_msec()
	
	current_domain = gurt_url
	if not search_bar.has_focus():
		search_bar.text = original_url  # Show the original input in search bar
	
	render_content(html_bytes)
	
	if main_navigation_request:
		main_navigation_request.end_time = network_end_time
		main_navigation_request.time_ms = network_end_time - network_start_time
		var headers = {"content-type": "text/html"}
		var body_text = html_bytes.get_string_from_utf8()
		NetworkManager.complete_request(main_navigation_request.id, 200, "OK", headers, body_text, html_bytes)
		main_navigation_request = null
	
	tab.stop_loading()
	
	if add_to_history:
		add_to_history(gurt_url, tab)
	else:
		update_navigation_buttons()

func handle_gurt_error(error_message: String, tab: Tab) -> void:
	var error_html = GurtProtocol.create_error_page(error_message)
	
	render_content(error_html)
	
	const GLOBE_ICON = preload("res://Assets/Icons/globe.svg")
	tab.stop_loading()
	tab.set_icon(GLOBE_ICON)

func _on_search_focus_entered() -> void:
	if not current_domain.is_empty():
		search_bar.text = current_domain

func _on_search_focus_exited() -> void:
	if not current_domain.is_empty():
		var display_text = current_domain
		if display_text.begins_with("gurt://"):
			display_text = display_text.substr(7)
		elif display_text.begins_with("file://"):
			display_text = URLUtils.file_url_to_path(display_text)
		search_bar.text = display_text

func render() -> void:
	render_content(Constants.HTML_CONTENT)

func render_content(html_bytes: PackedByteArray) -> void:
	if main_navigation_request:
		NetworkManager.clear_all_requests_except(main_navigation_request.id)
	else:
		NetworkManager.clear_all_requests()
	
	var active_tab = get_active_tab()
	var target_container: Control
	
	if active_tab and active_tab.website_container:
		target_container = active_tab.website_container
	else:
		target_container = website_container
		
	if not target_container:
		print("Error: No container available for rendering")
		return
	
	if active_tab:
		var existing_tab_lua_apis = active_tab.lua_apis
		for lua_api in existing_tab_lua_apis:
			if is_instance_valid(lua_api):
				lua_api.kill_script_execution()
				remove_child(lua_api)
				lua_api.queue_free()
		active_tab.lua_apis.clear()
		
		var existing_postprocess = []
		for child in get_children():
			if child is HTMLPostprocess:
				existing_postprocess.append(child)
		
		for postprocess in existing_postprocess:
			remove_child(postprocess)
			postprocess.queue_free()
		
		if active_tab.background_panel:
			var existing_overlay = active_tab.background_panel.get_node_or_null("PostprocessOverlay")
			if existing_overlay:
				existing_overlay.queue_free()
	else:
		var existing_lua_apis = []
		for child in get_children():
			if child is LuaAPI:
				existing_lua_apis.append(child)
		
		for lua_api in existing_lua_apis:
			lua_api.kill_script_execution()
			remove_child(lua_api)
			lua_api.queue_free()
	
	var postprocess_nodes: Array[Node] = []
	for child in get_children():
		if child is HTMLPostprocess:
			postprocess_nodes.append(child)
	for node in postprocess_nodes:
		remove_child(node)
		node.queue_free()
	
	var default_panel = website_container.get_parent()
	if default_panel and default_panel.has_method("get_node_or_null"):
		var existing_overlay = default_panel.get_node_or_null("PostprocessOverlay")
		if existing_overlay:
			existing_overlay.queue_free()
	
	if target_container.get_parent() and target_container.get_parent().name == "BodyMarginContainer":
		var body_margin_container = target_container.get_parent()
		var scroll_container = body_margin_container.get_parent()
		if scroll_container:
			body_margin_container.remove_child(target_container)
			scroll_container.remove_child(body_margin_container)
			body_margin_container.queue_free()
			scroll_container.add_child(target_container)
	
	for child in target_container.get_children():
		child.queue_free()
	
	font_dependent_elements.clear()
	FontManager.clear_fonts()
	FontManager.set_refresh_callback(refresh_fonts)
	
	var parser: HTMLParser = HTMLParser.new(html_bytes)
	var parse_result = parser.parse()
	
	parser.process_styles()
	
	if parse_result.external_css and not parse_result.external_css.is_empty():
		await parser.process_external_styles(current_domain)
	
	# Process and load all custom fonts defined in <font> tags
	parser.process_fonts(current_domain)
	FontManager.load_all_fonts()
	
	if parse_result.errors.size() > 0:
		print("Parse errors: " + str(parse_result.errors))
	
	var tab = active_tab
	
	var title = parser.get_title()
	tab.set_title(title)
	
	var icon = parser.get_icon()
	tab.update_icon_from_url(icon)
	
	if not icon.is_empty():
		tab.set_meta("parsed_icon_url", icon)
	
	var body = parser.find_first("body")
	
	if body:
		var background_panel = active_tab.background_panel
		
		StyleManager.apply_body_styles(body, parser, target_container, background_panel)
		
		parser.register_dom_node(body, target_container)
	
	var scripts = parser.find_all("script")
	
	var lua_api = LuaAPI.new()
	add_child(lua_api)
	if active_tab:
		active_tab.lua_apis.append(lua_api)
	
	lua_api.dom_parser = parser
	
	if lua_api.threaded_vm:
		lua_api.threaded_vm.dom_parser = parser

	var i = 0
	if body:
		while i < body.children.size():
			var element: HTMLParser.HTMLElement = body.children[i]
			
			if should_group_as_inline(element):
				# Create an HBoxContainer for consecutive inline elements
				var inline_elements: Array[HTMLParser.HTMLElement] = []

				while i < body.children.size() and should_group_as_inline(body.children[i]):
					inline_elements.append(body.children[i])
					i += 1

				var hbox = HBoxContainer.new()
				hbox.add_theme_constant_override("separation", 4)

				for inline_element in inline_elements:
					var inline_node = await create_element_node(inline_element, parser, target_container)
					if inline_node:
						
						# Input elements register their own DOM nodes in their init() function
						if inline_element.tag_name not in ["input", "textarea", "select", "button", "audio"]:
							parser.register_dom_node(inline_element, inline_node)
						
						safe_add_child(hbox, inline_node)
						# Handle hyperlinks for all inline elements
						if contains_hyperlink(inline_element) and inline_node is RichTextLabel:
							inline_node.meta_clicked.connect(handle_link_click)
					else:
						print("Failed to create inline element node: ", inline_element.tag_name)

				safe_add_child(target_container, hbox)
				continue
			
			var element_node = await create_element_node(element, parser, target_container)
			if element_node:
				
				# Input elements register their own DOM nodes in their init() function
				if element.tag_name not in ["input", "textarea", "select", "button", "audio", "canvas"]:
					parser.register_dom_node(element, element_node)
				
				# ul/ol handle their own adding
				if element.tag_name != "ul" and element.tag_name != "ol":
					safe_add_child(target_container, element_node)
					

				if contains_hyperlink(element):
					if element_node is RichTextLabel:
						element_node.meta_clicked.connect(handle_link_click)
					elif element_node.has_method("get") and element_node.get("rich_text_label"):
						element_node.rich_text_label.meta_clicked.connect(handle_link_click)
			else:
				print("Couldn't parse unsupported HTML tag \"%s\"" % element.tag_name)
			
			i += 1
	
	if scripts.size() > 0 and lua_api:
		parser.process_scripts(lua_api, null)
		if parse_result.external_scripts and not parse_result.external_scripts.is_empty():
			# Extract base URL without query parameters for script resolution
			var base_url_for_scripts = current_domain
			var query_pos = base_url_for_scripts.find("?")
			if query_pos != -1:
				base_url_for_scripts = base_url_for_scripts.substr(0, query_pos)
			await parser.process_external_scripts(lua_api, null, base_url_for_scripts)
	
	var postprocess_element = parser.process_postprocess()
	if postprocess_element:
		var postprocess_node = POSTPROCESS.instantiate()
		add_child(postprocess_node)
		await postprocess_node.init(postprocess_element, parser)
	
	active_tab.current_url = current_domain
	active_tab.has_content = true

static func safe_add_child(parent: Node, child: Node) -> void:
	if child.get_parent():
		child.get_parent().remove_child(child)
	parent.add_child(child)
	

func contains_hyperlink(element: HTMLParser.HTMLElement) -> bool:
	if element.tag_name == "a":
		return true
	
	for child in element.children:
		if contains_hyperlink(child):
			return true
	
	return false

func is_text_only_element(element: HTMLParser.HTMLElement) -> bool:
	if element.children.size() == 0:
		var text = element.get_collapsed_text()
		return not text.is_empty()
	
	return false

func create_element_node(element: HTMLParser.HTMLElement, parser: HTMLParser, container: Control = null) -> Control:
	var styles = parser.get_element_styles_with_inheritance(element, "", [])
	var hover_styles = parser.get_element_styles_with_inheritance(element, "hover", [])
	var is_flex_container = styles.has("display") and ("flex" in styles["display"])
	var is_grid_container = styles.has("display") and ("grid" in styles["display"])

	var final_node: Control
	var container_for_children: Node

	# If this is an inline element AND not a flex or grid container, do NOT recursively add child nodes for its children.
	# Only create a node for the outermost inline group; nested inline tags are handled by BBCode.
	if element.is_inline_element() and not is_flex_container and not is_grid_container:
		final_node = await create_element_node_internal(element, parser, container if container else get_active_website_container())
		if not final_node:
			return null
		final_node = StyleManager.apply_element_styles(final_node, element, parser)
		# Flex item properties may still apply
		FlexUtils.apply_flex_item_properties(final_node, styles)
		return final_node

	if is_grid_container:
		if element.tag_name == "div":
			if BackgroundUtils.needs_background_wrapper(styles) or BackgroundUtils.needs_background_wrapper(hover_styles):
				final_node = BackgroundUtils.create_panel_container_with_background(styles, hover_styles)
				var grid_container = GridContainer.new()
				grid_container.name = "Grid_" + element.tag_name
				var vbox = final_node.get_child(0) as VBoxContainer
				vbox.add_child(grid_container)
				container_for_children = grid_container
			else:
				final_node = GridContainer.new()
				final_node.name = "Grid_" + element.tag_name
				container_for_children = final_node
		else:
			final_node = GridContainer.new()
			final_node.name = "Grid_" + element.tag_name
			container_for_children = final_node
	elif is_flex_container:
		# The element's primary identity IS a flex container.
		if element.tag_name == "div":
			if BackgroundUtils.needs_background_wrapper(styles) or BackgroundUtils.needs_background_wrapper(hover_styles):
				final_node = BackgroundUtils.create_panel_container_with_background(styles, hover_styles)
				
				var flex_container = AUTO_SIZING_FLEX_CONTAINER.new()
				flex_container.name = "Flex_" + element.tag_name
				var vbox = final_node.get_child(0) as VBoxContainer
				vbox.add_child(flex_container)
				container_for_children = flex_container
				FlexUtils.apply_flex_container_properties(flex_container, styles)
				
				if flex_container.has_meta("should_fill_horizontal"):
					final_node.set_meta("needs_size_expand_fill", true)
			else:
				final_node = AUTO_SIZING_FLEX_CONTAINER.new()
				final_node.name = "Flex_" + element.tag_name
				container_for_children = final_node
				
				FlexUtils.apply_flex_container_properties(final_node, styles)
		else:
			final_node = AUTO_SIZING_FLEX_CONTAINER.new()
			final_node.name = "Flex_" + element.tag_name
			container_for_children = final_node
			FlexUtils.apply_flex_container_properties(final_node, styles)
		
		# For FLEX ul/ol elements, we need to create the li children directly in the flex container
		if element.tag_name == "ul" or element.tag_name == "ol":
			final_node.flex_direction = FlexContainer.FlexDirection.Column

			var active_container = container if container else get_active_website_container()
			active_container.add_child(final_node)
			
			var temp_list = UL.instantiate() if element.tag_name == "ul" else OL.instantiate()
			active_container.add_child(temp_list)
			await temp_list.init(element, parser)
			
			for child in temp_list.get_children():
				temp_list.remove_child(child)
				container_for_children.add_child(child)
			
			active_container.remove_child(temp_list)
			temp_list.queue_free()
		# If the element itself has text (like <span style="flex">TEXT</span>)
		elif not element.text_content.is_empty():
			var new_node = await create_element_node_internal(element, parser, container if container else get_active_website_container())
			if new_node:
				container_for_children.add_child(new_node)
		# For flex divs, we're done - no additional node creation needed
		elif element.tag_name == "div":
			pass
	else:
		final_node = await create_element_node_internal(element, parser, container if container else get_active_website_container())
		if not final_node:
			return null # Unsupported tag

		# If final_node is a PanelContainer, children should go to the VBoxContainer inside
		if final_node is PanelContainer and final_node.get_child_count() > 0:
			container_for_children = final_node.get_child(0)  # The VBoxContainer inside
		else:
			container_for_children = final_node

	# Applies background, size, etc. to the FlexContainer (top-level node)
	final_node = StyleManager.apply_element_styles(final_node, element, parser)

	if final_node and final_node.has_meta("needs_size_expand_fill"):
		final_node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if final_node.get_child_count() > 0:
			var vbox = final_node.get_child(0)
			vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	if is_grid_container:
		var grid_container_node = final_node
		
		if final_node is GridContainer:
			grid_container_node = final_node
		elif final_node is MarginContainer and final_node.get_child_count() > 0:
			var first_child = final_node.get_child(0)
			if first_child is GridContainer:
				grid_container_node = first_child
		elif final_node is PanelContainer and final_node.get_child_count() > 0:
			var vbox = final_node.get_child(0)
			if vbox is VBoxContainer and vbox.get_child_count() > 0:
				var potential_grid = vbox.get_child(0)
				if potential_grid is GridContainer:
					grid_container_node = potential_grid
		
		if grid_container_node is GridContainer:
			GridUtils.apply_grid_container_properties(grid_container_node, styles)

	FlexUtils.apply_flex_item_properties(final_node, styles)
	
	if not is_grid_container:
		GridUtils.apply_grid_item_properties(final_node, styles)

	# Skip ul/ol and non-flex forms, they handle their own children
	var skip_general_processing = false

	if element.tag_name == "ul" or element.tag_name == "ol":
		skip_general_processing = true
	elif element.tag_name == "form":
		skip_general_processing = not is_flex_container and not is_grid_container
	
	if not skip_general_processing:
		for child_element in element.children:
			# Only add child nodes if the child is NOT an inline element
			# UNLESS the parent is a flex or grid container (inline elements become flex/grid items)
			if not child_element.is_inline_element() or is_flex_container or is_grid_container:
				var child_node = await create_element_node(child_element, parser, container)
				if child_node and is_instance_valid(container_for_children):
					# Input elements register their own DOM nodes in their init() function
					if child_element.tag_name not in ["input", "textarea", "select", "button", "audio"]:
						parser.register_dom_node(child_element, child_node)
					safe_add_child(container_for_children, child_node)
					
					if contains_hyperlink(child_element):
						if child_node is RichTextLabel:
							child_node.meta_clicked.connect(handle_link_click)
						elif child_node.has_method("get") and child_node.get("rich_text_label"):
							child_node.rich_text_label.meta_clicked.connect(handle_link_click)

	return final_node

func create_element_node_internal(element: HTMLParser.HTMLElement, parser: HTMLParser, container: Control = null) -> Control:
	var node: Control = null
	
	match element.tag_name:
		"p":
			node = P.instantiate()
			node.init(element, parser)
		"pre":
			node = PRE.instantiate()
			node.init(element, parser)
		"h1", "h2", "h3", "h4", "h5", "h6":
			match element.tag_name:
				"h1": node = H1.instantiate()
				"h2": node = H2.instantiate()
				"h3": node = H3.instantiate()
				"h4": node = H4.instantiate()
				"h5": node = H5.instantiate()
				"h6": node = H6.instantiate()
			node.init(element, parser)
		"br":
			node = BR.instantiate()
			node.init(element, parser)
		"img":
			node = IMG.instantiate()
			node.init(element, parser)
		"separator":
			node = SEPARATOR.instantiate()
			node.init(element, parser)
		"form":
			var form_styles = parser.get_element_styles_with_inheritance(element, "", [])
			var is_flex_form = form_styles.has("display") and ("flex" in form_styles["display"])
			
			if is_flex_form:
				# Don't create a form node here - return null so general processing takes over
				return null
			else:
				node = FORM.instantiate()
				node.init(element, parser)
				
				# Manually process children for non-flex forms
				for child_element in element.children:
					var child_node = await create_element_node(child_element, parser, container)
					if child_node:
						safe_add_child(node, child_node)
		"input":
			node = INPUT.instantiate()
			node.init(element, parser)
		"button":
			node = BUTTON.instantiate()
			node.init(element, parser)
		"span", "b", "i", "u", "small", "mark", "code", "a":
			node = SPAN.instantiate()
			node.init(element, parser)
		"ul":
			node = UL.instantiate()
			var ul_container = container if container else website_container
			ul_container.add_child(node)
			await node.init(element, parser)
			return node
		"ol":
			node = OL.instantiate()
			var ol_container = container if container else website_container
			ol_container.add_child(node)
			await node.init(element, parser)
			return node
		"li":
			node = P.instantiate()
			node.init(element, parser)
		"select":
			node = SELECT.instantiate()
			node.init(element, parser)
		"textarea":
			node = TEXTAREA.instantiate()
			node.init(element, parser)
		"audio":
			node = AUDIO.instantiate()
			node.init(element, parser)
		"canvas":
			node = CANVAS.instantiate()
			node.init(element, parser)
		"div":
			var styles = parser.get_element_styles_with_inheritance(element, "", [])
			var hover_styles = parser.get_element_styles_with_inheritance(element, "hover", [])
			var is_flex_container = styles.has("display") and ("flex" in styles["display"])
			var is_grid_container = styles.has("display") and ("grid" in styles["display"])
			
			# For flex or grid divs, let the general flex/grid container logic handle them
			if is_flex_container or is_grid_container:
				return null
			
			# Create div container
			if BackgroundUtils.needs_background_wrapper(styles) or BackgroundUtils.needs_background_wrapper(hover_styles):
				node = BackgroundUtils.create_panel_container_with_background(styles, hover_styles)
			else:
				node = DIV.instantiate()
				node.init(element, parser)
			
			var has_only_text = is_text_only_element(element)
			
			if has_only_text:
				var p_node = P.instantiate()
				p_node.init(element, parser)
				
				var div_styles = parser.get_element_styles_with_inheritance(element, "", [])
				StyleManager.apply_styles_to_label(p_node, div_styles, element, parser)
				
				var container_for_children = node
				if node is PanelContainer and node.get_child_count() > 0:
					container_for_children = node.get_child(0)  # The VBoxContainer inside
				
				safe_add_child(container_for_children, p_node)
		_:
			return null
	
	return node

func register_font_dependent_element(label: Control, styles: Dictionary, element: HTMLParser.HTMLElement, parser: HTMLParser) -> void:
	font_dependent_elements.append({
		"label": label,
		"styles": styles,
		"element": element,
		"parser": parser
	})

func refresh_fonts(font_name: String) -> void:
	# Find all elements that should use this font and refresh them
	for element_info in font_dependent_elements:
		var label = element_info["label"]
		var styles = element_info["styles"]
		var element = element_info["element"]
		var parser = element_info["parser"]
		
		if styles.has("font-family") and styles["font-family"] == font_name:
			if is_instance_valid(label):
				StyleManager.apply_styles_to_label(label, styles, element, parser, "", true)

func get_current_url() -> String:
	return current_domain if not current_domain.is_empty() else ""

func reload_current_page() -> void:
	if not current_domain.is_empty():
		_on_search_submitted(current_domain)

func navigate_to_url(url: String, add_to_history: bool = true) -> void:
	if url.begins_with("gurt://") or url.begins_with("file://"):
		_on_search_submitted(url, add_to_history)
	else:
		var resolved_url = resolve_url(url)
		_on_search_submitted(resolved_url, add_to_history)

func update_search_bar_from_current_domain() -> void:
	if not search_bar.has_focus() and not current_domain.is_empty():
		var display_text = current_domain
		if display_text.begins_with("gurt://"):
			display_text = display_text.substr(7)
		elif display_text.begins_with("file://"):
			display_text = URLUtils.file_url_to_path(display_text)
		search_bar.text = display_text

func get_active_tab() -> Tab:
	if tab_container.active_tab >= 0 and tab_container.active_tab < tab_container.tabs.size():
		return tab_container.tabs[tab_container.active_tab]
	return null

func get_active_website_container() -> Control:
	var active_tab = get_active_tab()
	if active_tab:
		return active_tab.website_container
	return website_container  # fallback to original container

func get_dev_tools_console() -> DevToolsConsole:
	var active_tab = get_active_tab()
	if active_tab:
		return active_tab.get_dev_tools_console()
	return null

func add_to_history(url: String, tab: Tab, add_to_navigation: bool = true):
	if url.is_empty():
		return
	
	var title = "New Tab"
	var icon_url = ""
	
	if tab:
		if add_to_navigation:
			tab.add_to_navigation_history(url)
		
		if tab.button and tab.button.text:
			title = tab.button.text
		
		if tab.has_meta("parsed_icon_url"):
			icon_url = tab.get_meta("parsed_icon_url")
	
	var clean_url = url
	if clean_url.begins_with("gurt://"):
		clean_url = clean_url.substr(7)
	
	BrowserHistory.add_entry(clean_url, title, icon_url)
	update_navigation_buttons()

func _on_back_button_pressed() -> void:
	var active_tab = get_active_tab()
	if active_tab and active_tab.can_go_back():
		var url = active_tab.go_back()
		if not url.is_empty():
			navigate_to_url(url, false)

func _on_forward_button_pressed() -> void:
	var active_tab = get_active_tab()
	if active_tab and active_tab.can_go_forward():
		var url = active_tab.go_forward()
		if not url.is_empty():
			navigate_to_url(url, false)

func _on_refresh_button_pressed() -> void:
	reload_current_page()

func update_navigation_buttons() -> void:
	var active_tab = get_active_tab()
	if active_tab:
		back_button.disabled = not active_tab.can_go_back()
		forward_button.disabled = not active_tab.can_go_forward()
	else:
		back_button.disabled = true
		forward_button.disabled = true

func get_download_confirmation_setting() -> bool:
	return SettingsManager.get_download_confirmation()

func get_search_engine_url() -> String:
	return SettingsManager.get_search_engine_url()

func get_startup_behavior() -> Dictionary:
	return SettingsManager.get_startup_behavior()

func _handle_startup_behavior():
	var args = OS.get_cmdline_args()
	for arg in args:
		if arg.begins_with("gurt://"):
			print("Opening URL from command line: ", arg)
			_on_search_submitted(arg, true)
			return
	
	var startup_behavior = get_startup_behavior()
	
	if startup_behavior.specific_page and not startup_behavior.url.is_empty():
		_on_search_submitted(startup_behavior.url, true)
