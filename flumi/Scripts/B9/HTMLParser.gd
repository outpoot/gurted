class_name HTMLParser
extends Node

class HTMLElement:
	var tag_name: String
	var attributes: Dictionary = {}
	var text_content: String = ""
	var children: Array[HTMLElement] = []
	var parent: HTMLElement = null
	var is_self_closing: bool = false
	
	func _init(tag: String = ""):
		tag_name = tag
	
	func get_attribute(name_: String, default: String = "") -> String:
		return attributes.get(name_, default)
	
	func has_attribute(name_: String) -> bool:
		return attributes.has(name_)
	
	func set_attribute(name_: String, value: String) -> void:
		attributes.set(name_, value)
	
	func get_id() -> String:
		return get_attribute("id")
	
	func get_collapsed_text() -> String:
		var collapsed = HTMLParser.unescape_html_entities(text_content).strip_edges()
		# Replace multiple whitespace characters with single space
		var regex = RegEx.new()
		regex.compile("\\s+")
		return regex.sub(collapsed, " ", true)
	
	func get_preserved_text() -> String:
		return HTMLParser.unescape_html_entities(text_content)
	
	func get_bbcode_formatted_text(parser: HTMLParser) -> String:
		var styles = {}
		if parser != null:
			styles = parser.get_element_styles_with_inheritance(self, "", [])
		return HTMLParser.get_bbcode_with_styles(self, styles, parser, [])
	
	func is_inline_element() -> bool:
		return tag_name in ["b", "i", "u", "small", "mark", "code", "span", "a", "input"]

class HTMLBody extends HTMLElement:
	var body_node: Node = null
	
	func _init():
		super._init("body")

class ParseResult:
	var root: HTMLElement
	var all_elements: Array[HTMLElement] = []
	var errors: Array[String] = []
	var css_parser: CSSParser = null
	var inline_styles: Dictionary = {}
	var dom_nodes: Dictionary = {}
	var external_css: Array[String] = []
	var external_scripts: Array[String] = []
	
	func _init():
		root = HTMLElement.new("document")

# Properties
var xml_parser: XMLParser
var bitcode: PackedByteArray
var parse_result: ParseResult

func _init(data: PackedByteArray):
	var html_string = data.get_string_from_utf8()
	html_string = preprocess_html_entities(html_string)
	bitcode = html_string.to_utf8_buffer()
	xml_parser = XMLParser.new()
	parse_result = ParseResult.new()

static func unescape_html_entities(text: String) -> String:
	return text.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"").replace("&#39;", "'").replace("&amp;", "&")

static func preprocess_html_entities(html: String) -> String:
	var result = ""
	var i = 0
	
	while i < html.length():
		var character = html[i]
		
		if character == "<":
			# Check if this starts a valid HTML tag
			var tag_end = html.find(">", i)
			if tag_end != -1:
				var potential_tag = html.substr(i, tag_end - i + 1)
				# Simple check for valid tag pattern
				if is_valid_tag_pattern(potential_tag):
					result += potential_tag
					i = tag_end + 1
					continue
			# If not a valid tag, escape it
			result += "&lt;"
		elif character == ">":
			# Escape standalone > that's not part of a tag
			result += "&gt;"
		else:
			result += character
		
		i += 1
	
	return result

static func is_valid_tag_pattern(tag: String) -> bool:
	if tag.length() < 3:  # Minimum: <x>
		return false
	
	if not tag.begins_with("<") or not tag.ends_with(">"):
		return false
	
	var inner = tag.substr(1, tag.length() - 2).strip_edges()
	
	if inner.begins_with("/"):
		inner = inner.substr(1).strip_edges()
	
	# Handle self-closing tags
	if inner.ends_with("/"):
		inner = inner.substr(0, inner.length() - 1).strip_edges()
	
	# Extract tag name (first part before space or attributes)
	var tag_name = inner.split(" ")[0].split("\t")[0]
	
	# Valid tag names contain only letters, numbers, and hyphens
	var regex = RegEx.new()
	regex.compile("^[a-zA-Z][a-zA-Z0-9-]*$")
	return regex.search(tag_name) != null

# Main parsing function
func parse() -> ParseResult:
	xml_parser.open_buffer(bitcode)
	var element_stack: Array[HTMLElement] = [parse_result.root]

	while xml_parser.read() != ERR_FILE_EOF:
		match xml_parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var element = create_element()
				var current_parent = element_stack.back()
				element.parent = current_parent
				current_parent.children.append(element)
				parse_result.all_elements.append(element)
				
				if element.tag_name == "style":
					handle_style_element(element)
				
				if not element.is_self_closing:
					element_stack.append(element)
			
			XMLParser.NODE_ELEMENT_END:
				if element_stack.size() > 1:
					element_stack.pop_back()
			
			XMLParser.NODE_TEXT:
				var text = xml_parser.get_node_data().strip_edges()
				if text.length() > 0 and element_stack.size() > 0:
					element_stack.back().text_content += text
	
	return parse_result

func handle_style_element(style_element: HTMLElement) -> void:
	# Check if it's an external stylesheet
	var src = style_element.get_attribute("src")
	if src.length() > 0:
		if not parse_result.external_css:
			parse_result.external_css = []
		parse_result.external_css.append(src)
		return
	
	# Handle inline CSS
	if not parse_result.css_parser:
		parse_result.css_parser = CSSParser.new()
		parse_result.css_parser.init()

func process_styles() -> void:
	if not parse_result.css_parser:
		parse_result.css_parser = CSSParser.new()
		parse_result.css_parser.init()
	
	var css_content = Constants.DEFAULT_CSS
	var style_elements = find_all("style")
	for style_element in style_elements:
		if style_element.get_attribute("src").is_empty():
			css_content += style_element.text_content + "\n"

	if css_content.length() > 0:
		parse_result.css_parser.css_text = css_content
		parse_result.css_parser.parse()

func process_external_styles(base_url: String = "") -> void:
	if not parse_result.external_css or parse_result.external_css.is_empty():
		return
	
	if not parse_result.css_parser:
		parse_result.css_parser = CSSParser.new()
		parse_result.css_parser.init()
	
	var combined_css = parse_result.css_parser.css_text if parse_result.css_parser.css_text else Constants.DEFAULT_CSS
	
	for css_url in parse_result.external_css:
		var css_content = await Network.fetch_external_resource(css_url, base_url)
		if not css_content.is_empty():
			combined_css += "\n" + css_content
	
	parse_result.css_parser.css_text = combined_css
	parse_result.css_parser.parse()

func get_element_styles_with_inheritance(element: HTMLElement, event: String = "", visited_elements: Array = []) -> Dictionary:
	if !parse_result.css_parser:
		return {}
	# Prevent infinite recursion
	if element in visited_elements:
		return {}

	var new_visited_for_styles = visited_elements.duplicate()
	new_visited_for_styles.append(element)
	
	var styles = {}
	
	styles.merge(parse_result.css_parser.stylesheet.get_styles_for_element(event, element))
	# Apply inline styles (higher priority) - force override CSS rules
	var inline_style = element.get_attribute("style")
	if inline_style.length() > 0:
		var inline_parsed = parse_inline_style_with_event(inline_style, event)
		for property in inline_parsed:
			styles[property] = inline_parsed[property]
	
	# Inherit certain properties from parent elements
	var inheritable_properties = ["font-size", "color", "font-family", "cursor", "font-bold", "font-italic", "underline"]
	var parent_element = element.parent
	while parent_element:
		var parent_styles = get_element_styles_internal(parent_element, event)
		for property in inheritable_properties:
			# Only inherit if child doesn't already have this property
			if not styles.has(property) and parent_styles.has(property):
				styles[property] = parent_styles[property]
		parent_element = parent_element.parent
	
	return styles

func get_element_styles_internal(element: HTMLElement, event: String = "") -> Dictionary:
	var styles = {}
	
	# Apply CSS rules
	if parse_result.css_parser:
		styles.merge(parse_result.css_parser.stylesheet.get_styles_for_element(event, element))
	
	# Apply inline styles (higher priority) - force override CSS rules
	var inline_style = element.get_attribute("style")
	if inline_style.length() > 0:
		var inline_parsed = parse_inline_style_with_event(inline_style, event)
		for property in inline_parsed:
			styles[property] = inline_parsed[property]  # Force override
	
	return styles

func parse_inline_style_with_event(style_string: String, event: String = "") -> Dictionary:
	var properties = {}
	
	# Split style string into individual utility classes
	var utility_classes = style_string.split(" ") # e.g. ["bg-red-500, "text-lg", "hover:bg-blue-500"]

	for utility_name in utility_classes:
		utility_name = utility_name.strip_edges() # e.g. "bg-red-500"
		if utility_name.is_empty():
			continue
		
		# Check if this utility is for the requested event
		if event.length() > 0:
			if utility_name.begins_with(event + ":"): # e.g. "hover:bg-blue-500"
				var actual_utility = utility_name.substr(event.length() + 1)  # bg-blue-500
				var rule = CSSParser.CSSRule.new()
				CSSParser.parse_utility_class_internal(rule, actual_utility)
				for property in rule.properties:
					properties[property] = rule.properties[property]
			else:
				# Check if this is a CSS class that might have pseudo-class rules
				if parse_result.css_parser and parse_result.css_parser.stylesheet:
					var pseudo_styles = parse_result.css_parser.stylesheet.get_styles_for_element(event, null)
					if not pseudo_styles.is_empty():
						for property in pseudo_styles:
							properties[property] = pseudo_styles[property]
		else:
			if not utility_name.contains(":"):
				if parse_result.css_parser and parse_result.css_parser.stylesheet:
					var css_rule = parse_result.css_parser.stylesheet.find_rule_by_selector("." + utility_name)
					if css_rule:
						for property in css_rule.properties:
							properties[property] = css_rule.properties[property]
					else:
						var rule = CSSParser.CSSRule.new()
						CSSParser.parse_utility_class_internal(rule, utility_name)
						for property in rule.properties:
							properties[property] = rule.properties[property]
				else:
					var rule = CSSParser.CSSRule.new()
					CSSParser.parse_utility_class_internal(rule, utility_name)
					for property in rule.properties:
						properties[property] = rule.properties[property]
	
	return properties

static func extract_class_names(element: HTMLElement) -> Array[String]:
	var class_names: Array[String] = []
	var style_attr = element.get_attribute("style")
	if style_attr.length() > 0:
		var style_tokens = style_attr.split(" ")
		for token in style_tokens:
			token = token.strip_edges()
			if token.length() > 0 and not UtilityClassValidator.is_utility_class(token):
				class_names.append(token)
	return class_names

# Creates element from CURRENT xml parser node
func create_element() -> HTMLElement:
	var element = HTMLElement.new(xml_parser.get_node_name())
	element.is_self_closing = xml_parser.is_empty()
	
	# Parse attributes
	for i in range(xml_parser.get_attribute_count()):
		var attr_name = xml_parser.get_attribute_name(i)
		var attr_value = xml_parser.get_attribute_value(i)
		element.attributes[attr_name] = attr_value
	
	return element

# Utility functions
func find_all(tag: String, attribute: String = "") -> Array[HTMLElement]:
	if parse_result.all_elements.is_empty():
		parse()
	
	var results: Array[HTMLElement] = []
	for element in parse_result.all_elements:
		if element.tag_name == tag:
			if attribute.is_empty() or element.has_attribute(attribute):
				results.append(element)
	
	return results

func find_all_by_class(tag: String, the_class_name: String) -> Array[HTMLElement]:
	if parse_result.all_elements.is_empty():
		parse()
	
	var results: Array[HTMLElement] = []
	for element in parse_result.all_elements:
		if element.tag_name == tag:
			var class_names = extract_class_names(element)
			if the_class_name in class_names:
				results.append(element)
	
	return results

func find_by_id(element_id: String) -> HTMLElement:
	if parse_result.all_elements.is_empty():
		parse()
	
	for element in parse_result.all_elements:
		if element.get_id() == element_id:
			return element
	
	return null

func register_dom_node(element: HTMLElement, node) -> void:
	var element_id = element.get_id()
	if element_id.length() > 0:
		parse_result.dom_nodes[element_id] = node

func find_first(tag: String, attribute: String = "") -> HTMLElement:
	var results = find_all(tag, attribute)
	return results[0] if results.size() > 0 else null

# Extract attribute values
func get_attribute_values(tag: String, attribute: String) -> Array[String]:
	var elements = find_all(tag, attribute)
	var values: Array[String] = []
	
	for element in elements:
		var value = element.get_attribute(attribute)
		if value.length() > 0:
			values.append(value)
	
	return values

func get_attribute_values_by_class(tag: String, the_class_name: String, attribute: String) -> Array[String]:
	var elements = find_all_by_class(tag, the_class_name)
	var values: Array[String] = []
	
	for element in elements:
		var value = element.get_attribute(attribute)
		if value.length() > 0:
			values.append(value)
	
	return values

# Misc
func get_title() -> String:
	var title_element = find_first("title")
	return title_element.text_content if title_element != null else ""

func get_icon() -> String:
	var icon_element = find_first("icon")
	return icon_element.get_attribute("src") if icon_element != null else ""

func process_fonts(base_url: String = "") -> void:
	var font_elements = find_all("font")
	
	for font_element in font_elements:
		var name_str = font_element.get_attribute("name")
		var src = font_element.get_attribute("src")
		var weight = font_element.get_attribute("weight", "400")
		
		if name_str and src:
			var resolved_src = URLUtils.resolve_url(base_url, src)
			FontManager.register_font(name_str, resolved_src, weight)

func get_meta_content(name_: String) -> String:
	var meta_elements = find_all("meta", "name")
	for element in meta_elements:
		if element.get_attribute("name") == name_:
			return element.get_attribute("content")
	return ""

func get_all_links() -> Array[String]:
	return get_attribute_values("a", "href")

func get_all_images() -> Array[String]:
	return get_attribute_values("img", "src")

func get_all_scripts() -> Array[String]:
	return get_attribute_values("script", "src")

func get_all_postprocess() -> Array[String]:
	return get_attribute_values("postprocess", "src")

func process_scripts(lua_api: LuaAPI, _lua_vm) -> void:
	if not lua_api:
		print("Warning: Lua API not available for script processing")
		return
	
	lua_api.dom_parser = self
	
	for script_element in find_all("script"):
		var src = script_element.get_attribute("src")
		var inline_code = script_element.text_content.strip_edges()
		
		if not src.is_empty():
			if not parse_result.external_scripts:
				parse_result.external_scripts = []
			parse_result.external_scripts.append(src)
		elif not inline_code.is_empty():
			lua_api.execute_lua_script(inline_code)

func process_external_scripts(lua_api: LuaAPI, _lua_vm, base_url: String = "") -> void:
	if not lua_api or not parse_result.external_scripts or parse_result.external_scripts.is_empty():
		return
	
	lua_api.dom_parser = self
	
	for script_url in parse_result.external_scripts:
		var script_content = await Network.fetch_external_resource(script_url, base_url)
		if not script_content.is_empty():
			lua_api.execute_lua_script(script_content)

func process_postprocess() -> HTMLParser.HTMLElement:
	var postprocess_elements = find_all("postprocess")
	if postprocess_elements.is_empty():
		return null
	
	# Return the last postprocess element (last defined wins)
	return postprocess_elements[-1]

func get_all_stylesheets() -> Array[String]:
	return get_attribute_values("style", "src")

func apply_element_styles(node: Control, element: HTMLElement, parser: HTMLParser) -> void:
	var styles = parser.get_element_styles_with_inheritance(element, "", [])
	if node.get("rich_text_label"):
		var label = node.rich_text_label
		var text = HTMLParser.get_bbcode_with_styles(element, styles, parser, [])
		label.text = text

static func apply_element_bbcode_formatting(element: HTMLElement, styles: Dictionary, content: String) -> String:
	# Apply general styling first (color, font-weight) for all elements
	var formatted_content = content
	
	# Apply font weight (bold/semibold/etc)
	if styles.has("font-bold") and styles["font-bold"]:
		formatted_content = "[b]" + formatted_content + "[/b]"
	elif styles.has("font-semibold") and styles["font-semibold"]:
		formatted_content = "[b]" + formatted_content + "[/b]"  # BBCode doesn't have semibold, use bold
	
	# Apply italic
	if styles.has("font-italic") and styles["font-italic"]:
		formatted_content = "[i]" + formatted_content + "[/i]"
	
	# Apply underline
	if styles.has("underline") and styles["underline"]:
		formatted_content = "[u]" + formatted_content + "[/u]"
	
	# Apply color
	if styles.has("color"):
		var color = styles["color"]
		if typeof(color) == TYPE_COLOR:
			color = "#" + color.to_html(false)
		else:
			color = str(color)
		var color_pattern = "[color=%s]" % color
		if not formatted_content.contains(color_pattern):
			formatted_content = "[color=%s]%s[/color]" % [color, formatted_content]
	
	# Apply tag-specific formatting
	match element.tag_name:
		"b":
			if not (styles.has("font-bold") and styles["font-bold"]):
				formatted_content = "[b]" + formatted_content + "[/b]"
		"i":
			if not (styles.has("font-italic") and styles["font-italic"]):
				formatted_content = "[i]" + formatted_content + "[/i]"
		"u":
			if not (styles.has("underline") and styles["underline"]):
				formatted_content = "[u]" + formatted_content + "[/u]"
		"small":
			if styles.has("font-size"):
				formatted_content = "[font_size=%d]%s[/font_size]" % [styles["font-size"], formatted_content]
			else:
				formatted_content = "[font_size=20]%s[/font_size]" % formatted_content
		"mark":
			if styles.has("bg"):
				var bg_color = styles["bg"]
				if typeof(bg_color) == TYPE_COLOR:
					bg_color = bg_color.to_html(false)
				formatted_content = "[bgcolor=#%s]%s[/bgcolor]" % [bg_color, formatted_content]
			else:
				formatted_content = "[bgcolor=#FFFF00]%s[/bgcolor]" % formatted_content
		"code":
			if styles.has("font-size"):
				formatted_content = "[font_size=%d][code]%s[/code][/font_size]" % [styles["font-size"], formatted_content]
			else:
				formatted_content = "[font_size=20][code]%s[/code][/font_size]" % formatted_content
		"a":
			var href = element.get_attribute("href")
			
			if href.length() > 0:
				if not formatted_content.contains("[url="):
					formatted_content = "[url=%s]%s[/url]" % [href, formatted_content]
	
	return formatted_content

static func get_bbcode_with_styles(element: HTMLElement, styles: Dictionary, parser: HTMLParser, visited_elements: Array = []) -> String:
	if element in visited_elements:
		return ""
	
	var new_visited = visited_elements.duplicate()
	new_visited.append(element)
	
	var text = ""
	if element.text_content.length() > 0:
		text += element.get_collapsed_text()

	for child in element.children:
		var child_styles = styles
		if parser != null:
			child_styles = parser.get_element_styles_with_inheritance(child, "", [])
		var child_content = HTMLParser.get_bbcode_with_styles(child, child_styles, parser, new_visited)
		child_content = apply_element_bbcode_formatting(child, child_styles, child_content)
		text += child_content
	
	# Apply formatting to the current element itself
	text = apply_element_bbcode_formatting(element, styles, text)
	
	return text
