class_name SizeUtils
extends RefCounted

# Utility functions for parsing CSS size values

static func parse_size(val: String) -> String:
	print("DEBUG: SizeUtils.parse_size() - Parsing value: ", val)

	# Add comprehensive null and empty checks
	if val == null:
		print("ERROR: SizeUtils.parse_size() - Input value is null")
		return "0px"

	if typeof(val) != TYPE_STRING:
		print("ERROR: SizeUtils.parse_size() - Input value is not a string, type: ", typeof(val))
		return "0px"

	if val.is_empty():
		print("WARNING: SizeUtils.parse_size() - Input value is empty")
		return "0px"

	var named = {
		"0": "0px", "1": "4px", "2": "8px", "3": "12px", "4": "16px", "5": "20px", "6": "24px", "8": "32px", "10": "40px",
		"12": "48px", "16": "64px", "20": "80px", "24": "96px", "28": "112px", "32": "128px", "36": "144px", "40": "160px",
		"44": "176px", "48": "192px", "52": "208px", "56": "224px", "60": "240px", "64": "256px", "72": "288px", "80": "320px", "96": "384px",
		"3xs": "256px", "2xs": "288px", "xs": "320px", "sm": "384px", "md": "448px", "lg": "512px",
		"xl": "576px", "2xl": "672px", "3xl": "768px", "4xl": "896px", "5xl": "1024px", "6xl": "1152px", "7xl": "1280px",
		"full": "100%"
	}

	if named.has(val):
		var result = named[val]
		print("DEBUG: SizeUtils.parse_size() - Found named size: ", val, " -> ", result)
		return result

	# Fractional (e.g. 1/2, 1/3)
	if val.find("/") != -1:
		var parts = val.split("/")
		if parts.size() == 2:
			var numerator = parts[0].strip_edges()
			var denominator = parts[1].strip_edges()

			if numerator.is_valid_int() and denominator.is_valid_int():
				var num_val = int(numerator)
				var den_val = int(denominator)

				if den_val != 0:
					var frac = float(num_val) / float(den_val)
					var result = str(frac * 100.0) + "%"
					print("DEBUG: SizeUtils.parse_size() - Parsed fraction: ", val, " -> ", result)
					return result
				else:
					print("ERROR: SizeUtils.parse_size() - Division by zero in fraction: ", val)
			else:
				print("ERROR: SizeUtils.parse_size() - Invalid fraction parts: ", val)
		else:
			print("ERROR: SizeUtils.parse_size() - Invalid fraction format: ", val)
	
	if val.is_valid_int():
		var result = str(int(val) * 16) + "px"
		print("DEBUG: SizeUtils.parse_size() - Parsed integer: ", val, " -> ", result)
		return result

	print("DEBUG: SizeUtils.parse_size() - Returning original value: ", val)
	return val

static func extract_bracket_content(string: String, start_idx: int) -> String:
	print("DEBUG: SizeUtils.extract_bracket_content() - Extracting from: ", string, " at index: ", start_idx)

	# Add comprehensive null and bounds checks
	if string == null:
		print("ERROR: SizeUtils.extract_bracket_content() - Input string is null")
		return ""

	if typeof(string) != TYPE_STRING:
		print("ERROR: SizeUtils.extract_bracket_content() - Input is not a string, type: ", typeof(string))
		return ""

	if start_idx < 0 or start_idx >= string.length():
		print("ERROR: SizeUtils.extract_bracket_content() - Invalid start index: ", start_idx)
		return ""

	var open_idx = string.find("[", start_idx)
	if open_idx == -1:
		print("DEBUG: SizeUtils.extract_bracket_content() - No opening bracket found")
		return ""

	var close_idx = string.find("]", open_idx)
	if close_idx == -1:
		print("ERROR: SizeUtils.extract_bracket_content() - No closing bracket found")
		return ""

	if close_idx <= open_idx:
		print("ERROR: SizeUtils.extract_bracket_content() - Invalid bracket positions")
		return ""

	var result = string.substr(open_idx + 1, close_idx - open_idx - 1)
	print("DEBUG: SizeUtils.extract_bracket_content() - Extracted: ", result)
	return result

static func parse_radius(radius_str: String) -> int:
	print("DEBUG: SizeUtils.parse_radius() - Parsing radius: ", radius_str)

	# Add comprehensive null and empty checks
	if radius_str == null:
		print("ERROR: SizeUtils.parse_radius() - Input radius is null")
		return 0

	if typeof(radius_str) != TYPE_STRING:
		print("ERROR: SizeUtils.parse_radius() - Input radius is not a string, type: ", typeof(radius_str))
		return 0

	if radius_str.is_empty():
		print("WARNING: SizeUtils.parse_radius() - Input radius is empty")
		return 0

	if radius_str.ends_with("px"):
		var value = radius_str.replace("px", "")
		if value.is_valid_int():
			var result = int(value)
			print("DEBUG: SizeUtils.parse_radius() - Parsed px radius: ", radius_str, " -> ", result)
			return result
		else:
			print("ERROR: SizeUtils.parse_radius() - Invalid px value: ", value)
	elif radius_str.ends_with("rem"):
		var value = radius_str.replace("rem", "")
		if value.is_valid_float():
			var result = int(float(value) * 16)
			print("DEBUG: SizeUtils.parse_radius() - Parsed rem radius: ", radius_str, " -> ", result)
			return result
		else:
			print("ERROR: SizeUtils.parse_radius() - Invalid rem value: ", value)
	elif radius_str.is_valid_float():
		var result = int(radius_str)
		print("DEBUG: SizeUtils.parse_radius() - Parsed float radius: ", radius_str, " -> ", result)
		return result
	elif radius_str.is_valid_int():
		var result = int(radius_str)
		print("DEBUG: SizeUtils.parse_radius() - Parsed int radius: ", radius_str, " -> ", result)
		return result

	print("ERROR: SizeUtils.parse_radius() - Could not parse radius, returning 0: ", radius_str)
	return 0
