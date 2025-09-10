class_name LuaCanvasUtils
extends RefCounted

# This file mainly creates operations that are handled by canvas.gd

static var pending_operations: Dictionary = {}
static var batch_timer: SceneTreeTimer = null

static func emit_canvas_operation(lua_api: LuaAPI, operation: Dictionary) -> void:
	var element_id = operation.get("element_id", "")
	
	if not pending_operations.has(element_id):
		pending_operations[element_id] = []
	
	pending_operations[element_id].append(operation)
	
	if not batch_timer or batch_timer.time_left <= 0:
		var scene_tree = lua_api.get_tree() if lua_api else Engine.get_main_loop()
		if scene_tree:
			batch_timer = scene_tree.create_timer(0.001) # 1ms batch window
			batch_timer.timeout.connect(_flush_pending_operations.bind(lua_api))

static func _flush_pending_operations(lua_api: LuaAPI) -> void:
	if not lua_api or not lua_api.is_inside_tree():
		pending_operations.clear()
		return
	
	for element_id in pending_operations:
		var operations = pending_operations[element_id]
		for operation in operations:
			lua_api.threaded_vm.call_deferred("_emit_dom_operation_request", operation)
	
	pending_operations.clear()
	batch_timer = null

static func _element_withContext_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		vm.lua_pushnil()
		return 1
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var context_type: String = vm.luaL_checkstring(2)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	vm.lua_getfield(1, "_tag_name")
	var tag_name: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	# Only works on canvas elements
	if tag_name != "canvas":
		vm.lua_pushnil()
		return 1
	
	vm.lua_newtable()
	vm.lua_pushstring(element_id)
	vm.lua_setfield(-2, "_element_id")
	vm.lua_pushstring(context_type)
	vm.lua_setfield(-2, "_context_type")
	
	match context_type:
		"2d":
			add_2d_context_methods(vm, lua_api)
		"shader":
			add_shader_context_methods(vm, lua_api)
	
	return 1

static func add_2d_context_methods(vm: LuauVM, lua_api: LuaAPI):
	vm.set_meta("lua_api", lua_api)
	
	# Basic drawing functions
	vm.lua_pushcallable(_2d_fillRect_wrapper, "context.fillRect")
	vm.lua_setfield(-2, "fillRect")
	
	vm.lua_pushcallable(_2d_strokeRect_wrapper, "context.strokeRect")
	vm.lua_setfield(-2, "strokeRect")
	
	vm.lua_pushcallable(_2d_clearRect_wrapper, "context.clearRect")
	vm.lua_setfield(-2, "clearRect")
	
	vm.lua_pushcallable(_2d_drawCircle_wrapper, "context.drawCircle")
	vm.lua_setfield(-2, "drawCircle")
	
	vm.lua_pushcallable(_2d_drawText_wrapper, "context.drawText")
	vm.lua_setfield(-2, "drawText")
	
	# Path-based drawing functions
	vm.lua_pushcallable(_2d_beginPath_wrapper, "context.beginPath")
	vm.lua_setfield(-2, "beginPath")
	
	vm.lua_pushcallable(_2d_closePath_wrapper, "context.closePath")
	vm.lua_setfield(-2, "closePath")
	
	vm.lua_pushcallable(_2d_moveTo_wrapper, "context.moveTo")
	vm.lua_setfield(-2, "moveTo")
	
	vm.lua_pushcallable(_2d_lineTo_wrapper, "context.lineTo")
	vm.lua_setfield(-2, "lineTo")
	
	vm.lua_pushcallable(_2d_arc_wrapper, "context.arc")
	vm.lua_setfield(-2, "arc")
	
	vm.lua_pushcallable(_2d_stroke_wrapper, "context.stroke")
	vm.lua_setfield(-2, "stroke")
	
	vm.lua_pushcallable(_2d_fill_wrapper, "context.fill")
	vm.lua_setfield(-2, "fill")
	
	# Transformation functions
	vm.lua_pushcallable(_2d_save_wrapper, "context.save")
	vm.lua_setfield(-2, "save")
	
	vm.lua_pushcallable(_2d_restore_wrapper, "context.restore")
	vm.lua_setfield(-2, "restore")
	
	vm.lua_pushcallable(_2d_translate_wrapper, "context.translate")
	vm.lua_setfield(-2, "translate")
	
	vm.lua_pushcallable(_2d_rotate_wrapper, "context.rotate")
	vm.lua_setfield(-2, "rotate")
	
	vm.lua_pushcallable(_2d_scale_wrapper, "context.scale")
	vm.lua_setfield(-2, "scale")
	
	# Advanced drawing functions
	vm.lua_pushcallable(_2d_quadraticCurveTo_wrapper, "context.quadraticCurveTo")
	vm.lua_setfield(-2, "quadraticCurveTo")
	
	vm.lua_pushcallable(_2d_bezierCurveTo_wrapper, "context.bezierCurveTo")
	vm.lua_setfield(-2, "bezierCurveTo")
	
	# Style property setters
	vm.lua_pushcallable(_2d_setStrokeStyle_wrapper, "context.setStrokeStyle")
	vm.lua_setfield(-2, "setStrokeStyle")
	
	vm.lua_pushcallable(_2d_setFillStyle_wrapper, "context.setFillStyle")
	vm.lua_setfield(-2, "setFillStyle")
	
	vm.lua_pushcallable(_2d_setLineWidth_wrapper, "context.setLineWidth")
	vm.lua_setfield(-2, "setLineWidth")
	
	vm.lua_pushcallable(_2d_setFont_wrapper, "context.setFont")
	vm.lua_setfield(-2, "setFont")
	
	# Text measurement
	vm.lua_pushcallable(_2d_measureText_wrapper, "context.measureText")
	vm.lua_setfield(-2, "measureText")

static func add_shader_context_methods(vm: LuauVM, lua_api: LuaAPI):
	vm.set_meta("lua_api", lua_api)
	
	vm.lua_pushcallable(_shader_source_wrapper, "context.source")
	vm.lua_setfield(-2, "source")

static func _2d_fillRect_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var x: float = vm.luaL_checknumber(2)
	var y: float = vm.luaL_checknumber(3)
	var width: float = vm.luaL_checknumber(4)
	var height: float = vm.luaL_checknumber(5)
	var color: String = ""
	
	if vm.lua_gettop() >= 6:
		color = vm.luaL_checkstring(6)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "canvas_fillRect",
		"element_id": element_id,
		"x": x,
		"y": y,
		"width": width,
		"height": height,
		"color": color
	}
	
	emit_canvas_operation(lua_api, operation)
	
	return 0

static func _2d_strokeRect_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var x: float = vm.luaL_checknumber(2)
	var y: float = vm.luaL_checknumber(3)
	var width: float = vm.luaL_checknumber(4)
	var height: float = vm.luaL_checknumber(5)
	var color: String = ""
	var stroke_width: float = 0.0
	
	if vm.lua_gettop() >= 6:
		color = vm.luaL_checkstring(6)
	if vm.lua_gettop() >= 7:
		stroke_width = vm.luaL_checknumber(7)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "canvas_strokeRect",
		"element_id": element_id,
		"x": x,
		"y": y,
		"width": width,
		"height": height,
		"color": color,
		"stroke_width": stroke_width
	}
	
	emit_canvas_operation(lua_api, operation)
	
	return 0

static func _2d_clearRect_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var x: float = vm.luaL_checknumber(2)
	var y: float = vm.luaL_checknumber(3)
	var width: float = vm.luaL_checknumber(4)
	var height: float = vm.luaL_checknumber(5)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "canvas_clearRect",
		"element_id": element_id,
		"x": x,
		"y": y,
		"width": width,
		"height": height
	}
	
	emit_canvas_operation(lua_api, operation)
	
	return 0

static func _2d_drawCircle_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var x: float = vm.luaL_checknumber(2)
	var y: float = vm.luaL_checknumber(3)
	var radius: float = vm.luaL_checknumber(4)
	var color: String = "#000000"
	var filled: bool = true
	
	if vm.lua_gettop() >= 5:
		color = vm.luaL_checkstring(5)
	if vm.lua_gettop() >= 6:
		filled = vm.lua_toboolean(6)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "canvas_drawCircle",
		"element_id": element_id,
		"x": x,
		"y": y,
		"radius": radius,
		"color": color,
		"filled": filled
	}
	
	emit_canvas_operation(lua_api, operation)
	
	return 0

static func _2d_drawText_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var x: float = vm.luaL_checknumber(2)
	var y: float = vm.luaL_checknumber(3)
	var text: String = vm.luaL_checkstring(4)
	var font_name: String = "default"
	var color: String = "#000000"
	
	if vm.lua_gettop() >= 5:
		font_name = vm.luaL_checkstring(5)
	if vm.lua_gettop() >= 6:
		color = vm.luaL_checkstring(6)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "canvas_drawText",
		"element_id": element_id,
		"x": x,
		"y": y,
		"text": text,
		"font_name": font_name,
		"color": color
	}
	
	emit_canvas_operation(lua_api, operation)
	
	return 0

static func _shader_source_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var shader_code: String = vm.luaL_checkstring(2)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "canvas_source",
		"element_id": element_id,
		"shader_code": shader_code
	}
	
	emit_canvas_operation(lua_api, operation)
	
	return 0

# Path-based drawing wrappers
static func _2d_beginPath_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "canvas_beginPath",
		"element_id": element_id
	}
	
	emit_canvas_operation(lua_api, operation)
	return 0

static func _2d_closePath_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "canvas_closePath",
		"element_id": element_id
	}
	
	emit_canvas_operation(lua_api, operation)
	return 0

static func _2d_moveTo_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var x: float = vm.luaL_checknumber(2)
	var y: float = vm.luaL_checknumber(3)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "canvas_moveTo",
		"element_id": element_id,
		"x": x,
		"y": y
	}
	
	emit_canvas_operation(lua_api, operation)
	return 0

static func _2d_lineTo_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var x: float = vm.luaL_checknumber(2)
	var y: float = vm.luaL_checknumber(3)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "canvas_lineTo",
		"element_id": element_id,
		"x": x,
		"y": y
	}
	
	emit_canvas_operation(lua_api, operation)
	return 0

static func _2d_arc_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var x: float = vm.luaL_checknumber(2)
	var y: float = vm.luaL_checknumber(3)
	var radius: float = vm.luaL_checknumber(4)
	var start_angle: float = vm.luaL_checknumber(5)
	var end_angle: float = vm.luaL_checknumber(6)
	var counterclockwise: bool = false
	
	if vm.lua_gettop() >= 7:
		counterclockwise = vm.lua_toboolean(7)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "canvas_arc",
		"element_id": element_id,
		"x": x,
		"y": y,
		"radius": radius,
		"start_angle": start_angle,
		"end_angle": end_angle,
		"counterclockwise": counterclockwise
	}
	
	emit_canvas_operation(lua_api, operation)
	return 0

static func _2d_stroke_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "canvas_stroke",
		"element_id": element_id
	}
	
	emit_canvas_operation(lua_api, operation)
	return 0

static func _2d_fill_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "canvas_fill",
		"element_id": element_id
	}
	
	emit_canvas_operation(lua_api, operation)
	return 0

# Transformation wrappers
static func _2d_save_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "canvas_save",
		"element_id": element_id
	}
	
	emit_canvas_operation(lua_api, operation)
	return 0

static func _2d_restore_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "canvas_restore",
		"element_id": element_id
	}
	
	emit_canvas_operation(lua_api, operation)
	return 0

static func _2d_translate_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var x: float = vm.luaL_checknumber(2)
	var y: float = vm.luaL_checknumber(3)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "canvas_translate",
		"element_id": element_id,
		"x": x,
		"y": y
	}
	
	emit_canvas_operation(lua_api, operation)
	return 0

static func _2d_rotate_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var angle: float = vm.luaL_checknumber(2)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "canvas_rotate",
		"element_id": element_id,
		"angle": angle
	}
	
	emit_canvas_operation(lua_api, operation)
	return 0

static func _2d_scale_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var x: float = vm.luaL_checknumber(2)
	var y: float = vm.luaL_checknumber(3)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "canvas_scale",
		"element_id": element_id,
		"x": x,
		"y": y
	}
	
	emit_canvas_operation(lua_api, operation)
	return 0

# Advanced drawing wrappers
static func _2d_quadraticCurveTo_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var cpx: float = vm.luaL_checknumber(2)
	var cpy: float = vm.luaL_checknumber(3)
	var x: float = vm.luaL_checknumber(4)
	var y: float = vm.luaL_checknumber(5)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "canvas_quadraticCurveTo",
		"element_id": element_id,
		"cpx": cpx,
		"cpy": cpy,
		"x": x,
		"y": y
	}
	
	emit_canvas_operation(lua_api, operation)
	return 0

static func _2d_bezierCurveTo_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var cp1x: float = vm.luaL_checknumber(2)
	var cp1y: float = vm.luaL_checknumber(3)
	var cp2x: float = vm.luaL_checknumber(4)
	var cp2y: float = vm.luaL_checknumber(5)
	var x: float = vm.luaL_checknumber(6)
	var y: float = vm.luaL_checknumber(7)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "canvas_bezierCurveTo",
		"element_id": element_id,
		"cp1x": cp1x,
		"cp1y": cp1y,
		"cp2x": cp2x,
		"cp2y": cp2y,
		"x": x,
		"y": y
	}
	
	emit_canvas_operation(lua_api, operation)
	return 0

# Style property wrappers
static func _2d_setStrokeStyle_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var style: String = vm.luaL_checkstring(2)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "canvas_setStrokeStyle",
		"element_id": element_id,
		"style": style
	}
	
	emit_canvas_operation(lua_api, operation)
	return 0

static func _2d_setFillStyle_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var style: String = vm.luaL_checkstring(2)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "canvas_setFillStyle",
		"element_id": element_id,
		"style": style
	}
	
	emit_canvas_operation(lua_api, operation)
	return 0

static func _2d_setLineWidth_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var width: float = vm.luaL_checknumber(2)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "canvas_setLineWidth",
		"element_id": element_id,
		"width": width
	}
	
	emit_canvas_operation(lua_api, operation)
	return 0

static func _2d_setFont_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		return 0
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var font: String = vm.luaL_checkstring(2)
	
	vm.lua_getfield(1, "_element_id")
	var element_id: String = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var operation = {
		"type": "canvas_setFont",
		"element_id": element_id,
		"font": font
	}
	
	emit_canvas_operation(lua_api, operation)
	return 0

# TODO: should probably cache and async this, could lag otherwise if called looped
static func _2d_measureText_wrapper(vm: LuauVM) -> int:
	var lua_api = vm.get_meta("lua_api") as LuaAPI
	if not lua_api:
		vm.lua_pushnil()
		return 1
	
	vm.luaL_checktype(1, vm.LUA_TTABLE)
	var text: String = vm.luaL_checkstring(2)
	
	vm.lua_getfield(1, "_element_id")
	var element_id = vm.lua_tostring(-1)
	vm.lua_pop(1)
	
	var dom_parser = lua_api.dom_parser
	var dom_node = get_canvas_node_main_thread(dom_parser, element_id)
	var actual_width = text.length() * 10 # Fallback estimate
	
	if dom_node and dom_node.has_method("withContext"):
		var context = dom_node.withContext("2d")
		if context and context.has_method("measureText"):
			var metrics = context.measureText(text)
			if metrics and metrics.has("width"):
				actual_width = metrics.width
	
	vm.lua_newtable()
	vm.lua_pushnumber(actual_width)
	vm.lua_setfield(-2, "width")
	
	return 1

static func handle_canvas_fillRect(operation: Dictionary, dom_parser: HTMLParser) -> void:
	var element_id: String = operation.element_id
	var x: float = operation.x
	var y: float = operation.y
	var width: float = operation.width
	var height: float = operation.height
	var color: String = operation.color
	
	var dom_node = get_canvas_node_main_thread(dom_parser, element_id)
	if dom_node and dom_node.has_method("withContext"):
		var context = dom_node.withContext("2d")
		if context:
			context.fillRect(x, y, width, height, color)

static func handle_canvas_strokeRect(operation: Dictionary, dom_parser: HTMLParser) -> void:
	var element_id: String = operation.element_id
	var x: float = operation.x
	var y: float = operation.y
	var width: float = operation.width
	var height: float = operation.height
	var color: String = operation.color
	var stroke_width: float = operation.get("stroke_width", 1.0)
	
	var dom_node = get_canvas_node_main_thread(dom_parser, element_id)
	if dom_node and dom_node.has_method("withContext"):
		var context = dom_node.withContext("2d")
		if context:
			context.strokeRect(x, y, width, height, color, stroke_width)

static func handle_canvas_clearRect(operation: Dictionary, dom_parser: HTMLParser) -> void:
	var element_id: String = operation.element_id
	var x: float = operation.x
	var y: float = operation.y
	var width: float = operation.width
	var height: float = operation.height
	
	var dom_node = get_canvas_node_main_thread(dom_parser, element_id)
	if dom_node and dom_node.has_method("withContext"):
		var context = dom_node.withContext("2d")
		if context:
			context.clearRect(x, y, width, height)

static func handle_canvas_drawCircle(operation: Dictionary, dom_parser: HTMLParser) -> void:
	var element_id: String = operation.element_id
	var x: float = operation.x
	var y: float = operation.y
	var radius: float = operation.radius
	var color: String = operation.color
	var filled: bool = operation.get("filled", true)
	
	var dom_node = get_canvas_node_main_thread(dom_parser, element_id)
	if dom_node and dom_node.has_method("withContext"):
		var context = dom_node.withContext("2d")
		if context:
			context.drawCircle(x, y, radius, color, filled)

static func handle_canvas_drawText(operation: Dictionary, dom_parser: HTMLParser) -> void:
	var element_id: String = operation.element_id
	var x: float = operation.x
	var y: float = operation.y
	var text: String = operation.text
	var color: String = operation.color
	
	var dom_node = get_canvas_node_main_thread(dom_parser, element_id)
	if dom_node and dom_node.has_method("withContext"):
		var context = dom_node.withContext("2d")
		if context:
			context.drawText(x, y, text, color)

static func handle_canvas_source(operation: Dictionary, dom_parser: HTMLParser) -> void:
	var element_id: String = operation.element_id
	var shader_code: String = operation.shader_code
	
	var dom_node = get_canvas_node_main_thread(dom_parser, element_id)
	if dom_node and dom_node.has_method("withContext"):
		var context = dom_node.withContext("shader")
		if context:
			context.source(shader_code)

static func handle_canvas_beginPath(operation: Dictionary, dom_parser: HTMLParser) -> void:
	var element_id: String = operation.element_id
	var dom_node = get_canvas_node_main_thread(dom_parser, element_id)
	if dom_node and dom_node.has_method("withContext"):
		var context = dom_node.withContext("2d")
		if context:
			context.beginPath()

static func handle_canvas_closePath(operation: Dictionary, dom_parser: HTMLParser) -> void:
	var element_id: String = operation.element_id
	var dom_node = get_canvas_node_main_thread(dom_parser, element_id)
	if dom_node and dom_node.has_method("withContext"):
		var context = dom_node.withContext("2d")
		if context:
			context.closePath()

static func handle_canvas_moveTo(operation: Dictionary, dom_parser: HTMLParser) -> void:
	var element_id: String = operation.element_id
	var x: float = operation.x
	var y: float = operation.y
	var dom_node = get_canvas_node_main_thread(dom_parser, element_id)
	if dom_node and dom_node.has_method("withContext"):
		var context = dom_node.withContext("2d")
		if context:
			context.moveTo(x, y)

static func handle_canvas_lineTo(operation: Dictionary, dom_parser: HTMLParser) -> void:
	var element_id: String = operation.element_id
	var x: float = operation.x
	var y: float = operation.y
	var dom_node = get_canvas_node_main_thread(dom_parser, element_id)
	if dom_node and dom_node.has_method("withContext"):
		var context = dom_node.withContext("2d")
		if context:
			context.lineTo(x, y)

static func handle_canvas_arc(operation: Dictionary, dom_parser: HTMLParser) -> void:
	var element_id: String = operation.element_id
	var x: float = operation.x
	var y: float = operation.y
	var radius: float = operation.radius
	var start_angle: float = operation.start_angle
	var end_angle: float = operation.end_angle
	var counterclockwise: bool = operation.get("counterclockwise", false)
	var dom_node = get_canvas_node_main_thread(dom_parser, element_id)
	if dom_node and dom_node.has_method("withContext"):
		var context = dom_node.withContext("2d")
		if context:
			context.arc(x, y, radius, start_angle, end_angle, counterclockwise)

static func handle_canvas_stroke(operation: Dictionary, dom_parser: HTMLParser) -> void:
	var element_id: String = operation.element_id
	var dom_node = get_canvas_node_main_thread(dom_parser, element_id)
	if dom_node and dom_node.has_method("withContext"):
		var context = dom_node.withContext("2d")
		if context:
			context.stroke()

static func handle_canvas_fill(operation: Dictionary, dom_parser: HTMLParser) -> void:
	var element_id: String = operation.element_id
	var dom_node = get_canvas_node_main_thread(dom_parser, element_id)
	if dom_node and dom_node.has_method("withContext"):
		var context = dom_node.withContext("2d")
		if context:
			context.fill()

static func handle_canvas_save(operation: Dictionary, dom_parser: HTMLParser) -> void:
	var element_id: String = operation.element_id
	var dom_node = get_canvas_node_main_thread(dom_parser, element_id)
	if dom_node and dom_node.has_method("withContext"):
		var context = dom_node.withContext("2d")
		if context:
			context.save()

static func handle_canvas_restore(operation: Dictionary, dom_parser: HTMLParser) -> void:
	var element_id: String = operation.element_id
	var dom_node = get_canvas_node_main_thread(dom_parser, element_id)
	if dom_node and dom_node.has_method("withContext"):
		var context = dom_node.withContext("2d")
		if context:
			context.restore()

static func handle_canvas_translate(operation: Dictionary, dom_parser: HTMLParser) -> void:
	var element_id: String = operation.element_id
	var x: float = operation.x
	var y: float = operation.y
	var dom_node = get_canvas_node_main_thread(dom_parser, element_id)
	if dom_node and dom_node.has_method("withContext"):
		var context = dom_node.withContext("2d")
		if context:
			context.translate(x, y)

static func handle_canvas_rotate(operation: Dictionary, dom_parser: HTMLParser) -> void:
	var element_id: String = operation.element_id
	var angle: float = operation.angle
	var dom_node = get_canvas_node_main_thread(dom_parser, element_id)
	if dom_node and dom_node.has_method("withContext"):
		var context = dom_node.withContext("2d")
		if context:
			context.rotate(angle)

static func handle_canvas_scale(operation: Dictionary, dom_parser: HTMLParser) -> void:
	var element_id: String = operation.element_id
	var x: float = operation.x
	var y: float = operation.y
	var dom_node = get_canvas_node_main_thread(dom_parser, element_id)
	if dom_node and dom_node.has_method("withContext"):
		var context = dom_node.withContext("2d")
		if context:
			context.scale(x, y)

static func handle_canvas_quadraticCurveTo(operation: Dictionary, dom_parser: HTMLParser) -> void:
	var element_id: String = operation.element_id
	var cpx: float = operation.cpx
	var cpy: float = operation.cpy
	var x: float = operation.x
	var y: float = operation.y
	var dom_node = get_canvas_node_main_thread(dom_parser, element_id)
	if dom_node and dom_node.has_method("withContext"):
		var context = dom_node.withContext("2d")
		if context:
			context.quadraticCurveTo(cpx, cpy, x, y)

static func handle_canvas_bezierCurveTo(operation: Dictionary, dom_parser: HTMLParser) -> void:
	var element_id: String = operation.element_id
	var cp1x: float = operation.cp1x
	var cp1y: float = operation.cp1y
	var cp2x: float = operation.cp2x
	var cp2y: float = operation.cp2y
	var x: float = operation.x
	var y: float = operation.y
	var dom_node = get_canvas_node_main_thread(dom_parser, element_id)
	if dom_node and dom_node.has_method("withContext"):
		var context = dom_node.withContext("2d")
		if context:
			context.bezierCurveTo(cp1x, cp1y, cp2x, cp2y, x, y)

static func handle_canvas_setStrokeStyle(operation: Dictionary, dom_parser: HTMLParser) -> void:
	var element_id: String = operation.element_id
	var style: String = operation.style
	var dom_node = get_canvas_node_main_thread(dom_parser, element_id)
	if dom_node and dom_node.has_method("withContext"):
		var context = dom_node.withContext("2d")
		if context:
			context.stroke_style = style

static func handle_canvas_setFillStyle(operation: Dictionary, dom_parser: HTMLParser) -> void:
	var element_id: String = operation.element_id
	var style: String = operation.style
	var dom_node = get_canvas_node_main_thread(dom_parser, element_id)
	if dom_node and dom_node.has_method("withContext"):
		var context = dom_node.withContext("2d")
		if context:
			context.fill_style = style

static func handle_canvas_setLineWidth(operation: Dictionary, dom_parser: HTMLParser) -> void:
	var element_id: String = operation.element_id
	var width: float = operation.width
	var dom_node = get_canvas_node_main_thread(dom_parser, element_id)
	if dom_node and dom_node.has_method("withContext"):
		var context = dom_node.withContext("2d")
		if context:
			context.line_width = width

static func handle_canvas_setFont(operation: Dictionary, dom_parser: HTMLParser) -> void:
	var element_id: String = operation.element_id
	var font: String = operation.font
	var dom_node = get_canvas_node_main_thread(dom_parser, element_id)
	if dom_node and dom_node.has_method("withContext"):
		var context = dom_node.withContext("2d")
		if context:
			context.font = font

static func get_canvas_node_main_thread(dom_parser: HTMLParser, element_id: String) -> Node:
	var dom_node = dom_parser.parse_result.dom_nodes.get(element_id, null)
	if not dom_node:
		return null
	
	if dom_node is MarginContainer and dom_node.get_child_count() > 0:
		dom_node = dom_node.get_child(0)
	
	return dom_node
