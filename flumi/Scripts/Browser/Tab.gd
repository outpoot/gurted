class_name Tab
extends Control

signal tab_pressed
signal tab_closed

@onready var gradient_texture: TextureRect = %GradientTexture
@onready var button: Button = %Button
@onready var close_button: Button = %CloseButton
@onready var icon: TextureRect = %Icon
@onready var animation: AnimationPlayer = $AnimationPlayer
var appear_tween: Tween

const TAB_GRADIENT: GradientTexture2D = preload("res://Scenes/Styles/TabGradient.tres")
const TAB_GRADIENT_DEFAULT: GradientTexture2D = preload("res://Scenes/Styles/TabGradientDefault.tres")
const TAB_GRADIENT_INACTIVE: GradientTexture2D = preload("res://Scenes/Styles/TabGradientInactive.tres")

const TAB_HOVER: StyleBoxFlat = preload("res://Scenes/Styles/TabHover.tres")
const TAB_DEFAULT: StyleBoxFlat = preload("res://Scenes/Styles/TabDefault.tres")
const CLOSE_BUTTON_HOVER: StyleBoxFlat = preload("res://Scenes/Styles/CloseButtonHover.tres")
const CLOSE_BUTTON_NORMAL: StyleBoxFlat = preload("res://Scenes/Styles/CloseButtonNormal.tres")

const CLOSE_BUTTON_HIDE_THRESHOLD := 100
const TEXT_HIDE_THRESHOLD := 50
const GRADIENT_WIDTH := 64
const GRADIENT_OFFSET := 72
const CLOSE_BUTTON_OFFSET := 34
const ICON_OFFSET := 8
const APPEAR_ANIMATION_DURATION := 0.25

var is_active := false
var mouse_over_tab := false
var loading_tween: Tween

var scroll_container: ScrollContainer = null
var website_container: VBoxContainer = null
var background_panel: PanelContainer = null
var main_hbox: HSplitContainer = null
var dev_tools: Control = null
var dev_tools_visible: bool = false
var lua_apis: Array[LuaAPI] = []
var current_url: String = ""
var has_content: bool = false
var navigation_history: Array[String] = []
var history_index: int = -1

func _ready():
	add_to_group("tabs")
	gradient_texture.texture = gradient_texture.texture.duplicate()
	gradient_texture.texture.gradient = gradient_texture.texture.gradient.duplicate()

func _process(_delta):
	# NOTE: probably very inefficient
	if mouse_over_tab:
		var mouse_pos = get_global_mouse_position()
		var close_button_rect = Rect2(close_button.global_position, close_button.size * close_button.scale)
		
		if close_button_rect.has_point(mouse_pos):
			close_button.add_theme_stylebox_override("normal", CLOSE_BUTTON_HOVER)
		else:
			close_button.add_theme_stylebox_override("normal", CLOSE_BUTTON_NORMAL)

func set_title(title: String) -> void:
	button.text = title
	button.set_meta("original_text", title)

func set_icon(new_icon: Texture) -> void:
	icon.texture = new_icon
	icon.rotation = 0

func update_icon_from_url(icon_url: String) -> void:
	if icon_url.is_empty():
		const GLOBE_ICON = preload("res://Assets/Icons/globe.svg")
		set_icon(GLOBE_ICON)
		remove_meta("original_icon_url")
		return
	
	set_meta("original_icon_url", icon_url)
	
	var icon_resource = await Network.fetch_image(icon_url)
	
	if is_instance_valid(self) and icon_resource:
		set_icon(icon_resource)
	elif is_instance_valid(self):
		const GLOBE_ICON = preload("res://Assets/Icons/globe.svg")
		set_icon(GLOBE_ICON)

func _on_button_mouse_entered() -> void:
	mouse_over_tab = true
	if is_active: return
	gradient_texture.texture = TAB_GRADIENT_INACTIVE

func _on_button_mouse_exited() -> void:
	mouse_over_tab = false
	if is_active: return
	gradient_texture.texture = TAB_GRADIENT_DEFAULT

func start_loading() -> void:
	const LOADER_CIRCLE = preload("res://Assets/Icons/loader-circle.svg")
	
	stop_loading()
	
	set_icon(LOADER_CIRCLE)
	icon.pivot_offset = Vector2(11.5, 11.5)
	
	loading_tween = create_tween()
	if loading_tween:
		loading_tween.set_loops(0)
		loading_tween.tween_method(func(angle):
			if !is_instance_valid(icon): 
				if loading_tween: loading_tween.kill()
				return
			icon.rotation = angle
		, 0.0, TAU, 1.0)

func stop_loading() -> void:
	if loading_tween:
		loading_tween.kill()
		loading_tween = null

func _exit_tree():
	if loading_tween:
		loading_tween.kill()
		loading_tween = null
	
	for lua_api in lua_apis:
		if is_instance_valid(lua_api):
			lua_api.kill_script_execution()
			lua_api.queue_free()
	lua_apis.clear()
	
	if scroll_container and is_instance_valid(scroll_container):
		if scroll_container.get_parent():
			scroll_container.get_parent().remove_child(scroll_container)
		scroll_container.queue_free()
	
	if background_panel and is_instance_valid(background_panel):
		if background_panel.get_parent():
			background_panel.get_parent().remove_child.call_deferred(background_panel)
		background_panel.queue_free()
	
	if dev_tools and is_instance_valid(dev_tools):
		dev_tools.queue_free()
	
	remove_from_group("tabs")

func init_scene(parent_container: Control) -> void:
	if not scroll_container:
		background_panel = PanelContainer.new()
		background_panel.name = "Tab_Background_" + str(get_instance_id())
		background_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		background_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		var style_box = StyleBoxFlat.new()
		style_box.bg_color = Color(1, 1, 1, 1)  # White background
		background_panel.add_theme_stylebox_override("panel", style_box)
		
		main_hbox = HSplitContainer.new()
		main_hbox.name = "Tab_MainHBox_" + str(get_instance_id())
		main_hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		main_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		
		scroll_container = ScrollContainer.new()
		scroll_container.name = "Tab_ScrollContainer_" + str(get_instance_id())
		scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL # Take 2/3 of space
		
		website_container = VBoxContainer.new()
		website_container.name = "Tab_WebsiteContainer_" + str(get_instance_id())
		website_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		website_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
		website_container.add_theme_constant_override("separation", 22)
		
		var dev_tools_scene = preload("res://Scenes/DevTools.tscn")
		dev_tools = dev_tools_scene.instantiate()
		dev_tools.name = "Tab_DevTools_" + str(get_instance_id())
		dev_tools.visible = false
		
		parent_container.call_deferred("add_child", background_panel)
		background_panel.call_deferred("add_child", main_hbox)
		main_hbox.call_deferred("add_child", scroll_container)
		main_hbox.call_deferred("add_child", dev_tools)
		scroll_container.call_deferred("add_child", website_container)
		
		background_panel.visible = is_active

func show_content() -> void:
	if background_panel:
		background_panel.visible = true

func play_appear_animation(target_width: float) -> void:
	var should_hide_close = target_width < CLOSE_BUTTON_HIDE_THRESHOLD
	var should_hide_text = target_width < TEXT_HIDE_THRESHOLD
	
	close_button.visible = not should_hide_close
	button.text = "" if should_hide_text else button.get_meta("original_text", "New Tab")
	
	var should_show_gradient = not should_hide_text and not should_hide_close
	gradient_texture.visible = should_show_gradient
	
	if should_show_gradient:
		gradient_texture.size.x = GRADIENT_WIDTH
		gradient_texture.position.x = target_width - GRADIENT_OFFSET
	
	if not should_hide_close:
		close_button.position.x = target_width - CLOSE_BUTTON_OFFSET
	
	icon.position.x = ICON_OFFSET
	custom_minimum_size.x = 0.0
	size.x = 0.0
	button.custom_minimum_size.x = 0.0
	button.size.x = 0.0
	
	if appear_tween:
		appear_tween.kill()
	
	appear_tween = create_tween()
	appear_tween.set_ease(Tween.EASE_OUT)
	appear_tween.set_trans(Tween.TRANS_CUBIC)
	
	appear_tween.parallel().tween_property(self, "custom_minimum_size:x", target_width, APPEAR_ANIMATION_DURATION)
	appear_tween.parallel().tween_property(self, "size:x", target_width, APPEAR_ANIMATION_DURATION)
	appear_tween.parallel().tween_property(button, "custom_minimum_size:x", target_width, APPEAR_ANIMATION_DURATION)
	appear_tween.parallel().tween_property(button, "size:x", target_width, APPEAR_ANIMATION_DURATION)

func _on_button_pressed() -> void:
	tab_pressed.emit()

func _on_close_button_pressed() -> void:
	var close_tween = create_tween()
	close_tween.set_ease(Tween.EASE_IN)
	close_tween.set_trans(Tween.TRANS_CUBIC)
	
	close_tween.parallel().tween_property(self, "custom_minimum_size:x", 0.0, 0.15)
	close_tween.parallel().tween_property(self, "size:x", 0.0, 0.15)
	close_tween.parallel().tween_property(button, "custom_minimum_size:x", 0.0, 0.15)
	close_tween.parallel().tween_property(button, "size:x", 0.0, 0.15)
	
	await close_tween.finished
	tab_closed.emit()
	queue_free()

func toggle_dev_tools() -> void:
	if not dev_tools:
		return
		
	dev_tools_visible = not dev_tools_visible
	dev_tools.visible = dev_tools_visible
	
	if dev_tools_visible:
		scroll_container.size_flags_stretch_ratio = 2.0
		dev_tools.size_flags_stretch_ratio = 1.0
	else:
		scroll_container.size_flags_stretch_ratio = 1.0

func get_dev_tools_console() -> DevToolsConsole:
	if dev_tools and dev_tools.has_method("get_console"):
		return dev_tools.get_console()
	return null

func add_to_navigation_history(url: String) -> void:
	if url.is_empty():
		return
	
	# If we're not at the end of history, remove everything after current position
	if history_index < navigation_history.size() - 1:
		navigation_history = navigation_history.slice(0, history_index + 1)
	
	# Don't add duplicate consecutive entries
	if navigation_history.is_empty() or navigation_history[-1] != url:
		navigation_history.append(url)
		history_index = navigation_history.size() - 1

func can_go_back() -> bool:
	return history_index > 0

func can_go_forward() -> bool:
	return history_index < navigation_history.size() - 1

func go_back() -> String:
	if can_go_back():
		history_index -= 1
		return navigation_history[history_index]
	return ""

func go_forward() -> String:
	if can_go_forward():
		history_index += 1
		return navigation_history[history_index]
	return ""

func get_current_history_url() -> String:
	if history_index >= 0 and history_index < navigation_history.size():
		return navigation_history[history_index]
	return ""
