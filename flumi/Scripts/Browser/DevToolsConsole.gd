class_name DevToolsConsole
extends VBoxContainer

@onready var log_container: VBoxContainer = $ScrollContainer/LogContainer
@onready var input_line: CodeEdit = $InputContainer/InputLine
@onready var scroll_container: ScrollContainer = $ScrollContainer
@onready var clear_button: Button = $Toolbar/ClearButton
@onready var filter_input: LineEdit = $Toolbar/LineEdit

var log_entries: Array[Dictionary] = []
var current_filter: String = ""
var last_log_item: Control = null
var last_log_entry: Dictionary = {}
var input_history: Array[String] = []
var history_index: int = -1

func _ready():
	connect_signals()
	initialize_filter()
	load_existing_logs()
	
	visibility_changed.connect(_on_visibility_changed)

func initialize_filter() -> void:
	filter_input.placeholder_text = "Filter"
	current_filter = ""

func connect_signals() -> void:
	clear_button.pressed.connect(_on_clear_pressed)
	
	input_line.gui_input.connect(_on_input_gui_input)
	filter_input.text_changed.connect(_on_filter_changed)

func load_existing_logs() -> void:
	var existing_messages = Trace.get_all_messages()
	for msg in existing_messages:
		add_log_entry(msg.message, msg.level, msg.timestamp)

func _on_lua_print(message: String) -> void:
	add_log_entry(message, "lua", Time.get_ticks_msec() / 1000.0)

func add_log_entry(message: Variant, level: String, timestamp: float) -> void:
	var entry = {
		"message": message,
		"level": level,
		"timestamp": timestamp,
		"count": 1
	}
	
	if can_group_with_last_entry(entry):
		last_log_entry.count += 1
		last_log_entry.timestamp = timestamp
		log_entries[log_entries.size() - 1] = last_log_entry
		
		update_log_item_display(last_log_item, last_log_entry)
		return
	
	log_entries.append(entry)
	last_log_entry = entry
	
	var should_add_separator = false
	if level == "log" or level == "lua" or level == "input":
		if log_container.get_child_count() > 0:
			var last_displayed_entry = get_last_displayed_entry()
			if last_displayed_entry and last_displayed_entry.level != "warning" and last_displayed_entry.level != "error":
				should_add_separator = true
	
	if should_add_separator:
		var separator = HSeparator.new()
		separator.add_theme_color_override("separator", Color.GRAY * 0.3)
		log_container.add_child(separator)
	
	var log_item = create_log_item(entry)
	log_container.add_child(log_item)
	last_log_item = log_item
	
	apply_filter_to_item(log_item, entry)
	
	call_deferred("_scroll_to_bottom")

func create_log_item(entry: Dictionary) -> Control:
	if entry.level == "input":
		var input_display_text = get_display_text_for_entry(entry)
		var message_code_edit = CodeEditUtils.create_code_edit({
			"text": input_display_text,
			"scroll_fit_content_height": true,
			"transparent_background": true,
			"syntax_highlighter": input_line.syntax_highlighter.duplicate(),
			"block_editing_signals": true,
			"size_flags_vertical": Control.SIZE_SHRINK_CENTER
		})
		
		message_code_edit.gui_input.connect(_on_log_code_edit_gui_input)
		message_code_edit.focus_entered.connect(_on_log_code_edit_focus_entered.bind(message_code_edit))
		message_code_edit.text_changed.connect(_on_log_code_edit_text_changed.bind(message_code_edit, input_display_text))
		
		return message_code_edit
	
	if entry.level == "lua" and entry.message is Dictionary and entry.message.has("parts"):
		return create_structured_log_item(entry)
	
	var panel = PanelContainer.new()
	var style_box = StyleBoxFlat.new()
	
	match entry.level:
		"warning":
			style_box.bg_color = Color.YELLOW
			style_box.bg_color.a = 0.2
			style_box.corner_radius_top_left = 6
			style_box.corner_radius_top_right = 6
			style_box.corner_radius_bottom_left = 6
			style_box.corner_radius_bottom_right = 6
			style_box.content_margin_left = 8
			style_box.content_margin_right = 8
			style_box.content_margin_top = 4
			style_box.content_margin_bottom = 4
		"error":
			style_box.bg_color = Color.RED
			style_box.bg_color.a = 0.2
			style_box.corner_radius_top_left = 6
			style_box.corner_radius_top_right = 6
			style_box.corner_radius_bottom_left = 6
			style_box.corner_radius_bottom_right = 6
			style_box.content_margin_left = 8
			style_box.content_margin_right = 8
			style_box.content_margin_top = 4
			style_box.content_margin_bottom = 4
		_:
			style_box.bg_color = Color.TRANSPARENT
	
	panel.add_theme_stylebox_override("panel", style_box)
	
	var container: Control
	if entry.level == "warning" or entry.level == "error":
		var margin_container = MarginContainer.new()
		margin_container.add_child(panel)
		container = margin_container
	else:
		container = panel
	
	var message_label = Label.new()
	var display_text = get_display_text_for_entry(entry)
	message_label.text = display_text
	message_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	
	match entry.level:
		"warning":
			message_label.add_theme_color_override("font_color", Color.YELLOW)
		"error":
			message_label.add_theme_color_override("font_color", Color.WHITE)
		_:
			message_label.add_theme_color_override("font_color", Color.WHITE)
	
	panel.add_child(message_label)
	return container

func _scroll_to_bottom() -> void:
	if scroll_container:
		scroll_container.scroll_vertical = int(scroll_container.get_v_scroll_bar().max_value)

func _on_clear_pressed() -> void:
	for child in log_container.get_children():
		child.queue_free()
	log_entries.clear()
	
	last_log_item = null
	last_log_entry = {}
	
	Trace.clear_messages()

func _on_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ENTER and event.ctrl_pressed:
			var text = input_line.text.strip_edges()
			if not text.is_empty():
				_on_input_submitted(text)
				input_line.text = ""
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_UP and not event.ctrl_pressed and not event.shift_pressed and not event.alt_pressed:
			if input_line.get_caret_column() == 0 and input_line.get_caret_line() == 0:
				navigate_history_up()
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_DOWN and not event.ctrl_pressed and not event.shift_pressed and not event.alt_pressed:
			var caret_pos = input_line.get_caret_column()
			var last_line = input_line.get_line_count() - 1
			var last_line_length = input_line.get_line(last_line).length()
			if input_line.get_caret_line() == last_line and caret_pos == last_line_length:
				navigate_history_down()
				get_viewport().set_input_as_handled()

func navigate_history_up() -> void:
	if input_history.is_empty():
		return
	if history_index == -1:
		history_index = input_history.size() - 1
	elif history_index > 0:
		history_index -= 1
	
	if history_index >= 0 and history_index < input_history.size():
		input_line.text = input_history[history_index]
		call_deferred("move_caret_to_end")

func navigate_history_down() -> void:
	if input_history.is_empty() or history_index == -1:
		return
	
	history_index += 1
	
	if history_index >= input_history.size():
		history_index = -1
		input_line.text = ""
	else:
		input_line.text = input_history[history_index]
		call_deferred("move_caret_to_end")

func move_caret_to_end() -> void:
	var last_line = input_line.get_line_count() - 1
	var last_line_length = input_line.get_line(last_line).length()
	input_line.set_caret_line(last_line)
	input_line.set_caret_column(last_line_length)

func _on_input_submitted(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	
	if input_history.is_empty() or input_history[input_history.size() - 1] != text:
		input_history.append(text)
		if input_history.size() > 100:
			input_history.pop_front()
	
	history_index = -1
	
	add_log_entry("> " + text, "input", Time.get_ticks_msec() / 1000.0)
	
	execute_lua_command(text)

func execute_lua_command(code: String) -> void:
	var main_scene = Engine.get_main_loop().current_scene
	if main_scene and main_scene.has_method("get_active_tab"):
		var active_tab = main_scene.get_active_tab()
		if active_tab and active_tab.lua_apis.size() > 0:
			var lua_api = active_tab.lua_apis[0]
			if lua_api:
				var is_expression = is_likely_expression(code)
				if is_expression:
					var wrapped_code = "print(" + code + ")"
					lua_api.execute_lua_script(wrapped_code, "<console>")
				else:
					lua_api.execute_lua_script(code, "<console>")
				return
	
	add_log_entry("No Lua context available", "error", Time.get_ticks_msec() / 1000.0)

func is_likely_expression(code: String) -> bool:
	var trimmed = code.strip_edges()
	var statement_keywords = ["if", "for", "while", "do", "function", "local", "return", "break"]
	for keyword in statement_keywords:
		if trimmed.begins_with(keyword + " ") or trimmed.begins_with(keyword + "("):
			return false
	if "=" in trimmed and not ("==" in trimmed or "!=" in trimmed or ">=" in trimmed or "<=" in trimmed):
		return false
	if "print(" in trimmed or "console.log(" in trimmed or "_trace_" in trimmed:
		return false
	if trimmed.ends_with(")") or trimmed.ends_with("]") or not (" " in trimmed):
		return true
	return true

func _on_filter_changed(new_text: String) -> void:
	current_filter = new_text.strip_edges()
	refresh_log_display()

func refresh_log_display() -> void:
	for i in range(log_container.get_child_count()):
		var child = log_container.get_child(i)
		if child is HSeparator:
			child.visible = should_separator_be_visible(i)
		else:
			var entry_index = get_entry_index_for_child(i)
			if entry_index >= 0 and entry_index < log_entries.size():
				var entry = log_entries[entry_index]
				apply_filter_to_item(child, entry)
	
	call_deferred("_scroll_to_bottom")

func apply_filter_to_item(item: Control, entry: Dictionary) -> void:
	item.visible = entry_matches_filter(entry)

func entry_matches_filter(entry: Dictionary) -> bool:
	if current_filter.is_empty():
		return true
	
	var message_text = ""
	if entry.message is Dictionary and entry.message.has("parts"):
		message_text = get_display_text_for_entry(entry)
	else:
		message_text = str(entry.message)
	
	if current_filter.to_lower() in message_text.to_lower():
		return true
	
	if current_filter.to_lower() == entry.level.to_lower():
		return true
	
	return false

func get_last_displayed_entry() -> Dictionary:
	for i in range(log_entries.size() - 2, -1, -1):  # Start from second-to-last entry
		var entry = log_entries[i]
		if entry_matches_filter(entry):
			return entry
	return {}

func should_separator_be_visible(separator_index: int) -> bool:
	var before_visible = false
	var after_visible = false
	
	if separator_index > 0:
		var before_child = log_container.get_child(separator_index - 1)
		before_visible = before_child.visible
	
  
	if separator_index < log_container.get_child_count() - 1:
		var after_child = log_container.get_child(separator_index + 1)
		after_visible = after_child.visible
	
	return before_visible and after_visible

func get_entry_index_for_child(child_index: int) -> int:
	var entry_index = 0
	for i in range(child_index):
		var child = log_container.get_child(i)
		if not child is HSeparator:
			entry_index += 1
	return entry_index

func can_group_with_last_entry(entry: Dictionary) -> bool:
	if last_log_entry.is_empty() or last_log_item == null:
		return false
	
	if entry.level != last_log_entry.level:
		return false
	
	var current_message_text = ""
	var last_message_text = ""
	
	if entry.message is Dictionary and entry.message.has("parts"):
		current_message_text = get_display_text_for_entry(entry)
	else:
		current_message_text = str(entry.message)
	
	if last_log_entry.message is Dictionary and last_log_entry.message.has("parts"):
		last_message_text = get_display_text_for_entry(last_log_entry)
	else:
		last_message_text = str(last_log_entry.message)
	
	if current_message_text != last_message_text:
		return false
	
	if entry.level == "input":
		return false
	
	return true

func update_log_item_display(log_item: Control, entry: Dictionary) -> void:
	if entry.level == "input":
		var code_edit = log_item as CodeEdit
		if code_edit:
			code_edit.text = get_display_text_for_entry(entry)
	else:
		var label = find_message_label_in_item(log_item)
		if label:
			label.text = get_display_text_for_entry(entry)

func find_message_code_edit_in_item(item: Control) -> CodeEdit:
	if item is CodeEdit:
		return item as CodeEdit
	
	if item is MarginContainer:
		var panel = item.get_child(0) as PanelContainer
		if panel:
			return panel.get_child(0) as CodeEdit
	elif item is PanelContainer:
		return item.get_child(0) as CodeEdit
	return null

func find_message_label_in_item(item: Control) -> Label:
	if item is MarginContainer:
		var panel = item.get_child(0) as PanelContainer
		if panel:
			return panel.get_child(0) as Label
	elif item is PanelContainer:
		return item.get_child(0) as Label
	return null

func _on_log_code_edit_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var key = event.keycode
		if event.ctrl_pressed and (key == KEY_C or key == KEY_A):
			return
		if key in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_HOME, KEY_END, KEY_PAGEUP, KEY_PAGEDOWN]:
			return
		if event.shift_pressed and key in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_HOME, KEY_END]:
			return
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		return

func _on_log_code_edit_focus_entered(code_edit: CodeEdit) -> void:
	code_edit.release_focus()

func _on_log_code_edit_text_changed(code_edit: CodeEdit, original_text: String) -> void:
	if code_edit.text != original_text:
		code_edit.text = original_text

func get_display_text_for_entry(entry: Dictionary) -> String:
	var count = entry.get("count", 1)
	var message = entry.message
	
	var base_text = ""
	if message is Dictionary and message.has("parts"):
		var parts = message.parts
		var text_parts = []
		for part in parts:
			if part.type == "primitive":
				text_parts.append(str(part.data))
			elif part.type == "table":
				var key_count = part.data.keys().size()
				text_parts.append("Object {" + str(key_count) + "}")
		base_text = "\t".join(text_parts)
	else:
		base_text = str(message)
	
	if count > 1:
		return "(" + str(count) + ") " + base_text
	else:
		return base_text

func create_structured_log_item(entry) -> Control:
	var container = VBoxContainer.new()
	var parts = entry.message.parts
	if parts.size() == 1 and parts[0].type == "primitive":
		var simple_panel = PanelContainer.new()
		var style_box = StyleBoxFlat.new()
		style_box.bg_color = Color.TRANSPARENT
		style_box.content_margin_left = 10
		style_box.content_margin_top = 5
		style_box.content_margin_right = 10
		style_box.content_margin_bottom = 5
		simple_panel.add_theme_stylebox_override("panel", style_box)
		var label = Label.new()
		label.text = str(parts[0].data)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		simple_panel.add_child(label)
		container.add_child(simple_panel)
		return container
	
	for i in range(parts.size()):
		var part = parts[i]
		
		if part.type == "primitive":
			var text_panel = PanelContainer.new()
			var style_box = StyleBoxFlat.new()
			style_box.bg_color = Color.TRANSPARENT
			style_box.content_margin_left = 10
			style_box.content_margin_top = 2
			style_box.content_margin_right = 10
			style_box.content_margin_bottom = 2
			text_panel.add_theme_stylebox_override("panel", style_box)
			
			var label = Label.new()
			label.text = str(part.data)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			text_panel.add_child(label)
			container.add_child(text_panel)
			
		elif part.type == "table":
			var table_item = create_expandable_table_item(part.data)
			container.add_child(table_item)
	
	return container

func create_expandable_table_item(table_data) -> Control:
	var main_container = VBoxContainer.new()
	
	var header_container = HBoxContainer.new()
	header_container.custom_minimum_size.y = 24
	
	var chevron_button = Button.new()
	chevron_button.text = "▶"
	chevron_button.custom_minimum_size = Vector2(20, 20)
	chevron_button.flat = true
	chevron_button.focus_mode = Control.FOCUS_NONE
	header_container.add_child(chevron_button)
	
	var summary_label = Label.new()
	var key_count = table_data.keys().size()
	if table_data.has("__type"):
		summary_label.text = str(table_data.get("__type", "Object")) + " {" + str(key_count) + "}"
	else:
		summary_label.text = "Object {" + str(key_count) + "}"
	summary_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_container.add_child(summary_label)
	
	main_container.add_child(header_container)
	
	var content_container = VBoxContainer.new()
	content_container.visible = false
	
	for key in table_data.keys():
		if key == "__type":
			continue
			
		var value = table_data[key]
		var row_container = HBoxContainer.new()
		
		var key_label = Label.new()
		key_label.text = str(key) + ": "
		key_label.custom_minimum_size.x = 80
		key_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		row_container.add_child(key_label)
		
		var value_label = Label.new()
		if value is Dictionary:
			var nested_count = value.keys().size()
			value_label.text = "Object {" + str(nested_count) + "}"
			value_label.modulate = Color.GRAY
		elif value is Array:
			value_label.text = "Array [" + str(value.size()) + "]"
			value_label.modulate = Color.GRAY
		else:
			value_label.text = str(value)
		
		value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		value_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_container.add_child(value_label)
		
		content_container.add_child(row_container)
	
	main_container.add_child(content_container)
	
	chevron_button.pressed.connect(func():
		content_container.visible = !content_container.visible
		chevron_button.text = "▼" if content_container.visible else "▶"
	)
	
	return main_container

func _on_visibility_changed() -> void:
	if visible:
		input_line.grab_focus()
