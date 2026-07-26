@tool
class_name AutoSizingFlexContainer
extends FlexContainer

signal flex_resized

var content_size: Vector2 = Vector2.ZERO

# This is the overridden layout logic for the auto-sizing container
func _resort() -> void:
	# Check if we should fill horizontally (for w-full)
	if has_meta("should_fill_horizontal"):
		size_flags_horizontal = Control.SIZE_FILL
	else:
		if size_flags_horizontal == Control.SIZE_EXPAND_FILL and has_meta("size_flags_set_by_style_manager"):
			pass
		else:
			if not has_meta("size_flags_set_by_style_manager"):
				size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	
	# Check if we should fill vertically (for h-full)  
	if has_meta("should_fill_vertical"):
		size_flags_vertical = Control.SIZE_FILL
	else:
		if not has_meta("size_flags_set_by_style_manager"):
			size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	
	if debug_draw:
		_draw_rects.clear()

	var child_count = get_child_count()
	var valid_child_index = 0
	for i in range(child_count):
		var c = get_child(i)
		if not c is Control or c.is_set_as_top_level():
			continue
		
		# Skip background panel from flex calculations
		if BackgroundUtils.is_background_panel(c):
			continue

		var cid = c.get_instance_id()
		var target_index = _find_index_from_flex_list(_flex_list, cid)
		var flexbox: Flexbox

		# If the child shouldn't participate in layout, remove its corresponding flexbox node
		if not _should_include_child_in_layout(c):
			if target_index != -1:
				_root.remove_child_at(target_index)
				_flex_list.remove_at(target_index)
			continue

		# Find, swap, or create a new flexbox node for the child
		if target_index != -1:
			var old_flex_data = _flex_list[valid_child_index]
			var new_flex_data = _flex_list[target_index]
			flexbox = new_flex_data[FlexDataType.FLEXBOX]

			if old_flex_data[FlexDataType.CID] != cid:
				_root.swap_child(valid_child_index, target_index)
				_flex_list[target_index] = old_flex_data
				_flex_list[valid_child_index] = new_flex_data
		else:
			flexbox = Flexbox.new()
			_root.insert_child(flexbox, valid_child_index)
			_flex_list.insert(valid_child_index, [cid, flexbox, c])

		# Set the minimum size and apply flex properties for the child
		_set_control_min_size(c, flexbox)
		var flex_metas = c.get_meta("flex_metas", {})
		if flex_metas.size():
			apply_flex_meta(flexbox, flex_metas)
			if flex_metas.has("padding"):
				padding_wrapper(c, flex_metas.get("padding"))
		valid_child_index += 1

	# Clean up any flexbox nodes for children that were removed
	child_count = valid_child_index
	if child_count != _flex_list.size():
		for i in range(_flex_list.size() - 1, child_count - 1, -1):
			_root.remove_child_at(i)
		_flex_list.resize(child_count)
		_root.mark_dirty_and_propogate()


	var auto_size_width = not has_meta("custom_css_width") and not has_meta("should_fill_horizontal") and not has_meta("custom_css_width_percentage")
	var auto_size_height = not has_meta("custom_css_height") and not has_meta("should_fill_vertical") and not has_meta("custom_css_height_percentage")

	var available_width = NAN
	var available_height = NAN
	
	if not auto_size_width:
		available_width = calculate_available_dimension(true)
	elif flex_wrap != FlexContainer.FlexWrap.NoWrap:
		available_width = get_parent_or_fallback_size(true)
	
	if not auto_size_height:
		available_height = calculate_available_dimension(false)

	_root.calculate_layout(available_width, available_height, 1) # 1 = LTR direction

	# Get the size computed by Yoga
	var computed_size = Vector2(
		_root.get_computed_width(),
		_root.get_computed_height()
	)

	# Respect any explicit width/height set via metadata
	var custom_w = calculate_custom_dimension(true)
	var custom_h = calculate_custom_dimension(false)

	var needed_size = Vector2(
		max(custom_w, computed_size.x),
		max(custom_h, computed_size.y)
	)
	
	# Store the actual content size for background drawing
	content_size = needed_size

	# Construct the new minimum size for this container
	var new_min_size = custom_minimum_size
	if auto_size_width:
		# If flex wrap is enabled, constrain width to parent's available space
		if flex_wrap == FlexContainer.FlexWrap.Wrap:
			var parent_width = get_parent_or_fallback_size(true)
			if not is_nan(parent_width) and parent_width > 0:
				new_min_size.x = min(needed_size.x, parent_width)
			else:
				new_min_size.x = needed_size.x
		else:
			new_min_size.x = needed_size.x
	else:
		# For w-full, ensure minimum size matches the needed size
		new_min_size.x = needed_size.x
	if auto_size_height:
		new_min_size.y = needed_size.y
	else:
		# For h-full, ensure minimum size matches the needed size  
		new_min_size.y = needed_size.y

	if not custom_minimum_size.is_equal_approx(new_min_size):
		custom_minimum_size = new_min_size
		
		# For w-full/h-full, also force the actual size if SIZE_FILL isn't working
		if has_meta("should_fill_horizontal") and size.x < new_min_size.x:
			size.x = new_min_size.x
		if has_meta("should_fill_vertical") and size.y < new_min_size.y:
			size.y = new_min_size.y

	# Apply the calculated layout to each child control
	for flex_data in _flex_list:
		var flexbox = flex_data[FlexDataType.FLEXBOX]
		var c = flex_data[FlexDataType.CONTROL]
		var offset = Vector2(flexbox.get_computed_left(), flexbox.get_computed_top())
		var rect_size = Vector2(flexbox.get_computed_width(), flexbox.get_computed_height())
		_fit_child_in_rect(c, Rect2(offset, rect_size))

		if debug_draw:
			_draw_debug_rect(Rect2(offset, rect_size), Color(1, 0, 0, 0.8))


	if not _is_inside_background_container():
		BackgroundUtils.update_background_panel(self)
	
	emit_signal("flex_resized")

func _should_include_child_in_layout(c: Control) -> bool:
	if not is_instance_valid(c):
		return false
	
	if not c.visible or not c.is_inside_tree():
		return false
	
	return true

func _is_inside_background_container() -> bool:
	var current_parent = get_parent()
	while current_parent:
		if current_parent is PanelContainer:
			if current_parent.has_meta("hover_stylebox") or current_parent.has_meta("normal_stylebox"):
				return true
		current_parent = current_parent.get_parent()
	return false

func calculate_available_dimension(is_width: bool) -> float:
	var percentage_key = "custom_css_width_percentage" if is_width else "custom_css_height_percentage"
	var fill_key = "should_fill_horizontal" if is_width else "should_fill_vertical"
	
	if has_meta(fill_key):
		return get_parent_or_fallback_size(is_width)
	elif has_meta(percentage_key):
		var percentage_str = get_meta(percentage_key)
		var percentage = float(percentage_str.replace("%", "")) / 100.0
		var parent_size = get_parent_size(is_width)
		return parent_size * percentage if parent_size > 0 else (custom_minimum_size.x if is_width else custom_minimum_size.y)
	else:
		return size.x if is_width else size.y

func calculate_custom_dimension(is_width: bool) -> float:
	var dimension_key = "custom_css_width" if is_width else "custom_css_height"
	var percentage_key = "custom_css_width_percentage" if is_width else "custom_css_height_percentage"
	var fill_key = "should_fill_horizontal" if is_width else "should_fill_vertical"
	
	if has_meta(dimension_key):
		return float(get_meta(dimension_key))
	elif has_meta(percentage_key):
		var percentage_str = get_meta(percentage_key)
		var percentage = float(percentage_str.replace("%", "")) / 100.0
		var parent_size = get_parent_size(is_width)
		if parent_size > 0:
			return parent_size * percentage
		elif (size.x if is_width else size.y) > 0:
			return (size.x if is_width else size.y) * percentage
		else:
			return 0.0
	elif has_meta(fill_key):
		return 0.0
	else:
		return 0.0

func get_parent_size(is_width: bool) -> float:
	var parent_container = get_parent()
	if parent_container:
		return parent_container.size.x if is_width else parent_container.size.y
	return 0.0

func get_parent_or_fallback_size(is_width: bool) -> float:
	var parent_container = get_parent()
	if parent_container and (parent_container.size.x if is_width else parent_container.size.y) > 0:
		return parent_container.size.x if is_width else parent_container.size.y
	elif (size.x if is_width else size.y) > 0:
		return size.x if is_width else size.y
	else:
		var fallback = custom_minimum_size.x if is_width else custom_minimum_size.y
		return fallback if fallback > 0 else NAN
