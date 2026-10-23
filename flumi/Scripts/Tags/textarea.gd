extends Control

const BROWSER_TEXT = preload("res://Scenes/Styles/BrowserText.tres")

func init(element: HTMLParser.HTMLElement, parser: HTMLParser) -> void:
	var text_edit: TextEdit = $TextEdit
	
	var placeholder = element.get_attribute("placeholder")
	var value = element.get_attribute("value")
	var rows = element.get_attribute("rows")
	var cols = element.get_attribute("cols")
	var maxlength = element.get_attribute("maxlength")
	
	# Set placeholder text
	text_edit.placeholder_text = placeholder
	
	# Set initial value
	if value.length() > 0:
		text_edit.text = value
	elif element.text_content.length() > 0:
		text_edit.text = element.text_content
	
	# We assume to fit $rows amount of new lines
	var line_height = text_edit.get_theme_default_font().get_height(text_edit.get_theme_default_font_size())
	# We assume the biggest letter typed is "M" (77), and optimize to fit $cols amount of "M"
	var char_width = text_edit.get_theme_default_font().get_char_size(77, text_edit.get_theme_default_font_size()).x
	
	var min_height = line_height * (rows.to_int() if rows.length() > 0 else 4) + 26  # padding
	var min_width = char_width * (cols.to_int() if cols.length() > 0 else 50) + 16  # padding

	text_edit.custom_minimum_size = Vector2(min_width, min_height)
	text_edit.size = Vector2(min_width, min_height)
	text_edit.min_size = Vector2(min_width, min_height)
	
	# Sync Control size with TextEdit
	custom_minimum_size = text_edit.custom_minimum_size
	
	if element.has_attribute("disabled"):
		text_edit.editable = false
		var stylebox = StyleBoxFlat.new()
		stylebox.bg_color = Color(0.8, 0.8, 0.8, 1.0)
		stylebox.border_color = Color(0, 0, 0, 1.0)
		stylebox.border_width_bottom = 1
		stylebox.border_width_top = 1
		stylebox.border_width_left = 1
		stylebox.border_width_right = 1
		stylebox.corner_radius_bottom_left = 3
		stylebox.corner_radius_bottom_right = 3
		stylebox.corner_radius_top_left = 3
		stylebox.corner_radius_top_right = 3
		text_edit.add_theme_stylebox_override("normal", stylebox)
		text_edit.add_theme_stylebox_override("focus", stylebox)
		text_edit.add_theme_stylebox_override("readonly", stylebox)
	else:
		text_edit.remove_theme_stylebox_override("normal")
		text_edit.remove_theme_stylebox_override("focus")
		text_edit.remove_theme_stylebox_override("readonly")
		
		if element.has_attribute("readonly"):
			text_edit.editable = false
		else:
			text_edit.editable = true
	
	# Handle maxlength
	if maxlength.length() > 0 and maxlength.is_valid_int():
		var max_len = maxlength.to_int()
		# Disconnect existing signal if connected to prevent duplicates
		if text_edit.text_changed.is_connected(_on_text_changed):
			text_edit.text_changed.disconnect(_on_text_changed)
		text_edit.text_changed.connect(_on_text_changed.bind(max_len))
	
	# Enable focus mode for textarea to support change events on focus lost
	text_edit.focus_mode = Control.FOCUS_ALL
	
	parser.register_dom_node(element, text_edit)

func _on_text_changed(max_length: int) -> void:
	var text_edit = $TextEdit as TextEdit
	if not text_edit:
		return

	if text_edit.text.length() > max_length:
		var cursor_pos = text_edit.get_caret_column()
		var line_pos = text_edit.get_caret_line()
		text_edit.text = text_edit.text.substr(0, max_length)
		var line_count = text_edit.get_line_count()
		if line_count == 0:
			text_edit.set_caret_line(0)
			text_edit.set_caret_column(0)
			return
		line_pos = clamp(line_pos, 0, line_count - 1)
		text_edit.set_caret_line(line_pos)
		var line_text = text_edit.get_line(line_pos)
		text_edit.set_caret_column(min(cursor_pos, line_text.length()))
