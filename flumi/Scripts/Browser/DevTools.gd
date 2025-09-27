extends Control

@onready var console: DevToolsConsole = $DevTools/TabContainer/Console
@onready var elements_tab: ElementsTab = $DevTools/TabContainer/Elements
@onready var sources_tab: SourcesTab = $DevTools/TabContainer/Sources
@onready var application_tab: ApplicationTab = $DevTools/TabContainer/Application
@onready var tab_container: TabContainer = $DevTools/TabContainer

var current_tab: Tab = null

func _ready():
	connect_console_signals()
	tab_container.tab_selected.connect(_on_tab_selected)

func connect_console_signals():
	if console:
		Trace.get_instance().log_message.connect(_on_trace_log_message)

func get_console() -> DevToolsConsole:
	return console

func get_elements_tab() -> ElementsTab:
	return elements_tab

func _on_trace_log_message(message: String, level: String, timestamp: float):
	if console:
		console.add_log_entry(message, level, timestamp)

func _on_tab_selected(tab_index: int):
	if tab_index == 0 and elements_tab:
		update_elements_tab()
		elements_tab.update_elements_tree()
	elif tab_index == 2 and sources_tab:
		update_sources_tab()
		sources_tab.update_file_tree()
	elif tab_index == 4 and application_tab:
		update_application_tab()

func update_elements_tab():
	var main_scene = Engine.get_main_loop().current_scene
	if main_scene and main_scene.has_method("get_active_tab"):
		var active_tab = main_scene.get_active_tab()
		if active_tab != current_tab:
			current_tab = active_tab
			if elements_tab:
				elements_tab.set_current_tab(active_tab)
				elements_tab.update_elements_tree()

func update_sources_tab():
	var main_scene = Engine.get_main_loop().current_scene
	if main_scene and main_scene.has_method("get_active_tab"):
		var active_tab = main_scene.get_active_tab()
		if active_tab != current_tab:
			current_tab = active_tab
			if sources_tab:
				sources_tab.set_current_tab(active_tab)
				sources_tab.refresh_sources()

func update_application_tab():
	var main_scene = Engine.get_main_loop().current_scene
	if main_scene and main_scene.has_method("get_active_tab"):
		var active_tab = main_scene.get_active_tab()
		if active_tab != current_tab:
			current_tab = active_tab
			if application_tab:
				application_tab.set_current_tab(active_tab)

func _on_close_button_pressed():
	if elements_tab:
		elements_tab.clear_highlight()
	Engine.get_main_loop().current_scene._toggle_dev_tools()
