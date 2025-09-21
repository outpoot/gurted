class_name BackgroundUtils
extends RefCounted

static func create_stylebox_from_styles(styles: Dictionary = {}, container: Control = null) -> StyleBoxFlat:
	# Add null checks and error handling
	if not styles:
		print("ERROR: BackgroundUtils.create_stylebox_from_styles() - styles is null or empty")
		return StyleBoxFlat.new()

	if container and not is_instance_valid(container):
		print("ERROR: BackgroundUtils.create_stylebox_from_styles() - container is not valid")
		container = null

	print("DEBUG: BackgroundUtils.create_stylebox_from_styles() - Creating stylebox for container: ", container.name if container else "null")

	var style_box = StyleBoxFlat.new()

	# Background color
	var bg_color = null
	if styles.has("background-color"):
		bg_color = styles["background-color"]
	elif container and container.has_meta("custom_css_background_color"):
		bg_color = container.get_meta("custom_css_background_color")
	
	if bg_color:
		style_box.bg_color = bg_color
	else:
		style_box.bg_color = Color.TRANSPARENT
	
	# Border radius
	var border_radius = null
	if styles.has("border-radius"):
		border_radius = styles["border-radius"]
	elif container and container.has_meta("custom_css_border_radius"):
		border_radius = container.get_meta("custom_css_border_radius")
	
	if border_radius:
		var radius = StyleManager.parse_radius(border_radius)
		style_box.corner_radius_top_left = radius
		style_box.corner_radius_top_right = radius
		style_box.corner_radius_bottom_left = radius
		style_box.corner_radius_bottom_right = radius
		
	# Border properties
	var has_border = false

	style_box.border_width_top = 0
	style_box.border_width_right = 0
	style_box.border_width_bottom = 0
	style_box.border_width_left = 0

	var general_border_width = null
	if styles.has("border-width"):
		general_border_width = styles["border-width"]
	elif container and container.has_meta("custom_css_border_width"):
		general_border_width = container.get_meta("custom_css_border_width")

	if general_border_width:
		has_border = true
		var parsed_width = StyleManager.parse_size(general_border_width)
		style_box.border_width_top = parsed_width
		style_box.border_width_right = parsed_width
		style_box.border_width_bottom = parsed_width
		style_box.border_width_left = parsed_width
		
	var individual_border_keys = [
		["border-top-width", "border_width_top"],
		["border-right-width", "border_width_right"],
		["border-bottom-width", "border_width_bottom"],
		["border-left-width", "border_width_left"]
	]

	for pair in individual_border_keys:
		var style_key = pair[0]
		var property_name = pair[1]
		var width = null
		var meta_key = "custom_css_" + style_key.replace("-", "_")

		if styles.has(style_key):
			width = styles[style_key]
		elif container and container.has_meta(meta_key):
			width = container.get_meta(meta_key)

		if width:
			has_border = true
			var parsed_width = StyleManager.parse_size(width)
			style_box.set(property_name, parsed_width)
	
	var border_color = Color.BLACK
	var has_border_color = false
	if styles.has("border-color"):
		border_color = styles["border-color"]
		has_border_color = true
	elif container and container.has_meta("custom_css_border_color"):
		border_color = container.get_meta("custom_css_border_color")
		has_border_color = true

	# If we have a border color but no width set, default to 1px
	if has_border_color and not has_border:
		has_border = true
		style_box.border_width_top = 1
		style_box.border_width_right = 1
		style_box.border_width_bottom = 1
		style_box.border_width_left = 1

	if has_border:
		style_box.border_color = border_color
	
	# Padding as content margins
	var has_padding = false
	if styles.size() > 0:
		has_padding = styles.has("padding") or styles.has("padding-top") or styles.has("padding-right") or styles.has("padding-bottom") or styles.has("padding-left")
	elif container:
		has_padding = container.has_meta("padding") or container.has_meta("padding_top") or container.has_meta("padding_right") or container.has_meta("padding_bottom") or container.has_meta("padding_left")

	if has_padding:
		# General padding
		var padding_val = null
		if styles.has("padding"):
			padding_val = StyleManager.parse_size(styles["padding"])
		elif container and container.has_meta("padding"):
			padding_val = StyleManager.parse_size(container.get_meta("padding"))

		if padding_val:
			style_box.content_margin_left = padding_val
			style_box.content_margin_right = padding_val
			style_box.content_margin_top = padding_val
			style_box.content_margin_bottom = padding_val

		# Individual padding values override general padding
		var padding_mappings = [["padding-left", "content_margin_left"], ["padding-right", "content_margin_right"], ["padding-top", "content_margin_top"], ["padding-bottom", "content_margin_bottom"]]

		for mapping in padding_mappings:
			var style_key = mapping[0]
			var property_key = mapping[1]
			var val = get_style_or_meta_value(styles, container, style_key)

			if val != null:
				style_box.set(property_key, val)
	
	print("DEBUG: BackgroundUtils.create_stylebox_from_styles() - Completed for container: ", container.name if container else "null")
	return style_box

# for AutoSizingFlexContainer
static func update_background_panel(container: Control) -> void:
	var needs_background = container.has_meta("custom_css_background_color") or container.has_meta("custom_css_border_radius")
	var needs_padding = container.has_meta("padding") or container.has_meta("padding_top") or container.has_meta("padding_right") or container.has_meta("padding_bottom") or container.has_meta("padding_left")
	var background_panel = get_background_panel(container)
	
	if needs_background or needs_padding:
		if not background_panel:
			background_panel = Panel.new()
			background_panel.name = "BackgroundPanel"
			background_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			background_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			container.add_child(background_panel)
			container.move_child(background_panel, 0) # first child
		
		var style_box = create_stylebox_from_styles({}, container)
		background_panel.add_theme_stylebox_override("panel", style_box)
	
	elif background_panel:
		background_panel.queue_free()

# Helper methods for AutoSizingFlexContainer
static func get_background_panel(container: Control) -> Panel:
	for child in container.get_children():
		if child.name == "BackgroundPanel" and child is Panel:
			return child
	return null

static func is_background_panel(node: Node) -> bool:
	return node.name == "BackgroundPanel" and node is Panel

# for any other tag
static func create_panel_container_with_background(styles: Dictionary, hover_styles: Dictionary = {}) -> PanelContainer:
	var panel_container = PanelContainer.new()
	panel_container.name = "Div"
	
	var vbox = VBoxContainer.new()
	vbox.name = "VBoxContainer"
	# Allow mouse events to pass through to the parent PanelContainer
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_container.add_child(vbox)
	
	var style_box = create_stylebox_from_styles(styles)
	panel_container.add_theme_stylebox_override("panel", style_box)
	
	# Add hover support if hover styles exist
	if hover_styles.size() > 0:
		setup_panel_hover_support(panel_container, styles, hover_styles)
	
	return panel_container

static func setup_panel_hover_support(panel: PanelContainer, normal_styles: Dictionary, hover_styles: Dictionary):
	var normal_stylebox = create_stylebox_from_styles(normal_styles)
	
	# Merge normal styles with hover styles for the hover state
	var merged_hover_styles = normal_styles.duplicate()
	for key in hover_styles:
		merged_hover_styles[key] = hover_styles[key]
	var hover_stylebox = create_stylebox_from_styles(merged_hover_styles)
	
	# Store references for the hover handlers
	panel.set_meta("normal_stylebox", normal_stylebox)
	panel.set_meta("hover_stylebox", hover_stylebox)
	panel.set_meta("normal_styles", normal_styles.duplicate(true))
	panel.set_meta("hover_styles", merged_hover_styles.duplicate(true))
	panel.set_meta("is_hovering", false)
	
	# Connect mouse events
	panel.mouse_entered.connect(_on_panel_mouse_entered.bind(panel))
	panel.mouse_exited.connect(_on_panel_mouse_exited_with_delay.bind(panel))
	
	_setup_child_hover_listeners(panel)

static func _setup_child_hover_listeners(panel: PanelContainer):
	for child in panel.get_children():
		_connect_child_hover_events(child, panel)
	
	panel.child_entered_tree.connect(_on_child_added.bind(panel))

static func _connect_child_hover_events(child: Node, panel: PanelContainer):
	if child is Control:
		# Only connect if not already connected
		if not child.mouse_entered.is_connected(_on_child_mouse_entered.bind(panel)):
			child.mouse_entered.connect(_on_child_mouse_entered.bind(panel))
		if not child.mouse_exited.is_connected(_on_child_mouse_exited.bind(panel)):
			child.mouse_exited.connect(_on_child_mouse_exited.bind(panel))
	
	for grandchild in child.get_children():
		_connect_child_hover_events(grandchild, panel)

static func _on_child_added(child: Node, panel: PanelContainer):
	_connect_child_hover_events(child, panel)

static func _on_child_mouse_entered(panel: PanelContainer):
	_on_panel_mouse_entered(panel)

static func _on_child_mouse_exited(panel: PanelContainer):
	_create_panel_check_timer(panel)

static func _on_panel_mouse_entered(panel: PanelContainer):
	panel.set_meta("is_hovering", true)
	if panel.has_meta("hover_stylebox"):
		var hover_stylebox = panel.get_meta("hover_stylebox")
		panel.add_theme_stylebox_override("panel", hover_stylebox)
	
	if panel.has_meta("hover_styles"):
		var hover_styles = panel.get_meta("hover_styles")
		var transform_target = find_transform_target_for_panel(panel)
		StyleManager.apply_transform_properties_direct(transform_target, hover_styles)

static func _on_panel_mouse_exited_with_delay(panel: PanelContainer):
	_create_panel_check_timer(panel)

static func _create_panel_check_timer(panel: PanelContainer):
	if not is_instance_valid(panel):
		return
	var timer = panel.get_tree().create_timer(0.01)
	var panel_ref = weakref(panel)
	timer.timeout.connect(func(): _check_panel_hover_safe(panel_ref))

static func _check_panel_hover_safe(panel_ref: WeakRef):
	var panel = panel_ref.get_ref()
	if panel:
		_check_panel_hover(panel)

static func _check_panel_hover(panel: PanelContainer):
	if not panel or not is_instance_valid(panel):
		return
	
	var mouse_pos = panel.get_global_mouse_position()
	var panel_rect = panel.get_global_rect()
	var is_mouse_over = panel_rect.has_point(mouse_pos)
	
	if not is_mouse_over and panel.get_meta("is_hovering", false):
		panel.set_meta("is_hovering", false)
		if panel.has_meta("normal_stylebox"):
			var normal_stylebox = panel.get_meta("normal_stylebox")
			panel.add_theme_stylebox_override("panel", normal_stylebox)
		
		if panel.has_meta("normal_styles"):
			var normal_styles = panel.get_meta("normal_styles")
			var transform_target = find_transform_target_for_panel(panel)
			StyleManager.apply_transform_properties_direct(transform_target, normal_styles)

static func find_transform_target_for_panel(panel: PanelContainer) -> Control:
	var parent = panel.get_parent()
	if parent and parent is FlexContainer:
		return parent
	
	return panel

static func needs_background_wrapper(styles: Dictionary) -> bool:
	return styles.has("background-color") or styles.has("border-radius") or styles.has("padding") or styles.has("padding-top") or styles.has("padding-right") or styles.has("padding-bottom") or styles.has("padding-left") or styles.has("border-width") or styles.has("border-top-width") or styles.has("border-right-width") or styles.has("border-bottom-width") or styles.has("border-left-width") or styles.has("border-color") or styles.has("border-style") or styles.has("border-top-color") or styles.has("border-right-color") or styles.has("border-bottom-color") or styles.has("border-left-color")

static func get_style_or_meta_value(styles: Dictionary, container: Control, key: String):
	if styles.has(key):
		return StyleManager.parse_size(styles[key])
	elif container and container.has_meta(key):
		return StyleManager.parse_size(container.get_meta(key))
	return null
