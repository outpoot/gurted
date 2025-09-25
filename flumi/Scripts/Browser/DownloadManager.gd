class_name DownloadManager
extends Node

const DOWNLOAD_DIALOG = preload("res://Scenes/UI/DownloadDialog.tscn")
const DOWNLOAD_PROGRESS = preload("res://Scenes/UI/DownloadProgress.tscn")
const DOWNLOADS_HISTORY = preload("res://Scenes/BrowserMenus/downloads.tscn")

var active_downloads: Dictionary = {}
var download_progress_container: VBoxContainer = null
var downloads_history_ui: DownloadsStore = null
var main_node: Main = null

func _init(main_reference: Main):
	main_node = main_reference

func _ensure_download_progress_container():
	if not download_progress_container:
		download_progress_container = VBoxContainer.new()
		download_progress_container.name = "DownloadProgressContainer"
		download_progress_container.size_flags_horizontal = Control.SIZE_SHRINK_END
		download_progress_container.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		
		var anchor_container = Control.new()
		anchor_container.name = "DownloadAnchor"
		anchor_container.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		anchor_container.position = Vector2(0, 130)
		anchor_container.offset_left = 381 # 376 + 5px padding
		anchor_container.add_child(download_progress_container)
		main_node.add_child(anchor_container)

func handle_download_request(download_data: Dictionary):
	var active_tab = main_node.get_active_tab()
	if active_tab and active_tab.current_url:
		download_data["current_site"] = URLUtils.extract_domain(active_tab.current_url)
	else:
		download_data["current_site"] = "Unknown site"
	
	var settings_node = Engine.get_main_loop().current_scene
	var skip_confirmation = !settings_node.get_download_confirmation_setting()
	
	if skip_confirmation:
		var filename = download_data.get("filename", "download")
		var default_path = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS) + "/" + filename
		_on_download_confirmed(download_data, default_path)
	else:
		var dialog = DOWNLOAD_DIALOG.instantiate()
		main_node.add_child(dialog)
		
		dialog.download_confirmed.connect(_on_download_confirmed)
		dialog.download_cancelled.connect(_on_download_cancelled)
		dialog.show_download_dialog(download_data)

func _on_download_confirmed(download_data: Dictionary, save_path: String):
	var download_id = download_data.get("id", "")
	var url = download_data.get("url", "")
	print(download_id, url)
	if download_id.is_empty() or url.is_empty():
		push_error("Invalid download data")
		return
	
	_start_download(download_id, url, save_path, download_data)

func _on_download_cancelled(download_data: Dictionary):
	print("Download cancelled: ", download_data.get("filename", "Unknown"))

func _start_download(download_id: String, url: String, save_path: String, download_data: Dictionary):
	_ensure_download_progress_container()
	
	var progress_ui = DOWNLOAD_PROGRESS.instantiate()
	
	download_progress_container.add_child(progress_ui)
	
	progress_ui.setup_download(download_id, download_data)
	progress_ui.download_cancelled.connect(_on_download_progress_cancelled)

	active_downloads[download_id] = {
		"save_path": save_path,
		"progress_ui": progress_ui,
		"start_time": Time.get_ticks_msec() / 1000.0,
		"total_bytes": 0,
		"downloaded_bytes": 0,
		"url": download_data.get("url", ""),
		"filename": download_data.get("filename", ""),
		"current_site": download_data.get("current_site", "")
	}

	if url.begins_with("gurt://"):
		_download_gurt_resource(download_id, url)
	else:
		_start_http_download(download_id, url)

func _start_http_download(download_id: String, url: String):
	var http_request = HTTPRequest.new()
	http_request.name = "DownloadRequest_" + download_id
	main_node.add_child(http_request)

	if not active_downloads.has(download_id):
		http_request.queue_free()
		return

	active_downloads[download_id]["http_request"] = http_request

	var save_path = active_downloads[download_id]["save_path"]
	http_request.set_download_file(save_path)

	http_request.request_completed.connect(func(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
		_on_download_completed(download_id, result, response_code, headers, body)
	)

	var headers = ["User-Agent: GURT Browser 1.0"]
	var request_error = http_request.request(url, headers)

	if request_error != OK:
		var error_msg = "Failed to start download: " + str(request_error)
		print(error_msg)
		var progress_ui = active_downloads[download_id]["progress_ui"]
		if progress_ui:
			progress_ui.set_error(error_msg)
		http_request.queue_free()
		active_downloads.erase(download_id)
		return

	var timer = Timer.new()
	timer.name = "ProgressTimer_" + download_id
	timer.wait_time = 0.5
	timer.timeout.connect(func(): _update_download_progress(download_id))
	main_node.add_child(timer)
	timer.start()

func _download_gurt_resource(download_id: String, url: String):
	if not active_downloads.has(download_id):
		return

	var progress_ui = active_downloads[download_id]["progress_ui"]
	var save_path = active_downloads[download_id]["save_path"]

	if progress_ui:
		progress_ui.update_progress(0, 0, -1) # -1 indicates unknown total size

	var resource_data = await Network.fetch_gurt_resource(url, true)

	if not active_downloads.has(download_id):
		return

	if resource_data.is_empty():
		var error_msg = "Failed to fetch gurt:// resource"
		print(error_msg)
		if progress_ui:
			progress_ui.set_error(error_msg)
		active_downloads.erase(download_id)
		return

	var file = FileAccess.open(save_path, FileAccess.WRITE)
	if not file:
		var error_msg = "Failed to create download file: " + save_path
		print(error_msg)
		if progress_ui:
			progress_ui.set_error(error_msg)
		active_downloads.erase(download_id)
		return

	file.store_buffer(resource_data)
	file.close()

	var file_size = resource_data.size()

	active_downloads[download_id]["total_bytes"] = file_size
	active_downloads[download_id]["downloaded_bytes"] = file_size

	if progress_ui:
		progress_ui.set_completed(save_path)

	_add_to_download_history(active_downloads[download_id], file_size, save_path)

	active_downloads.erase(download_id)

func _update_download_progress(download_id: String):
	if not active_downloads.has(download_id):
		return
	
	var download_info = active_downloads[download_id]
	var http_request = download_info.get("http_request", null)
	var progress_ui = download_info.progress_ui
	
	if http_request and progress_ui:
		var downloaded = http_request.get_downloaded_bytes()
		var total = http_request.get_body_size()
		
		download_info.downloaded_bytes = downloaded
		download_info.total_bytes = total
		
		var progress_percent = 0.0
		if total > 0:
			progress_percent = (float(downloaded) / float(total)) * 100.0
		
		progress_ui.update_progress(progress_percent, downloaded, total)

func _on_download_completed(download_id: String, result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	if not active_downloads.has(download_id):
		return
	
	var download_info = active_downloads[download_id]
	var progress_ui = download_info.progress_ui
	var save_path = download_info.save_path
	
	var timer = main_node.get_node_or_null("ProgressTimer_" + download_id)
	if timer:
		timer.queue_free()
	
	if response_code >= 200 and response_code < 300 and result == HTTPRequest.RESULT_SUCCESS:
		var file = FileAccess.open(save_path, FileAccess.READ)
		if file:
			var file_size = file.get_length()
			file.close()
			
			if progress_ui:
				progress_ui.set_completed(save_path)
			
			_add_to_download_history(download_info, file_size, save_path)
			
			print("Download completed: ", save_path)
		else:
			if progress_ui:
				progress_ui.set_error("Downloaded file not found")
			print("Downloaded file not found: ", save_path)
	else:
		var error_msg = "HTTP " + str(response_code) if response_code >= 400 else "Request failed (" + str(result) + ")"
		if progress_ui:
			progress_ui.set_error(error_msg)
		print("Download failed: ", error_msg)
		
		if FileAccess.file_exists(save_path):
			DirAccess.remove_absolute(save_path)
	
	download_info.http_request.queue_free()
	active_downloads.erase(download_id)

func _on_download_progress_cancelled(download_id: String):
	if not active_downloads.has(download_id):
		return
	
	var download_info = active_downloads[download_id]

	var http_request = download_info.get("http_request", null)
	if http_request:
		http_request.cancel_request()
		http_request.queue_free()

	var timer = main_node.get_node_or_null("ProgressTimer_" + download_id)
	if timer:
		timer.queue_free()
	
	active_downloads.erase(download_id)
	print("Download cancelled: ", download_id)

func show_downloads_history():
	_ensure_downloads_history_ui()
	downloads_history_ui.popup_centered_ratio(0.8)

func _add_to_download_history(download_info: Dictionary, file_size: int, file_path: String):
	_ensure_downloads_history_ui()
	
	var history_data = {
		"url": download_info.url,
		"filename": download_info.filename,
		"size": file_size,
		"timestamp": Time.get_unix_time_from_system(),
		"file_path": file_path,
		"current_site": download_info.get("current_site", "")
	}
	
	downloads_history_ui.add_download_entry(history_data)

func _ensure_downloads_history_ui():
	if not downloads_history_ui:
		downloads_history_ui = DOWNLOADS_HISTORY.instantiate()
		downloads_history_ui.visible = false
		main_node.add_child(downloads_history_ui)
