class_name HTMLCanvas
extends ColorRect

var canvas_element: HTMLParser.HTMLElement
var parser: HTMLParser
var canvas_width: int = 300
var canvas_height: int = 150
var draw_commands: Array = []
var context_2d: CanvasContext2D = null
var context_shader: CanvasContextShader = null
var pending_redraw: bool = false
var max_draw_commands: int = 1000

class CanvasContext2D:
	var canvas: HTMLCanvas
	# Drawing state
	var current_path: PackedVector2Array = PackedVector2Array()
	var path_started: bool = false
	# Style properties
	var stroke_style: String = "#000000"
	var fill_style: String = "#000000"
	var line_width: float = 1.0
	var line_cap: String = "butt"
	var line_join: String = "miter"
	var font: String = "16px sans-serif"
	var text_align: String = "start"
	var text_baseline: String = "alphabetic"
	# Transformation state
	var transform_stack: Array = []
	var current_transform: Transform2D = Transform2D.IDENTITY
	
	func _init(canvas_ref: HTMLCanvas):
		canvas = canvas_ref
	
	func fillRect(x: float, y: float, width: float, height: float, color_hex: String = ""):
		var color = _parse_color(fill_style if color_hex.is_empty() else color_hex)
		var cmd = {
			"type": "fillRect",
			"x": x,
			"y": y,
			"width": width,
			"height": height,
			"color": color,
			"transform": current_transform
		}
		canvas._add_draw_command(cmd)
	
	func strokeRect(x: float, y: float, width: float, height: float, color_hex: String = "", stroke_width: float = 0.0):
		var color = _parse_color(stroke_style if color_hex.is_empty() else color_hex)
		var width_val = line_width if stroke_width == 0.0 else stroke_width
		var cmd = {
			"type": "strokeRect",
			"x": x,
			"y": y,
			"width": width,
			"height": height,
			"color": color,
			"stroke_width": width_val,
			"transform": current_transform
		}
		canvas._add_draw_command(cmd)
	
	func clearRect(x: float, y: float, width: float, height: float):
		if x == 0 and y == 0 and width >= canvas.canvas_width and height >= canvas.canvas_height:
			canvas.draw_commands.clear()
			canvas._do_redraw()
			return
		
		var cmd = {
			"type": "clearRect",
			"x": x,
			"y": y,
			"width": width,
			"height": height
		}
		canvas._add_draw_command(cmd)
	
	func drawCircle(x: float, y: float, radius: float, color_hex: String = "#000000", filled: bool = true):
		var cmd = {
			"type": "circle",
			"x": x,
			"y": y,
			"radius": radius,
			"color": _parse_color(color_hex),
			"filled": filled,
			"transform": current_transform
		}
		canvas._add_draw_command(cmd)
	
	func drawText(x: float, y: float, text: String, color_hex: String = "#000000"):
		var color = _parse_color(fill_style if color_hex == "#000000" else color_hex)
		var cmd = {
			"type": "text",
			"x": x,
			"y": y,
			"text": text,
			"color": color,
			"font_size": _parse_font_size(font),
			"transform": current_transform
		}
		canvas._add_draw_command(cmd)
	
	# Path-based drawing functions
	func beginPath():
		current_path.clear()
		path_started = true
	
	func closePath():
		if current_path.size() > 0:
			current_path.append(current_path[0])
	
	func moveTo(x: float, y: float):
		var point = current_transform * Vector2(x, y)
		current_path.clear()
		current_path.append(point)
		path_started = true
	
	func lineTo(x: float, y: float):
		if not path_started:
			moveTo(x, y)
			return
		var point = current_transform * Vector2(x, y)
		current_path.append(point)
	
	func arc(x: float, y: float, radius: float, start_angle: float, end_angle: float, counterclockwise: bool = false):
		var segments = max(8, int(abs(end_angle - start_angle) * radius / 4))
		var angle_step = (end_angle - start_angle) / segments
		if counterclockwise:
			angle_step = -angle_step
		
		for i in range(segments + 1):
			var angle = start_angle + i * angle_step
			var point_x = x + cos(angle) * radius
			var point_y = y + sin(angle) * radius
			var point = current_transform * Vector2(point_x, point_y)
			
			if i == 0 and current_path.is_empty():
				current_path.append(point)
			else:
				current_path.append(point)
	
	func stroke():
		if current_path.size() < 2:
			return
		
		var cmd = {
			"type": "stroke_path",
			"path": current_path.duplicate(),
			"color": _parse_color(stroke_style),
			"line_width": line_width,
			"line_cap": line_cap,
			"line_join": line_join
		}
		canvas._add_draw_command(cmd)
	
	func fill():
		if current_path.size() < 3:
			return
		
		var cmd = {
			"type": "fill_path",
			"path": current_path.duplicate(),
			"color": _parse_color(fill_style)
		}
		canvas._add_draw_command(cmd)
	
	# Transformation functions
	func save():
		transform_stack.append({
			"transform": current_transform,
			"stroke_style": stroke_style,
			"fill_style": fill_style,
			"line_width": line_width,
			"line_cap": line_cap,
			"line_join": line_join,
			"font": font,
			"text_align": text_align,
			"text_baseline": text_baseline
		})
	
	func restore():
		if transform_stack.size() > 0:
			var state = transform_stack.pop_back()
			current_transform = state.transform
			stroke_style = state.stroke_style
			fill_style = state.fill_style
			line_width = state.line_width
			line_cap = state.line_cap
			line_join = state.line_join
			font = state.font
			text_align = state.text_align
			text_baseline = state.text_baseline
	
	func translate(x: float, y: float):
		current_transform = current_transform.translated(Vector2(x, y))
	
	func rotate(angle: float):
		var cos_a = cos(angle)
		var sin_a = sin(angle)
		var new_x = Vector2(
			current_transform.x.x * cos_a - current_transform.x.y * sin_a,
			current_transform.x.x * sin_a + current_transform.x.y * cos_a
		)
		var new_y = Vector2(
			current_transform.y.x * cos_a - current_transform.y.y * sin_a,
			current_transform.y.x * sin_a + current_transform.y.y * cos_a
		)
		current_transform = Transform2D(new_x, new_y, current_transform.origin)
	
	func scale(x: float, y: float):
		current_transform = Transform2D(
			current_transform.x * x,
			current_transform.y * y,
			current_transform.origin
		)
	
	# Advanced drawing functions
	func quadraticCurveTo(cpx: float, cpy: float, x: float, y: float):
		if current_path.is_empty():
			moveTo(0, 0)
		
		var start_point = current_path[current_path.size() - 1]
		var control_point = current_transform * Vector2(cpx, cpy)
		var end_point = current_transform * Vector2(x, y)
		
		# Approximate quadratic curve with line segments
		var segments = 20
		for i in range(1, segments + 1):
			var t = float(i) / segments
			var point = start_point.lerp(control_point, t).lerp(control_point.lerp(end_point, t), t)
			current_path.append(point)
	
	func bezierCurveTo(cp1x: float, cp1y: float, cp2x: float, cp2y: float, x: float, y: float):
		if current_path.is_empty():
			moveTo(0, 0)
		
		var start_point = current_path[current_path.size() - 1]
		var cp1 = current_transform * Vector2(cp1x, cp1y)
		var cp2 = current_transform * Vector2(cp2x, cp2y)
		var end_point = current_transform * Vector2(x, y)
		
		# Approximate cubic bezier with line segments
		var segments = 20
		for i in range(1, segments + 1):
			var t = float(i) / segments
			var inv_t = 1.0 - t
			var point = start_point * (inv_t * inv_t * inv_t) + \
					   cp1 * (3 * inv_t * inv_t * t) + \
					   cp2 * (3 * inv_t * t * t) + \
					   end_point * (t * t * t)
			current_path.append(point)
	
	# Style setters
	func setFont(font_str: String):
		font = font_str
	
	func setStrokeStyle(style: String):
		stroke_style = style
	
	func setFillStyle(style: String):
		fill_style = style
	
	func setLineWidth(width: float):
		line_width = width
	
	func measureText(text: String) -> Dictionary:
		var font_resource = ThemeDB.fallback_font
		var font_size = _parse_font_size(font)
		var text_size = font_resource.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		return {"width": text_size.x}
	
	func _parse_font_size(font_str: String) -> int:
		var regex = RegEx.new()
		regex.compile(r"(\d+)px")
		var result = regex.search(font_str)
		if result:
			return int(result.get_string(1))
		return 16
	
	func _parse_color(color_str: String) -> Color:
		return ColorUtils.parse_color(color_str)

class CanvasContextShader:
	var canvas: HTMLCanvas
	
	func _init(canvas_ref: HTMLCanvas):
		canvas = canvas_ref
	
	func source(shader_code: String):
		var shader = Shader.new()
		shader.code = shader_code
		
		var material = ShaderMaterial.new()
		material.shader = shader
		
		canvas.material = material

func init(element: HTMLParser.HTMLElement, _parser: HTMLParser):
	canvas_element = element
	parser = _parser
	
	var width_attr = element.get_attribute("width", "300")
	var height_attr = element.get_attribute("height", "150")
	
	canvas_width = int(width_attr)
	canvas_height = int(height_attr)
	
	custom_minimum_size = Vector2(canvas_width, canvas_height)
	size = Vector2(canvas_width, canvas_height)
	color = Color.TRANSPARENT
	clip_contents = true
	
	parser.register_dom_node(element, self)

func withContext(context_type: String):
	match context_type:
		"2d":
			if context_2d == null:
				context_2d = CanvasContext2D.new(self)
			return context_2d
		"shader":
			if context_shader == null:
				context_shader = CanvasContextShader.new(self)
			return context_shader
		_:
			return null

func _draw():
	draw_rect(Rect2(Vector2.ZERO, size), Color.TRANSPARENT)
	
	# Skip if too many commands to prevent frame drops
	if draw_commands.size() > max_draw_commands * 2:
		return
	
	for cmd in draw_commands:
		match cmd.type:
			"fillRect":
				var transform = cmd.get("transform", Transform2D.IDENTITY)

				if transform != Transform2D.IDENTITY:
					var corners = PackedVector2Array([
						transform * Vector2(cmd.x, cmd.y),
						transform * Vector2(cmd.x + cmd.width, cmd.y),
						transform * Vector2(cmd.x + cmd.width, cmd.y + cmd.height),
						transform * Vector2(cmd.x, cmd.y + cmd.height)
					])
					draw_colored_polygon(corners, cmd.color)
				else:
					var pos = Vector2(cmd.x, cmd.y)
					var sz = Vector2(cmd.width, cmd.height)
					draw_rect(Rect2(pos, sz), cmd.color)
			"strokeRect":
				var transform = cmd.get("transform", Transform2D.IDENTITY)
				var stroke_width = cmd.get("stroke_width", 1.0)

				if transform != Transform2D.IDENTITY:
					# Draw as stroke polygon for transformed rectangles
					var corners = PackedVector2Array([
						transform * Vector2(cmd.x, cmd.y),
						transform * Vector2(cmd.x + cmd.width, cmd.y),
						transform * Vector2(cmd.x + cmd.width, cmd.y + cmd.height),
						transform * Vector2(cmd.x, cmd.y + cmd.height),
						transform * Vector2(cmd.x, cmd.y) # Close the path
					])
					for i in range(corners.size() - 1):
						draw_line(corners[i], corners[i + 1], cmd.color, stroke_width)
				else:
					var pos = Vector2(cmd.x, cmd.y)
					# Draw stroke as four rectangles
					draw_rect(Rect2(pos.x, pos.y, cmd.width, stroke_width), cmd.color)
					draw_rect(Rect2(pos.x, pos.y + cmd.height - stroke_width, cmd.width, stroke_width), cmd.color)
					draw_rect(Rect2(pos.x, pos.y, stroke_width, cmd.height), cmd.color)
					draw_rect(Rect2(pos.x + cmd.width - stroke_width, pos.y, stroke_width, cmd.height), cmd.color)
			"clearRect":
				# Clear a rectangular area by painting with background color
				var clear_rect = Rect2(cmd.x, cmd.y, cmd.width, cmd.height)
				# Most canvases have a white or light background - paint with that
				draw_rect(clear_rect, Color.WHITE)
			"circle":
				var transform = cmd.get("transform", Transform2D.IDENTITY)
				var center = transform * Vector2(cmd.x, cmd.y)
				if cmd.filled:
					draw_circle(center, cmd.radius, cmd.color)
				else:
					# For stroke circle, we need to draw a ring - approximated with arc segments
					var segments = 32
					var points = PackedVector2Array()
					for i in range(segments + 1):
						var angle = (i * TAU) / segments
						var point = Vector2(cmd.x + cos(angle) * cmd.radius, cmd.y + sin(angle) * cmd.radius)
						points.append(transform * point)
					if points.size() > 1:
						for i in range(points.size() - 1):
							draw_line(points[i], points[i + 1], cmd.color, 1.0)
			"text":
				var font = ThemeDB.fallback_font
				var transform = cmd.get("transform", Transform2D.IDENTITY)
				var pos = transform * Vector2(cmd.x, cmd.y)
				var font_size = cmd.get("font_size", 16)
				draw_string(font, pos, cmd.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, cmd.color)
			"stroke_path":
				var path = cmd.path
				var clr = cmd.color
				var line_width = cmd.get("line_width", 1.0)
				if path.size() > 1:
					for i in range(path.size() - 1):
						draw_line(path[i], path[i + 1], clr, line_width)
			"fill_path":
				var path = cmd.path
				var clr = cmd.color
				if path.size() > 2:
					draw_colored_polygon(path, clr)

func _add_draw_command(cmd: Dictionary):
	_optimize_command(cmd)
	
	draw_commands.append(cmd)
	
	if draw_commands.size() > max_draw_commands:
		draw_commands = draw_commands.slice(draw_commands.size() - max_draw_commands)
	
	if not pending_redraw:
		pending_redraw = true
		call_deferred("_do_redraw")

func _optimize_command(cmd: Dictionary):
	# Remove redundant consecutive clearRect commands
	if cmd.type == "clearRect" and draw_commands.size() > 0:
		var last_cmd = draw_commands[-1]
		if last_cmd.type == "clearRect" and \
		   last_cmd.x == cmd.x and last_cmd.y == cmd.y and \
		   last_cmd.width == cmd.width and last_cmd.height == cmd.height:
			draw_commands.pop_back()

func _do_redraw():
	pending_redraw = false
	queue_redraw()

func clear():
	draw_commands.clear()
	_do_redraw()
