class_name ApplicationTab
extends VBoxContainer

@onready var crumbs_tree: Tree
@onready var add_crumb_btn: Button
@onready var edit_crumb_btn: Button
@onready var delete_crumb_btn: Button
@onready var clear_crumbs_btn: Button

var crumbs_data: Array[Dictionary] = []
var current_tab: Tab

func _ready():
	print("ApplicationTab: _ready() called")
	
	crumbs_tree = $CrumbsTree
	add_crumb_btn = $ButtonContainer/AddCrumbBtn
	edit_crumb_btn = $ButtonContainer/EditCrumbBtn
	delete_crumb_btn = $ButtonContainer/DeleteCrumbBtn
	clear_crumbs_btn = $ButtonContainer/ClearCrumbsBtn
	
	print("ApplicationTab: crumbs_tree = ", crumbs_tree)
	print("ApplicationTab: add_crumb_btn = ", add_crumb_btn)
	
	if crumbs_tree:
		print("ApplicationTab: Connecting crumbs_tree signals")
		crumbs_tree.item_selected.connect(_on_crumb_selected)
		crumbs_tree.gui_input.connect(_on_tree_gui_input)
	else:
		print("ApplicationTab: crumbs_tree is null!")
		
	if add_crumb_btn:
		print("ApplicationTab: Connecting add_crumb_btn signal")
		add_crumb_btn.pressed.connect(_on_add_crumb)
	else:
		print("ApplicationTab: add_crumb_btn is null!")
		
	if edit_crumb_btn:
		edit_crumb_btn.pressed.connect(_on_edit_crumb)
	if delete_crumb_btn:
		delete_crumb_btn.pressed.connect(_on_delete_crumb)
	if clear_crumbs_btn:
		clear_crumbs_btn.pressed.connect(_on_clear_crumbs)
	
	if edit_crumb_btn:
		edit_crumb_btn.disabled = true
	if delete_crumb_btn:
		delete_crumb_btn.disabled = true
		
	print("ApplicationTab: _ready() completed")

func set_current_tab(tab: Tab):
	print("ApplicationTab: set_current_tab called with tab = ", tab)
	current_tab = tab
	load_crumbs_for_current_tab()
	
	if current_tab and current_tab.has_signal("url_changed"):
		if not current_tab.url_changed.is_connected(_on_url_changed):
			current_tab.url_changed.connect(_on_url_changed)
	
	if current_tab and current_tab.has_signal("content_updated"):
		if not current_tab.content_updated.is_connected(_on_content_updated):
			current_tab.content_updated.connect(_on_content_updated)

func load_crumbs_for_current_tab():
	print("ApplicationTab: load_crumbs_for_current_tab called")
	if not current_tab:
		print("ApplicationTab: No current tab, returning")
		return
	
	var domain = get_domain_from_url(current_tab.current_url)
	print("ApplicationTab: Domain = ", domain)
	crumbs_data = get_crumbs_for_domain(domain)
	print("ApplicationTab: Loaded ", crumbs_data.size(), " crumbs")
	update_crumbs_tree()

func get_domain_from_url(url: String) -> String:
	print("ApplicationTab: get_domain_from_url called with: ", url)
	if url.begins_with("gurt://"):
		var parts = url.split("/")
		print("ApplicationTab: gurt:// parts: ", parts)
		if parts.size() > 2:
			var domain = parts[2]
			print("ApplicationTab: gurt:// domain: ", domain)
			return domain
	elif url.begins_with("http://") or url.begins_with("https://"):
		var parts = url.split("/")
		print("ApplicationTab: http(s):// parts: ", parts)
		if parts.size() > 2:
			var domain = parts[2]
			print("ApplicationTab: http(s):// domain: ", domain)
			return domain
	print("ApplicationTab: No domain found, returning empty string")
	return ""

func get_crumbs_for_domain(domain: String) -> Array[Dictionary]:
	print("ApplicationTab: get_crumbs_for_domain called with domain: ", domain)
	var file_path = "user://crumbs/" + domain + ".json"
	print("ApplicationTab: Looking for crumbs file: ", file_path)
	
	if not FileAccess.file_exists(file_path):
		print("ApplicationTab: Crumbs file does not exist")
		return []
	
	var file = FileAccess.open(file_path, FileAccess.READ)
	if not file:
		print("ApplicationTab: Failed to open crumbs file")
		return []
	
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var parse_result = json.parse(json_string)
	if parse_result != OK:
		print("ApplicationTab: Failed to parse crumbs JSON")
		return []
	
	var crumbs_data = json.data
	if not crumbs_data is Dictionary:
		print("ApplicationTab: Crumbs data is not a dictionary")
		return []
	
	var result: Array[Dictionary] = []
	for crumb_name in crumbs_data:
		var crumb_dict = crumbs_data[crumb_name]
		if crumb_dict is Dictionary:
			var crumb = {
				"name": crumb_name,
				"value": crumb_dict.get("value", ""),
				"domain": domain,
				"created": crumb_dict.get("created_at", 0),
				"lifespan": crumb_dict.get("lifespan", -1.0)
			}
			result.append(crumb)
	
	print("ApplicationTab: Loaded ", result.size(), " crumbs from file")
	return result

func _on_url_changed():
	print("ApplicationTab: URL changed, refreshing crumbs")
	load_crumbs_for_current_tab()

func _on_content_updated():
	print("ApplicationTab: Content updated, refreshing crumbs")
	load_crumbs_for_current_tab()

func save_crumbs_for_domain(domain: String, crumbs: Array[Dictionary]):
	print("ApplicationTab: save_crumbs_for_domain called for domain: ", domain)
	
	# Ensure crumbs directory exists
	var crumbs_dir = "user://crumbs/"
	if not DirAccess.dir_exists_absolute(crumbs_dir):
		DirAccess.make_dir_recursive_absolute(crumbs_dir)
	
	# Convert array to dictionary format
	var crumbs_data = {}
	for crumb in crumbs:
		crumbs_data[crumb.get("name", "")] = {
			"value": crumb.get("value", ""),
			"created_at": crumb.get("created", Time.get_unix_time_from_system()),
			"lifespan": crumb.get("lifespan", -1.0)
		}
	
	# Save to file
	var file_path = crumbs_dir + domain + ".json"
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if not file:
		print("ApplicationTab: Failed to open crumbs file for writing: ", file_path)
		return
	
	var json_string = JSON.stringify(crumbs_data)
	file.store_string(json_string)
	file.close()
	print("ApplicationTab: Crumbs saved to file: ", file_path)

func update_crumbs_tree():
	print("ApplicationTab: update_crumbs_tree called")
	if not crumbs_tree:
		print("ApplicationTab: crumbs_tree is null, cannot update")
		return
		
	crumbs_tree.clear()
	
	if crumbs_data.is_empty():
		print("ApplicationTab: No crumbs data, showing empty message")
		var root = crumbs_tree.create_item()
		root.set_text(0, "No crumbs for this domain")
		root.set_icon(0, null)
		return
	
	print("ApplicationTab: Creating tree with ", crumbs_data.size(), " crumbs")
	
	for i in range(crumbs_data.size()):
		var crumb = crumbs_data[i]
		var name = crumb.get("name", "Unnamed Crumb")
		var value = crumb.get("value", "")
		
		var crumb_item = crumbs_tree.create_item()
		crumb_item.set_text(0, name)
		crumb_item.set_metadata(0, {"index": i, "crumb": crumb, "type": "crumb"})
		crumb_item.set_icon(0, null)
		
		var value_item = crumbs_tree.create_item(crumb_item)
		value_item.set_text(0, value)
		value_item.set_metadata(0, {"index": i, "crumb": crumb, "type": "value"})
		value_item.set_icon(0, null)
		
		print("ApplicationTab: Added crumb: ", name)

func _on_crumb_selected():
	print("ApplicationTab: _on_crumb_selected called")
	var selected = crumbs_tree.get_selected()
	if selected and selected.get_metadata(0) != null:
		var metadata = selected.get_metadata(0)
		var type = metadata.get("type", "")
		if type == "crumb":
			print("ApplicationTab: Crumb selected, enabling buttons")
			if edit_crumb_btn:
				edit_crumb_btn.disabled = false
			if delete_crumb_btn:
				delete_crumb_btn.disabled = false
		else:
			print("ApplicationTab: Value selected, disabling buttons")
			if edit_crumb_btn:
				edit_crumb_btn.disabled = true
			if delete_crumb_btn:
				delete_crumb_btn.disabled = true
	else:
		print("ApplicationTab: No crumb selected, disabling buttons")
		if edit_crumb_btn:
			edit_crumb_btn.disabled = true
		if delete_crumb_btn:
			delete_crumb_btn.disabled = true

func _on_tree_gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		print("ApplicationTab: Right click detected")
		var selected = crumbs_tree.get_selected()
		if not selected or selected.get_metadata(0) == null:
			print("ApplicationTab: No valid selection for context menu")
			return
		
		print("ApplicationTab: Creating context menu")
		var context_menu = PopupMenu.new()
		context_menu.add_item("Copy", 0)
		context_menu.add_item("Edit", 1)
		context_menu.add_item("Delete", 2)
		context_menu.size = Vector2(100, 30)
		context_menu.position = get_global_mouse_position()
		add_child(context_menu)
		
		context_menu.id_pressed.connect(_on_context_menu_selected.bind(context_menu, selected))
		context_menu.popup()
		print("ApplicationTab: Context menu shown")

func _on_context_menu_selected(id: int, context_menu: PopupMenu, selected: TreeItem):
	match id:
		0:
			_on_copy_crumb()
		1:
			_on_edit_crumb()
		2:
			_on_delete_crumb()
	
	context_menu.queue_free()

func _on_copy_crumb():
	print("ApplicationTab: _on_copy_crumb called")
	var selected = crumbs_tree.get_selected()
	if not selected or selected.get_metadata(0) == null:
		print("ApplicationTab: No valid selection for copy")
		return
	
	var metadata = selected.get_metadata(0)
	var crumb = metadata["crumb"]
	var value = crumb.get("value", "")
	
	DisplayServer.clipboard_set(value)
	print("ApplicationTab: Copied crumb value: ", value)

func _on_add_crumb():
	print("ApplicationTab: _on_add_crumb called")
	show_crumb_dialog("", "", "")

func _on_edit_crumb():
	print("ApplicationTab: _on_edit_crumb called")
	var selected = crumbs_tree.get_selected()
	if not selected or selected.get_metadata(0) == null:
		print("ApplicationTab: No valid selection for edit")
		return
	
	var metadata = selected.get_metadata(0)
	var type = metadata.get("type", "")
	if type != "crumb":
		print("ApplicationTab: Must select crumb (not value) to edit")
		return
	
	var crumb = metadata["crumb"]
	show_crumb_dialog(crumb.get("name", ""), crumb.get("value", ""), crumb.get("domain", ""), metadata["index"])

func _on_delete_crumb():
	print("ApplicationTab: _on_delete_crumb called")
	var selected = crumbs_tree.get_selected()
	if not selected or selected.get_metadata(0) == null:
		print("ApplicationTab: No valid selection for delete")
		return
	
	var metadata = selected.get_metadata(0)
	var type = metadata.get("type", "")
	if type != "crumb":
		print("ApplicationTab: Must select crumb (not value) to delete")
		return
	
	var index = metadata["index"]
	
	crumbs_data.remove_at(index)
	save_crumbs()
	update_crumbs_tree()

func _on_clear_crumbs():
	print("ApplicationTab: _on_clear_crumbs called")
	crumbs_data.clear()
	save_crumbs()
	update_crumbs_tree()

func show_crumb_dialog(name: String, value: String, domain: String, edit_index: int = -1):
	print("ApplicationTab: show_crumb_dialog called")
	var dialog = AcceptDialog.new()
	dialog.title = "Edit Crumb" if edit_index >= 0 else "Add Crumb"
	dialog.size = Vector2(400, 200)
	
	var vbox = VBoxContainer.new()
	dialog.add_child(vbox)
	
	var name_label = Label.new()
	name_label.text = "Name:"
	vbox.add_child(name_label)
	
	var name_input = LineEdit.new()
	name_input.text = name
	name_input.placeholder_text = "Enter crumb name"
	vbox.add_child(name_input)
	
	var value_label = Label.new()
	value_label.text = "Value:"
	vbox.add_child(value_label)
	
	var value_input = LineEdit.new()
	value_input.text = value
	value_input.placeholder_text = "Enter crumb value"
	vbox.add_child(value_input)
	
	var domain_label = Label.new()
	domain_label.text = "Domain:"
	vbox.add_child(domain_label)
	
	var domain_input = LineEdit.new()
	domain_input.text = domain
	domain_input.placeholder_text = "Enter domain (optional)"
	vbox.add_child(domain_input)
	
	var button_container = HBoxContainer.new()
	vbox.add_child(button_container)
	
	var save_btn = Button.new()
	save_btn.text = "Save"
	button_container.add_child(save_btn)
	
	var cancel_btn = Button.new()
	cancel_btn.text = "Cancel"
	button_container.add_child(cancel_btn)
	
	add_child(dialog)
	dialog.popup_centered()
	
	save_btn.pressed.connect(_on_save_crumb.bind(dialog, name_input, value_input, domain_input, edit_index))
	cancel_btn.pressed.connect(dialog.queue_free)

func _on_save_crumb(dialog: AcceptDialog, name_input: LineEdit, value_input: LineEdit, domain_input: LineEdit, edit_index: int):
	var name = name_input.text.strip_edges()
	var value = value_input.text.strip_edges()
	var domain = domain_input.text.strip_edges()
	
	if name.is_empty() or value.is_empty():
		return
	
	if domain.is_empty() and current_tab:
		domain = get_domain_from_url(current_tab.current_url)
	
	var crumb = {
		"name": name,
		"value": value,
		"domain": domain,
		"created": Time.get_unix_time_from_system()
	}
	
	if edit_index >= 0:
		crumbs_data[edit_index] = crumb
	else:
		crumbs_data.append(crumb)
	
	save_crumbs()
	update_crumbs_tree()
	dialog.queue_free()

func save_crumbs():
	if not current_tab:
		return
	
	var domain = get_domain_from_url(current_tab.current_url)
	save_crumbs_for_domain(domain, crumbs_data)
