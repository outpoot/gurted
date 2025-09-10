class_name Trace
extends RefCounted

signal log_message(message: String, level: String, timestamp: float)

enum LogLevel {
	LOG,
	WARNING, 
	ERROR
}

static var _instance: Trace
static var _messages: Array[Dictionary] = []

static func get_instance() -> Trace:
	if not _instance:
		_instance = Trace.new()
	return _instance

static func trace_log(message: String) -> void:
	_emit_message(message, "log")

static func trace_warning(message: String) -> void:
	_emit_message(message, "warning")

static func trace_error(message: String) -> void:
	_emit_message(message, "error")

static func _emit_message(message: String, level: String) -> void:
	var timestamp = Time.get_ticks_msec() / 1000.0
	var log_entry = {
		"message": message,
		"level": level,
		"timestamp": timestamp
	}
	
	_messages.append(log_entry)
	get_instance().call_deferred("emit_signal", "log_message", message, level, timestamp)
	
	match level:
		"log":
			print("TRACE LOG: ", message)
		"warning":
			print("TRACE WARNING: ", message)
		"error":
			print("TRACE ERROR: ", message)

static func get_all_messages() -> Array[Dictionary]:
	return _messages.duplicate()

static func clear_messages() -> void:
	_messages.clear()

static func _lua_trace_log_handler(vm: LuauVM) -> int:
	var message = LuaPrintUtils.lua_value_to_string(vm, 1)
	vm.lua_getglobal("_trace_log")
	vm.lua_pushstring(message)
	vm.lua_call(1, 0)
	return 0

static func _lua_trace_warn_handler(vm: LuauVM) -> int:
	var message = LuaPrintUtils.lua_value_to_string(vm, 1)
	vm.lua_getglobal("_trace_warning")
	vm.lua_pushstring(message)
	vm.lua_call(1, 0)
	return 0

static func _lua_trace_error_handler(vm: LuauVM) -> int:
	var message = LuaPrintUtils.lua_value_to_string(vm, 1)
	vm.lua_getglobal("_trace_error")
	vm.lua_pushstring(message)
	vm.lua_call(1, 0)
	return 0

static func setup_trace_api(vm: LuauVM) -> void:
	vm.lua_newtable()
	
	vm.lua_pushcallable(_lua_trace_log_handler, "trace.log")
	vm.lua_setfield(-2, "log")
	
	vm.lua_pushcallable(_lua_trace_warn_handler, "trace.warn")
	vm.lua_setfield(-2, "warn")
	
	vm.lua_pushcallable(_lua_trace_error_handler, "trace.error")
	vm.lua_setfield(-2, "error")
	
	vm.lua_setglobal("trace")
