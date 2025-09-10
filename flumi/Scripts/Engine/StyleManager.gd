class_name StyleManager
extends RefCounted

static var body_text_color: Color = Color.BLACK

static func parse_size(val):
	if val == null: return null
	if typeof(val) == TYPE_INT or typeof(val) == TYPE_FLOAT:
		return float(val)
	
	# Handle bracketed values like [5px], [2rem], [50%]
	if val.begins_with("[") and val.ends_with("]"):
		var clean_val = val.replace("[", "").replace("]", "")
		if clean_val.ends_with("px"):
			return float(clean_val.replace("px", ""))
		elif clean_val.ends_with("rem"):
			return float(clean_val.replace("rem", "")) * 16.0
		elif clean_val.ends_with("%"):
			return clean_val
		else:
			return float(clean_val)
	
	if val.ends_with("px"):
		return float(val.replace("px", ""))
	if val.ends_with("rem"):
		return float(val.replace("rem", "")) * 16.0
	if val.ends_with("%"):
		return val
	return float(val)

static func apply_element_styles(node: Control, element: HTMLParser.HTMLElement, parser: HTMLParser) -> Control:
	var styles = parser.get_element_styles_with_inheritance(element, "", [])
	var label = null
	var target = null

	if not (node is FlexContainer):
		target = node if node is RichTextLabel else node.get_node_or_null("RichTextLabel")
		label = target
		# Also check for Button nodes
		if not target and node is HTMLButton:
			var button_node = node.get_node_or_null("ButtonNode")
			if button_node:
				target = button_node

	if element.tag_name == "input":
		apply_input_border_styles(node, styles)
	elif element.tag_name == "img":
		apply_image_styles(node, styles)

	# Unified font applying for label and button
	if target and styles.has("font-family") and styles["font-family"] not in ["sans-serif", "serif", "monospace"]:
		var main_node = Engine.get_main_loop().current_scene
		main_node.register_font_dependent_element(target, styles, element, parser)

	var width = null
	var height = null

	if styles.has("width"):
		width = parse_size(styles["width"])
	if styles.has("height"):
		height = parse_size(styles["height"])

	var skip_sizing = SizingUtils.should_skip_sizing(node, element, parser)
	
	if (width != null or height != null) and not skip_sizing:
		if width != null:
			if width is String and width.ends_with("%"):
				if width == "100%":
					node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					node.custom_minimum_size.x = 0
					if node is PanelContainer and node.get_child_count() > 0:
						var vbox = node.get_child(0)
						if vbox is VBoxContainer:
							vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					node.set_meta("size_flags_set_by_style_manager", true)
				else:
					# For other percentages, convert to viewport-relative size
					var percent = float(width.replace("%", "")) / 100.0
					var viewport_width = node.get_viewport().get_visible_rect().size.x if node.get_viewport() else 800
					node.custom_minimum_size.x = viewport_width * percent
					node.set_meta("size_flags_set_by_style_manager", true)
					node.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			else:
				node.custom_minimum_size.x = width
				node.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		
		if height != null:
			if height is String and height.ends_with("%"):
				if height == "100%":
					node.size_flags_vertical = Control.SIZE_EXPAND_FILL
					node.custom_minimum_size.y = 0
				else:
					# For other percentages, convert to viewport-relative size
					var percent = float(height.replace("%", "")) / 100.0
					var viewport_height = node.get_viewport().get_visible_rect().size.y if node.get_viewport() else 600
					node.custom_minimum_size.y = viewport_height * percent
				node.set_meta("size_flags_set_by_style_manager", true)
				node.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			else:
				node.custom_minimum_size.y = height
				node.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	
	apply_element_centering(node, styles)

	if label and label != node:
		label.anchors_preset = Control.PRESET_FULL_RECT

	# Apply z-index
	if styles.has("z-index"):
		node.z_index = styles["z-index"]
	
	# Apply opacity
	if styles.has("opacity"):
		node.modulate.a = styles["opacity"]
	
	if styles.has("display"):
		if styles["display"] == "none":
			node.visible = false
		else:
			node.visible = true
	
	# Apply cursor
	if styles.has("cursor"):
		var cursor_shape = get_cursor_shape_from_type(styles["cursor"])
		node.mouse_default_cursor_shape = cursor_shape
		
		# For text elements, apply cursor and handle mouse events appropriately
		if label:
			label.mouse_default_cursor_shape = cursor_shape
			
			# For non-pointer cursors on RichTextLabel, disable text interaction and let parent handle cursor
			if label is RichTextLabel and cursor_shape != Control.CURSOR_POINTING_HAND:
				label.selection_enabled = false
				label.context_menu_enabled = false
				label.shortcut_keys_enabled = false
				# Let parent container handle the cursor by ignoring mouse on text element
				label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			else:
				# For pointer cursors or non-RichTextLabel, ensure they can receive mouse events
				if label.mouse_filter == Control.MOUSE_FILTER_PASS:
					label.mouse_filter = Control.MOUSE_FILTER_STOP

	# Check for margins first and wrap in MarginContainer if needed
	var has_margin = styles.has("margin") or styles.has("margin-top") or styles.has("margin-right") or styles.has("margin-bottom") or styles.has("margin-left")
	node = handle_margin_wrapper(node, styles, has_margin)
	
	var needs_styling = styles.has("background-color") or styles.has("border-radius") or styles.has("border-width") or styles.has("border-top-width") or styles.has("border-right-width") or styles.has("border-bottom-width") or styles.has("border-left-width") or styles.has("border-color") or styles.has("padding") or styles.has("padding-top") or styles.has("padding-right") or styles.has("padding-bottom") or styles.has("padding-left")
	
	if needs_styling:
		# If node is a MarginContainer wrapper, get the actual content node for styling
		var content_node = node
		if node is MarginContainer and node.has_meta("is_margin_wrapper"):
			if node.get_child_count() > 0:
				content_node = node.get_child(0)
		
		var target_node_for_bg = content_node if content_node is FlexContainer else (label if label else content_node)
		if target_node_for_bg:
			# Clear existing metadata first to ensure clean state
			clear_styling_metadata(target_node_for_bg)
			
			# Set new metadata based on current styles
			set_styling_metadata(target_node_for_bg, styles)
			
			if target_node_for_bg is FlexContainer:
				BackgroundUtils.update_background_panel(target_node_for_bg)
			elif target_node_for_bg is PanelContainer:
				apply_stylebox_to_panel_container(target_node_for_bg, styles)
			else:
				apply_stylebox_to_container_direct(target_node_for_bg, styles)
			
			if target_node_for_bg.has_method("add_background_rect"):
				target_node_for_bg.call_deferred("add_background_rect")
	else:
		var content_node = node
		if node is MarginContainer and node.has_meta("is_margin_wrapper"):
			if node.get_child_count() > 0:
				content_node = node.get_child(0)
		
		var target_node_for_bg = content_node if content_node is FlexContainer else (label if label else content_node)
		if target_node_for_bg:
			clear_styling_metadata(target_node_for_bg)
			
			if target_node_for_bg is FlexContainer:
				BackgroundUtils.update_background_panel(target_node_for_bg)
			elif target_node_for_bg is PanelContainer:
				target_node_for_bg.remove_theme_stylebox_override("panel")
			else:
				target_node_for_bg.remove_theme_stylebox_override("panel")
				target_node_for_bg.remove_theme_stylebox_override("background")

	if label:
		apply_styles_to_label(label, styles, element, parser)

	var transform_target = node
	
	if node is MarginContainer and node.name.begins_with("MarginWrapper_"):
		if node.get_child_count() > 0:
			transform_target = node.get_child(0)
	
	apply_transform_properties(transform_target, styles)


	return node

static func apply_stylebox_to_panel_container(panel_container: PanelContainer, styles: Dictionary) -> void:
	var has_visual_styles = BackgroundUtils.needs_background_wrapper(styles)
	
	if has_visual_styles:
		var style_box = BackgroundUtils.create_stylebox_from_styles(styles, panel_container)
		panel_container.add_theme_stylebox_override("panel", style_box)
	else:
		panel_container.remove_theme_stylebox_override("panel")
		clear_styling_metadata(panel_container)

static func apply_stylebox_to_container_direct(container: Control, styles: Dictionary) -> void:
	var has_visual_styles = BackgroundUtils.needs_background_wrapper(styles)
	
	if has_visual_styles:
		var style_box = BackgroundUtils.create_stylebox_from_styles(styles, container)
		
		container.add_theme_stylebox_override("panel", style_box)
		container.add_theme_stylebox_override("background", style_box)
	else:
		container.remove_theme_stylebox_override("panel")
		container.remove_theme_stylebox_override("background")
		clear_styling_metadata(container)

static func set_styling_metadata(node: Control, styles: Dictionary) -> void:
	# Basic styling properties
	var basic_properties = [
		["background-color", "custom_css_background_color"],
		["border-radius", "custom_css_border_radius"],
		["border-width", "custom_css_border_width"],
		["border-color", "custom_css_border_color"]
	]
	
	for prop in basic_properties:
		if styles.has(prop[0]):
			node.set_meta(prop[1], styles[prop[0]])
	
	# Padding properties
	var padding_properties = [
		["padding", "padding"],
		["padding-top", "padding_top"],
		["padding-right", "padding_right"],
		["padding-bottom", "padding_bottom"],
		["padding-left", "padding_left"]
	]
	
	for prop in padding_properties:
		if styles.has(prop[0]):
			node.set_meta(prop[1], styles[prop[0]])
	
	# Individual border sides
	var border_sides = ["top", "right", "bottom", "left"]
	for side in border_sides:
		var width_key = "border-" + side + "-width"
		if styles.has(width_key):
			node.set_meta("custom_css_" + width_key.replace("-", "_"), styles[width_key])

static func clear_styling_metadata(node: Control) -> void:
	var metadata_keys = [
		"custom_css_background_color",
		"custom_css_border_radius", 
		"custom_css_border_width",
		"custom_css_border_color",
		"padding",
		"padding_top",
		"padding_right", 
		"padding_bottom",
		"padding_left"
	]
	
	for key in metadata_keys:
		if node.has_meta(key):
			node.remove_meta(key)

static func handle_margin_wrapper(node: Control, styles: Dictionary, needs_margin: bool):
	var current_wrapper = null
	
	if node is MarginContainer and node.has_meta("is_margin_wrapper"):
		current_wrapper = node

	elif node.get_parent() and node.get_parent() is MarginContainer:
		var parent = node.get_parent()
		if parent.has_meta("is_margin_wrapper"):
			current_wrapper = parent
	
	if needs_margin:
		if current_wrapper:
			update_margin_wrapper(current_wrapper, styles)
			return current_wrapper
		else:
			return apply_margin_wrapper(node, styles)
	else:
		if current_wrapper:
			if current_wrapper == node:
				if node.get_child_count() > 0:
					var content_node = node.get_child(0)
					return remove_margin_wrapper(current_wrapper, content_node)
			else:
				return remove_margin_wrapper(current_wrapper, node)
		else:
			return node

static func update_margin_wrapper(margin_container: MarginContainer, styles: Dictionary) -> void:
	clear_margin_overrides(margin_container)
	apply_margin_styles_to_container(margin_container, styles)

static func remove_margin_wrapper(margin_container: MarginContainer, original_node: Control) -> Control:
	var original_parent = margin_container.get_parent()
	var node_index = margin_container.get_index()
	
	original_node.size_flags_horizontal = margin_container.size_flags_horizontal
	original_node.size_flags_vertical = margin_container.size_flags_vertical
	
	margin_container.remove_child(original_node)
	
	if original_parent:
		original_parent.remove_child(margin_container)
		original_parent.add_child(original_node)
		original_parent.move_child(original_node, node_index)
	
	margin_container.queue_free()
	
	return original_node

static func apply_margin_wrapper(node: Control, styles: Dictionary) -> Control:
	var margin_container = MarginContainer.new()
	margin_container.name = "MarginWrapper_" + node.name
	margin_container.set_meta("is_margin_wrapper", true)
	
	var needs_fill = false
	
	if node.has_meta("should_fill_horizontal"):
		needs_fill = true
	
	if node.get_child_count() > 0:
		var vbox = node.get_child(0)
		if vbox is VBoxContainer and vbox.get_child_count() > 0:
			var flex_child = vbox.get_child(0)
			if flex_child and flex_child.has_meta("should_fill_horizontal"):
				needs_fill = true
	
	if needs_fill:
		margin_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	
	var has_explicit_width = styles.has("width")
	var has_explicit_height = styles.has("height")
	
	if has_explicit_width and not needs_fill:
			margin_container.size_flags_horizontal = node.size_flags_horizontal
	elif not needs_fill:
		margin_container.size_flags_horizontal = node.size_flags_horizontal
		node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	if has_explicit_height:
		margin_container.size_flags_vertical = node.size_flags_vertical
	else:
		margin_container.size_flags_vertical = node.size_flags_vertical
		node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	
	apply_margin_styles_to_container(margin_container, styles)
	
	# Handle reparenting properly
	var original_parent = node.get_parent()
	if original_parent:
		var node_index = node.get_index()
		original_parent.remove_child(node)
		margin_container.add_child(node)
		original_parent.add_child(margin_container)
		original_parent.move_child(margin_container, node_index)
	else:
		margin_container.add_child(node)
	
	return margin_container

static func clear_margin_overrides(margin_container: MarginContainer) -> void:
	margin_container.remove_theme_constant_override("margin_top")
	margin_container.remove_theme_constant_override("margin_right")
	margin_container.remove_theme_constant_override("margin_bottom")
	margin_container.remove_theme_constant_override("margin_left")

static func apply_margin_styles_to_container(margin_container: MarginContainer, styles: Dictionary) -> void:
	# Apply general margin first
	if styles.has("margin"):
		var general_margin = parse_size(styles["margin"])
		if general_margin != null:
			var margin_sides = ["margin_top", "margin_right", "margin_bottom", "margin_left"]
			for side in margin_sides:
				margin_container.add_theme_constant_override(side, general_margin)
	
	# Apply individual margin overrides
	var margin_mappings = [
		["margin-top", "margin_top"],
		["margin-right", "margin_right"],
		["margin-bottom", "margin_bottom"],
		["margin-left", "margin_left"]
	]
	
	for mapping in margin_mappings:
		var style_key = mapping[0]
		var theme_key = mapping[1]
		if styles.has(style_key):
			var margin_val = parse_size(styles[style_key])
			if margin_val != null:
				margin_container.add_theme_constant_override(theme_key, margin_val)

static func apply_styles_to_label(label: Control, styles: Dictionary, element: HTMLParser.HTMLElement, parser, text_override: String = "", is_refresh: bool = false) -> void:
	if label is Button:
		apply_font_to_button(label, styles)
		return
	
	if not label is RichTextLabel:
		return
	
	if not is_refresh and styles.has("font-family") and styles["font-family"] not in ["sans-serif", "serif", "monospace"]:
		var main_node = Engine.get_main_loop().current_scene
		main_node.register_font_dependent_element(label, styles, element, parser)
	
	var text = text_override if text_override != "" else (element.get_preserved_text() if element.tag_name == "pre" else element.get_bbcode_formatted_text(parser))

	var font_size = 24  # default

	if styles.has("font-family"):
		var font_family = styles["font-family"]
		var font_resource = FontManager.get_font(font_family)
			
		if font_family not in ["sans-serif", "serif", "monospace"]:
			if FontManager.loaded_fonts.has(font_family) and font_resource:
				apply_font_to_label(label, font_resource, styles)
			else:
				var fallback_font = FontManager.get_font("sans-serif")
				apply_font_to_label(label, fallback_font, styles)
		else:
			if font_resource:
				apply_font_to_label(label, font_resource, styles)
	else:
		# No custom font family, but check if we need to apply font weight
		if styles.has("font-thin") or styles.has("font-extralight") or styles.has("font-light") or styles.has("font-normal") or styles.has("font-medium") or styles.has("font-semibold") or styles.has("font-extrabold") or styles.has("font-black"):
			var default_font = FontManager.get_font("sans-serif")
			apply_font_to_label(label, default_font, styles)
	
	# Apply font size
	if styles.has("font-size"):
		font_size = int(styles["font-size"])
	
	label.add_theme_font_size_override("normal_font_size", font_size)
	label.add_theme_font_size_override("bold_font_size", font_size)
	label.add_theme_font_size_override("italics_font_size", font_size)
	label.add_theme_font_size_override("bold_italics_font_size", font_size)
	label.add_theme_font_size_override("mono_font_size", font_size)
		
	var has_existing_bbcode = text.contains("[url=") or text.contains("[color=")
	
	# Apply color
	var color_tag = ""
	if not has_existing_bbcode and styles.has("color"):
		var color = styles["color"] as Color
		if color == Color.BLACK and StyleManager.body_text_color != Color.BLACK:
			color = StyleManager.body_text_color
		color_tag = "[color=#%s]" % color.to_html(false)
	elif not has_existing_bbcode and StyleManager.body_text_color != Color.BLACK:
		color_tag = "[color=#%s]" % StyleManager.body_text_color.to_html(false)

	# Apply text styling (but not for text with existing BBCode)
	var bold_open = ""
	var bold_close = ""
	if not has_existing_bbcode and styles.has("font-bold") and styles["font-bold"]:
		bold_open = "[b]"
		bold_close = "[/b]"
	
	var italic_open = ""
	var italic_close = ""
	if not has_existing_bbcode and styles.has("font-italic") and styles["font-italic"]:
		italic_open = "[i]"
		italic_close = "[/i]"
	
	var underline_open = ""
	var underline_close = ""
	if not has_existing_bbcode and styles.has("underline") and styles["underline"]:
		underline_open = "[u]"
		underline_close = "[/u]"
	# Apply monospace font
	var mono_open = ""
	var mono_close = ""
	if styles.has("font-mono") and styles["font-mono"]:
		# If font-family is already monospace, just use BBCode for styling
		if not (styles.has("font-family") and styles["font-family"] == "monospace"):
			mono_open = "[code]"
			mono_close = "[/code]"
	if styles.has("text-align"):
		match styles["text-align"]:
			"left":
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			"center":
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			"right":
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			"justify":
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_FILL
	# Construct final text
	
	var styled_text = "%s%s%s%s%s%s%s%s%s%s%s" % [
			color_tag,
			bold_open,
			italic_open,
			underline_open,
			mono_open,
			text,
			mono_close,
			underline_close,
			italic_close,
			bold_close,
			"[/color]" if color_tag.length() > 0 else "",
	]
		
	label.text = styled_text

static func apply_body_styles(body: HTMLParser.HTMLElement, parser: HTMLParser, website_container: Control, website_background: Control) -> void:
	var styles = parser.get_element_styles_with_inheritance(body, "", [])
	
	# Apply background color
	if styles.has("background-color"):
		var style_box = StyleBoxFlat.new()
		style_box.bg_color = styles["background-color"] as Color
		website_background.add_theme_stylebox_override("panel", style_box)
	
	if styles.has("color"):
		StyleManager.body_text_color = styles["color"]
	# Apply padding
	var has_padding = styles.has("padding") or styles.has("padding-top") or styles.has("padding-right") or styles.has("padding-bottom") or styles.has("padding-left")
	
	if has_padding:
		var margin_container = MarginContainer.new()
		margin_container.name = "BodyMarginContainer"
		margin_container.size_flags_horizontal = website_container.size_flags_horizontal
		margin_container.size_flags_vertical = website_container.size_flags_vertical

		# ScrollContainer
		# |__ BodyMarginContainer
		#     |__ WebsiteContainer
		var original_parent = website_container.get_parent()
		var container_index = website_container.get_index()

		original_parent.remove_child(website_container)
		original_parent.add_child(margin_container)
		original_parent.move_child(margin_container, container_index)
		margin_container.add_child(website_container)
		
		var padding_val = parse_size(styles["padding"] if styles.has("padding") else 0)

		margin_container.add_theme_constant_override("margin_left", padding_val)
		margin_container.add_theme_constant_override("margin_right", padding_val)
		margin_container.add_theme_constant_override("margin_top", padding_val)
		margin_container.add_theme_constant_override("margin_bottom", padding_val)
		
		# Apply individual padding values using our helper function
		var padding_mappings = [
			["padding-top", "margin_top"],
			["padding-right", "margin_right"], 
			["padding-bottom", "margin_bottom"],
			["padding-left", "margin_left"]
		]
		
		for mapping in padding_mappings:
			var style_key = mapping[0]
			var margin_key = mapping[1]
			if styles.has(style_key):
				var margin_val = parse_size(styles[style_key])
				if margin_val != null:
					margin_container.add_theme_constant_override(margin_key, margin_val)

static func parse_radius(radius_str: String) -> int:
	return SizeUtils.parse_radius(radius_str)

static func apply_font_to_label(label: RichTextLabel, font_resource: Font, styles: Dictionary = {}) -> void:
	if font_resource is FontFile:
		label.add_theme_font_override("normal_font", font_resource)
		label.add_theme_font_override("bold_font", font_resource)
		label.add_theme_font_override("italics_font", font_resource)
	
	elif font_resource is SystemFont:
		var font_weight = 400
		if styles.has("font-thin"):
			font_weight = 100
		elif styles.has("font-extralight"):
			font_weight = 200
		elif styles.has("font-light"):
			font_weight = 300
		elif styles.has("font-normal"):
			font_weight = 400
		elif styles.has("font-medium"):
			font_weight = 500
		elif styles.has("font-semibold"):
			font_weight = 600
		elif styles.has("font-bold"):
			font_weight = 700
		elif styles.has("font-extrabold"):
			font_weight = 800
		elif styles.has("font-black"):
			font_weight = 900
		
		var normal_font = SystemFont.new()
		normal_font.font_names = font_resource.font_names
		normal_font.font_weight = font_weight
		label.add_theme_font_override("normal_font", normal_font)
		
		# Create bold variant
		var bold_font = SystemFont.new()
		bold_font.font_names = font_resource.font_names
		bold_font.font_weight = 700
		label.add_theme_font_override("bold_font", bold_font)
		
		# Create italic variant
		var italic_font = SystemFont.new()
		italic_font.font_names = font_resource.font_names
		italic_font.font_italic = true
		italic_font.font_weight = font_weight
		label.add_theme_font_override("italics_font", italic_font)
		
	else:
		label.add_theme_font_override("normal_font", font_resource)
		label.add_theme_font_override("bold_font", font_resource)
		label.add_theme_font_override("italics_font", font_resource)
	
	# Handle bold_italics_font
	if font_resource is FontFile:
		label.add_theme_font_override("bold_italics_font", font_resource)
	elif font_resource is SystemFont:
		var bold_italic_font = SystemFont.new()
		bold_italic_font.font_names = font_resource.font_names
		bold_italic_font.font_weight = 700
		bold_italic_font.font_italic = true
		label.add_theme_font_override("bold_italics_font", bold_italic_font)

static func apply_font_to_button(button: Button, styles: Dictionary) -> void:
	if styles.has("font-family"):
		var font_family = styles["font-family"]
		var font_resource = FontManager.get_font(font_family)
		
		# Set fallback first for FOUT prevention
		if font_family not in ["sans-serif", "serif", "monospace"]:
			if not FontManager.loaded_fonts.has(font_family):
				var fallback_font = FontManager.get_font("sans-serif")
				button.add_theme_font_override("font", fallback_font)
		
		if font_resource:
			button.add_theme_font_override("font", font_resource)
	
	# Apply font size
	if styles.has("font-size"):
		var font_size = int(styles["font-size"])
		button.add_theme_font_size_override("font_size", font_size)

static func get_cursor_shape_from_type(cursor_type: String) -> Control.CursorShape:
	match cursor_type:
		"pointer", "hand":
			return Control.CURSOR_POINTING_HAND
		"text":
			return Control.CURSOR_IBEAM
		"crosshair":
			return Control.CURSOR_CROSS
		"move":
			return Control.CURSOR_MOVE
		"not-allowed", "forbidden":
			return Control.CURSOR_FORBIDDEN
		"wait":
			return Control.CURSOR_WAIT
		"help":
			return Control.CURSOR_HELP
		"grab":
			return Control.CURSOR_DRAG
		"grabbing":
			return Control.CURSOR_CAN_DROP
		"e-resize", "ew-resize":
			return Control.CURSOR_HSIZE
		"n-resize", "ns-resize":
			return Control.CURSOR_VSIZE
		"ne-resize":
			return Control.CURSOR_BDIAGSIZE
		"nw-resize":
			return Control.CURSOR_FDIAGSIZE
		"se-resize":
			return Control.CURSOR_FDIAGSIZE
		"sw-resize":
			return Control.CURSOR_BDIAGSIZE
		"default", "auto", _:
			return Control.CURSOR_ARROW

static func apply_input_border_styles(input_node: Control, styles: Dictionary) -> void:
	if not BackgroundUtils.needs_background_wrapper(styles):
		return
	
	# Find the appropriate input control to style
	var styleable_controls = []
	
	# Get all potential input controls that support StyleBox
	var line_edit = input_node.get_node_or_null("LineEdit")
	var spinbox = input_node.get_node_or_null("SpinBox")
	var file_container = input_node.get_node_or_null("FileContainer")
	
	if line_edit: styleable_controls.append(line_edit)
	if spinbox: styleable_controls.append(spinbox)
	if file_container:
		var file_button = file_container.get_node_or_null("FileButton")
		if file_button: styleable_controls.append(file_button)
	
	# Apply styles using BackgroundUtils
	for control in styleable_controls:
		var style_box = BackgroundUtils.create_stylebox_from_styles(styles)
		
		# Set appropriate content margins for inputs if not specified
		if not styles.has("padding") and not styles.has("padding-left"):
			style_box.content_margin_left = 5.0
		if not styles.has("padding") and not styles.has("padding-right"):
			style_box.content_margin_right = 5.0
		if not styles.has("padding") and not styles.has("padding-top"):
			style_box.content_margin_top = 2.0
		if not styles.has("padding") and not styles.has("padding-bottom"):
			style_box.content_margin_bottom = 2.0
		
		# Apply the style to the appropriate states
		if control is LineEdit:
			control.add_theme_stylebox_override("normal", style_box)
			control.add_theme_stylebox_override("focus", style_box)
		elif control is SpinBox:
			control.add_theme_stylebox_override("normal", style_box)
			control.add_theme_stylebox_override("focus", style_box)
		elif control is Button:
			control.add_theme_stylebox_override("normal", style_box)

static func apply_image_styles(image_node: Control, styles: Dictionary) -> void:
	if not image_node is TextureRect:
		return
	
	var texture_rect = image_node as TextureRect
	
	if styles.has("object-fit"):
		var object_fit = styles["object-fit"]
		match object_fit:
			"none":
				texture_rect.stretch_mode = TextureRect.STRETCH_KEEP
			"fill":
				texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
			"contain":
				texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
			"cover":
				texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

static func apply_transform_properties(node: Control, styles: Dictionary) -> void:
	if node is FlexContainer:
		var has_panel_children = false
		for child in node.get_children():
			if child is PanelContainer:
				has_panel_children = true
				break
		
		if has_panel_children:
			apply_transform_properties_direct(node, styles)
		else:
			for child in node.get_children():
				if child is RichTextLabel or child is Control:
					apply_transform_properties_direct(child, styles)
					return
			apply_transform_properties_direct(node, styles)
	else:
		apply_transform_properties_direct(node, styles)

static func apply_transform_properties_direct(node: Control, styles: Dictionary) -> void:
	var scale_x = styles.get("scale-x", 1.0)
	var scale_y = styles.get("scale-y", 1.0)
	var rotation = styles.get("rotate", 0.0)
	
	var has_transform = scale_x != 1.0 or scale_y != 1.0 or rotation != 0.0
	var duration = get_transition_duration(styles)
	
	if has_transform:
		node.set_meta("css_transform_applied", true)
		
		# Set pivot point to center
		node.pivot_offset = node.size / 2
		
		if duration > 0:
			animate_transform(node, Vector2(scale_x, scale_y), rotation, duration)
		else:
			node.scale = Vector2(scale_x, scale_y)
			node.rotation = rotation
			await_and_restore_transform(node, Vector2(scale_x, scale_y), rotation)
	else:
		if duration > 0:
			animate_transform(node, Vector2.ONE, 0.0, duration)
		else:
			node.scale = Vector2.ONE
			node.rotation = 0.0
		if node.has_meta("css_transform_applied"):
			node.remove_meta("css_transform_applied")

static func get_transition_duration(styles: Dictionary) -> float:
	if styles.has("transition-transform"):
		return parse_transition_duration(styles["transition-transform"])
	elif styles.has("transition"):
		return parse_transition_duration(styles["transition"])
	return 0.0

static func parse_transition_duration(value: String) -> float:
	if value.ends_with("ms"):
		return float(value.replace("ms", "")) / 1000.0
	elif value.ends_with("s"):
		return float(value.replace("s", ""))
	return float(value) if value.is_valid_float() else 0.0

static func animate_transform(node: Control, target_scale: Vector2, target_rotation: float, duration: float) -> void:
	var tween = node.create_tween()
	tween.set_parallel(true)
	tween.tween_property(node, "scale", target_scale, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(node, "rotation", target_rotation, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

static func await_and_restore_transform(node: Control, target_scale: Vector2, target_rotation: float) -> void:
	var tree = Engine.get_main_loop()
	
	await tree.process_frame
	node.scale = target_scale
	node.rotation = target_rotation
	node.pivot_offset = node.size / 2

static func apply_flexcontainer_centering(node: Control, styles: Dictionary) -> void:
	if not node is FlexContainer:
		return
		
	var should_center_h = styles.has("mx-auto") or styles.has("justify-self-center")
	var should_center_v = styles.has("my-auto") or styles.has("align-self-center")
	
	if should_center_h and not node.has_meta("size_flags_horizontal_set"):
		node.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	
	if should_center_v and not node.has_meta("size_flags_vertical_set"):
		node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	if should_center_h or should_center_v:
		node.set_meta("size_flags_set_by_style_manager", true)

static func apply_element_centering(node: Control, styles: Dictionary) -> void:
	var should_center_h = styles.has("mx-auto") or styles.has("justify-self-center")
	var should_center_v = styles.has("my-auto") or styles.has("align-self-center")
	
	# For FlexContainers, use the existing logic with metadata checks
	if node is FlexContainer:
		if should_center_h and not node.has_meta("size_flags_horizontal_set"):
			node.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		
		if should_center_v and not node.has_meta("size_flags_vertical_set"):
			node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		
		if should_center_h or should_center_v:
			node.set_meta("size_flags_set_by_style_manager", true)
	else:
		# For other controls, apply centering more directly
		if should_center_h:
			# Only apply if no explicit width was set, or if explicit sizing allows centering
			var has_explicit_width = styles.has("width")
			if not has_explicit_width or not node.has_meta("size_flags_horizontal_set"):
				node.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		
		if should_center_v:
			# Only apply if no explicit height was set, or if explicit sizing allows centering
			var has_explicit_height = styles.has("height")
			if not has_explicit_height or not node.has_meta("size_flags_vertical_set"):
				node.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		
		if should_center_h or should_center_v:
			node.set_meta("size_flags_set_by_style_manager", true)
