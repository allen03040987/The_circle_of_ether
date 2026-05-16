@tool
extends EditorScript

# 設定路徑（請根據你的專案修改）
const SOURCE_DIR = "res://PixelBaker//"  # 原始大圖的位置
const SAVE_DIR = "res://VsMods/Explod/"  # 處理後小圖的位置
const PIXEL_SIZE = 16.0                # 你想要的像素顆粒大小

func _run():
	var dir = DirAccess.open(SOURCE_DIR)
	if not dir:
		print("錯誤：找不到來源資料夾 ", SOURCE_DIR)
		return
	
	# 確保儲存資料夾存在
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if not dir.current_is_dir() and (file_name.ends_with(".png") or file_name.ends_with(".jpg")):
			process_image(file_name)
		file_name = dir.get_next()
	
	print("--- 所有圖片處理完成！ ---")
	# 自動重新掃描檔案系統，讓 Godot 顯示新圖片
	get_editor_interface().get_resource_filesystem().scan()

func process_image(file_name):
	var full_path = SOURCE_DIR + file_name
	var image = Image.load_from_file(full_path)
	
	if image:
		var orig_size = image.get_size()
		# 計算像素化後的新尺寸
		var new_w = max(1, int(orig_size.x / PIXEL_SIZE))
		var new_h = max(1, int(orig_size.y / PIXEL_SIZE))
		
		print("正在處理: ", file_name, " -> 新尺寸: ", new_w, "x", new_h)
		
		# --- 關鍵步驟：像素化重採樣 ---
		# 1. 先縮小到極小（使用 Nearest 採樣，保留硬邊緣）
		image.resize(new_w, new_h, Image.INTERPOLATE_NEAREST)
		
		# 2. 儲存新檔案
		var save_path = SAVE_DIR + "pixel_" + file_name
		image.save_png(save_path)
	else:
		print("跳過：無法讀取 ", file_name)
