class_name HTMLP
extends HBoxContainer

var _element: HTMLParser.HTMLElement
var _parser: HTMLParser

const BROWSER_THEME = preload("res://Scenes/Styles/BrowserText.tres")
const AUTO_RESIZE_VISIBILITY_META := "auto_resize_visibility_watch"

func init(element, parser: HTMLParser) -> void:
	_element = element
	_parser = parser
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	
	mouse_filter = Control.MOUSE_FILTER_PASS
	
	var element_id = element.get_attribute("id")
	if element_id.is_empty():
		var unique_id = "elem_" + str(Time.get_ticks_msec()) + "_" + str(randi())
		element.set_attribute("id", unique_id)
		element_id = unique_id
	parser.register_dom_node(element, self)

	if get_child_count() > 0:
		return
	
	var element_text = element.text_content
	var child_texts = []
	
	for child in element.children:
		child_texts.append(child.text_content)
	
	var parent_only_text = element_text
	for child_text in child_texts:
		parent_only_text = parent_only_text.replace(child_text, "")
	
	if not parent_only_text.strip_edges().is_empty():
		create_styled_label(parent_only_text.strip_edges(), element, parser)
	
	for child in element.children:
		var child_label = create_styled_label(child.get_bbcode_formatted_text(parser), element, parser)
		
		if contains_hyperlink(child):
			child_label.meta_clicked.connect(_on_meta_clicked)

func create_styled_label(text: String, element, parser: HTMLParser) -> RichTextLabel:
	var label = RichTextLabel.new()
	
	label.theme = BROWSER_THEME
	label.focus_mode = Control.FOCUS_ALL
	label.add_theme_color_override("default_color", Color.BLACK)
	label.bbcode_enabled = true
	label.fit_content = true
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.selection_enabled = true
	
	var parent_cursor_shape = Control.CURSOR_IBEAM
	if element.parent:
		var parent_styles = parser.get_element_styles_with_inheritance(element.parent, "", [])
		if parent_styles.has("cursor"):
			parent_cursor_shape = StyleManager.get_cursor_shape_from_type(parent_styles["cursor"])
	
	label.mouse_default_cursor_shape = parent_cursor_shape
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	add_child(label)
	
	
	var styles = parser.get_element_styles_with_inheritance(element, "", [])
	StyleManager.apply_styles_to_label(label, styles, element, parser, text)
	
	call_deferred("_apply_auto_resize_to_label", label)
	return label

func _apply_auto_resize_to_label(label: RichTextLabel):
	if not is_instance_valid(label) or not is_instance_valid(self):
		return
	
	if not label.is_inside_tree():
		await label.tree_entered
	
	if not is_instance_valid(label) or not is_instance_valid(self):
		return

	if not label.is_visible_in_tree():
		if not label.has_meta(AUTO_RESIZE_VISIBILITY_META):
			label.set_meta(AUTO_RESIZE_VISIBILITY_META, true)
			label.visibility_changed.connect(_on_label_visibility_changed.bind(label), Object.CONNECT_ONE_SHOT)
		return

	if label.has_meta(AUTO_RESIZE_VISIBILITY_META):
		label.remove_meta(AUTO_RESIZE_VISIBILITY_META)
	
	var min_width = 20
	var max_width = 800
	
	label.fit_content = true
	
	var original_autowrap = label.autowrap_mode
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	
	await get_tree().process_frame
	
	if not is_instance_valid(label) or not is_instance_valid(self):
		return
	
	var content_width = 0.0
	if label.has_method("get_content_width"):
		content_width = label.get_content_width()
	var natural_width = max(content_width, label.size.x)
	if natural_width <= 0.0:
		natural_width = label.get_minimum_size().x
	
	var desired_width = clamp(natural_width, min_width, max_width)
	
	label.autowrap_mode = original_autowrap
	
	await get_tree().process_frame
	
	if not is_instance_valid(label) or not is_instance_valid(self):
		return
	
	label.custom_minimum_size = Vector2(desired_width, 0)
	
	label.queue_redraw()

func _on_label_visibility_changed(label: RichTextLabel) -> void:
	if not is_instance_valid(self) or not is_instance_valid(label):
		return
	
	if label.is_visible_in_tree():
		call_deferred("_apply_auto_resize_to_label", label)
	else:
		label.visibility_changed.connect(_on_label_visibility_changed.bind(label), Object.CONNECT_ONE_SHOT)

func contains_hyperlink(element: HTMLParser.HTMLElement) -> bool:
	if element.tag_name == "a":
		return true
	
	for child in element.children:
		if contains_hyperlink(child):
			return true
	
	return false

func _on_meta_clicked(meta: Variant) -> void:
	var current = get_parent()
	while current:
		if current.has_method("handle_link_click"):
			current.handle_link_click(meta)
			break
		current = current.get_parent()

func get_text() -> String:
	var text_parts = []
	for child in get_children():
		if child is RichTextLabel:
			text_parts.append(child.get_parsed_text())
	return " ".join(text_parts)

func set_text(new_text: String) -> void:
	# Clear existing children immediately
	for child in get_children():
		remove_child(child)
		child.queue_free()
	
	if _element:
		_element.text_content = new_text
	
	if _element and _parser:
		create_styled_label(new_text, _element, _parser)
	else:
		create_label(new_text)

func create_label(text: String) -> RichTextLabel:
	var label = RichTextLabel.new()
	
	label.theme = BROWSER_THEME
	label.focus_mode = Control.FOCUS_ALL
	label.add_theme_color_override("default_color", Color.BLACK)
	label.bbcode_enabled = true
	label.fit_content = true
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.selection_enabled = true
	
	var parent_cursor_shape = Control.CURSOR_IBEAM
	if _element and _parser and _element.parent:
		var parent_styles = _parser.get_element_styles_with_inheritance(_element.parent, "", [])
		if parent_styles.has("cursor"):
			parent_cursor_shape = StyleManager.get_cursor_shape_from_type(parent_styles["cursor"])
	
	label.mouse_default_cursor_shape = parent_cursor_shape
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	
	add_child(label)
	
	
	call_deferred("_apply_auto_resize_to_label", label)
	return label
