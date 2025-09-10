class_name TabManager
extends HBoxContainer

var tabs: Array[Tab] = []
var active_tab := 0

@onready var main: Main = $"../.."

const TAB = preload("res://Scenes/Tab.tscn")

const TAB_NORMAL: StyleBoxFlat = preload("res://Scenes/Styles/TabNormal.tres")
const TAB_HOVER: StyleBoxFlat = preload("res://Scenes/Styles/TabHover.tres")

const TAB_DEFAULT: StyleBoxFlat = preload("res://Scenes/Styles/TabDefault.tres")
const TAB_HOVER_DEFAULT: StyleBoxFlat = preload("res://Scenes/Styles/TabHoverDefault.tres")

const TAB_GRADIENT: GradientTexture2D = preload("res://Scenes/Styles/TabGradient.tres")
const TAB_GRADIENT_DEFAULT: GradientTexture2D = preload("res://Scenes/Styles/TabGradientDefault.tres")

@onready var h_box_container: HBoxContainer = $HBoxContainer

const MIN_TAB_WIDTH = 24                  # Minimum width (icon only)
const MIN_TAB_WIDTH_WITH_CLOSE = 60       # Minimum width when close button is visible
const MAX_TAB_WIDTH = 320                 # Max width
const CLOSE_BUTTON_HIDE_THRESHOLD = 100   # When to hide close button
const TEXT_HIDE_THRESHOLD = 50            # When to hide text
const POPUP_BUTTON_WIDTH = 50             # Width of + button
const NEW_TAB_BUTTON_WIDTH = 50           # Width of new tab button
const OTHER_UI_PADDING = 200              # Space for other UI elements

func _ready() -> void:
	tabs.assign(get_tree().get_nodes_in_group("tabs"))
	
	call_deferred("_initialize_tab_containers")
	
	set_active_tab(0)
	
	for i in tabs.size():
		tabs[i].tab_pressed.connect(_tab_pressed.bind(i))
		tabs[i].tab_closed.connect(_tab_closed.bind(i))
	
	get_viewport().size_changed.connect(_on_viewport_resized)
	
	call_deferred("update_tab_widths")
	call_deferred("_delayed_update")

func _initialize_tab_containers() -> void:
	for tab in tabs:
		trigger_init_scene(tab)

func trigger_init_scene(tab: Tab) -> void:
	var main_vbox = main.get_node("VBoxContainer")
	tab.init_scene(main_vbox)

func _tab_pressed(index: int) -> void:
	set_active_tab(index)

func _tab_closed(index: int) -> void:
	tabs.remove_at(index)

	if tabs.is_empty():
		get_tree().quit()
		return

	if index <= active_tab:
		if index == active_tab:
			# Closed tab was active, select right neighbor (or last tab if at end)
			if index >= tabs.size():
				active_tab = tabs.size() - 1
			else:
				active_tab = index
		else:
			# Closed tab was before active tab, shift active index down
			active_tab -= 1
	
	# Reconnect signals with updated indices
	for i in tabs.size():
		tabs[i].tab_pressed.disconnect(_tab_pressed)
		tabs[i].tab_closed.disconnect(_tab_closed)
		tabs[i].tab_pressed.connect(_tab_pressed.bind(i))
		tabs[i].tab_closed.connect(_tab_closed.bind(i))

	set_active_tab(active_tab)
	update_tab_widths()

func _on_viewport_resized() -> void:
	update_tab_widths()

func _delayed_update() -> void:
	update_tab_widths()

func update_tab_widths() -> void:
	if tabs.is_empty():
		return
		
	var viewport_width = get_viewport().get_visible_rect().size.x
	var available_width = viewport_width - POPUP_BUTTON_WIDTH - NEW_TAB_BUTTON_WIDTH - OTHER_UI_PADDING
	
	var tab_width = available_width / float(tabs.size())
	tab_width = clamp(tab_width, MIN_TAB_WIDTH, MAX_TAB_WIDTH)
	
	var should_hide_close = tab_width < CLOSE_BUTTON_HIDE_THRESHOLD
	var should_hide_text = tab_width < TEXT_HIDE_THRESHOLD
		
	h_box_container.custom_minimum_size.x = 0
	h_box_container.size.x = 0
	
	for tab in tabs:
		if tab.appear_tween and tab.appear_tween.is_valid():
			continue
		
		tab.custom_minimum_size.x = tab_width
		tab.size.x = tab_width
		
		tab.button.custom_minimum_size.x = tab_width
		tab.button.size.x = tab_width
		
		tab.close_button.visible = not should_hide_close
		tab.button.text = "" if should_hide_text else tab.button.get_meta("original_text", tab.button.text)
		
		if not tab.button.has_meta("original_text"):
			tab.button.set_meta("original_text", tab.button.text)
		
		update_tab_internal_elements(tab, tab_width, should_hide_close, should_hide_text)

func calculate_visible_tab_count(available_width: float) -> int:
	var all_tabs_width = calculate_tab_width(available_width, tabs.size())
	if all_tabs_width >= MIN_TAB_WIDTH:
		return tabs.size()
	
	for tab_count in range(tabs.size(), 0, -1):
		var tab_width = calculate_tab_width(available_width, tab_count)
		if tab_width >= MIN_TAB_WIDTH:
			return tab_count
	
	return max(1, tabs.size())

func calculate_tab_width(available_width: float, tab_count: int) -> float:
	if tab_count == 0:
		return MAX_TAB_WIDTH
	
	var ideal_width = available_width / tab_count
	return clamp(ideal_width, MIN_TAB_WIDTH, MAX_TAB_WIDTH)

func get_hidden_tabs() -> Array[Tab]:
	var hidden_tabs: Array[Tab] = []
	for tab in tabs:
		if not tab.visible:
			hidden_tabs.append(tab)
	return hidden_tabs

func has_hidden_tabs() -> bool:
	return get_hidden_tabs().size() > 0

func update_tab_internal_elements(tab: Tab, width: float, hide_close_button: bool = false, hide_text: bool = false) -> void:
	var should_show_gradient = not hide_text and not hide_close_button
	tab.gradient_texture.visible = should_show_gradient
	
	if should_show_gradient:
		var gradient_start_offset = 72
		var gradient_width = 64
		var gradient_start_x = width - gradient_start_offset
		
		tab.gradient_texture.position.x = gradient_start_x
		tab.gradient_texture.size.x = gradient_width
	
	if not hide_close_button:
		var close_button_x = width - 34
		tab.close_button.position.x = close_button_x

func set_active_tab(index: int) -> void:
	if index < 0 or index >= tabs.size():
		return
		
	if active_tab >= 0 and active_tab < tabs.size():
		tabs[active_tab].is_active = false
		tabs[active_tab].button.add_theme_stylebox_override("normal", TAB_DEFAULT)
		tabs[active_tab].button.add_theme_stylebox_override("pressed", TAB_DEFAULT)
		tabs[active_tab].button.add_theme_stylebox_override("hover", TAB_HOVER_DEFAULT)
		tabs[active_tab].gradient_texture.texture = TAB_GRADIENT_DEFAULT
		if tabs[active_tab].background_panel:
			tabs[active_tab].background_panel.visible = false
	
	tabs[index].is_active = true
	tabs[index].button.add_theme_stylebox_override("normal", TAB_NORMAL)
	tabs[index].button.add_theme_stylebox_override("pressed", TAB_NORMAL)
	tabs[index].button.add_theme_stylebox_override("hover", TAB_NORMAL)
	tabs[index].gradient_texture.texture = TAB_GRADIENT
	tabs[index].show_content()
	
	if not tabs[index].website_container:
		if main:
			trigger_init_scene(tabs[index])
	
	active_tab = index
	
	if main and main.search_bar:
		if tabs[index].has_content:
			main.current_domain = tabs[index].current_url
			var display_text = main.current_domain
			if display_text.begins_with("gurt://"):
				display_text = display_text.substr(7)
			main.search_bar.text = display_text
		else:
			main.current_domain = ""
			main.search_bar.text = ""
			main.search_bar.grab_focus()
		
		main.update_navigation_buttons()

func create_tab() -> void:
	var index = tabs.size();
	var tab = TAB.instantiate()
	tabs.append(tab)
	h_box_container.add_child(tab)
	tab.tab_pressed.connect(_tab_pressed.bind(index))
	tab.tab_closed.connect(_tab_closed.bind(index))
	var viewport_width = get_viewport().get_visible_rect().size.x
	var available_width = viewport_width - POPUP_BUTTON_WIDTH - NEW_TAB_BUTTON_WIDTH - OTHER_UI_PADDING
	var visible_count = calculate_visible_tab_count(available_width)
	var tab_width = calculate_tab_width(available_width, visible_count)
	
	tab.play_appear_animation(tab_width)

	set_active_tab(index)
	
	await get_tree().process_frame
	update_tab_widths()
	
	trigger_init_scene(tab)
	
	var startup_behavior = main.get_startup_behavior()
	if startup_behavior.specific_page and not startup_behavior.url.is_empty():
		main._on_search_submitted(startup_behavior.url, true)
	else:
		main.render()

func _input(_event: InputEvent) -> void:
	if Input.is_action_just_pressed("NewTab"):
		create_tab()
	if Input.is_action_just_pressed("CloseTab"):
		tabs[active_tab]._on_close_button_pressed()
	if Input.is_action_just_pressed("NextTab"):
		var next_tab = (active_tab + 1) % tabs.size()
		set_active_tab(next_tab)
	if Input.is_action_just_pressed("PreviousTab"):
		var prev_tab = (active_tab - 1 + tabs.size()) % tabs.size()
		set_active_tab(prev_tab - 1)
	if Input.is_action_just_pressed("FocusSearch"):
		main.search_bar.grab_focus()
		main.search_bar.select_all()
	if Input.is_action_just_pressed("ReloadPage"):
		main.reload_current_page()

func _on_new_tab_button_pressed() -> void:
	create_tab()
