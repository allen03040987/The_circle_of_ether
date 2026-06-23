extends Node
## 遊戲全域管理器 (Autoload)
## 負責處理設定檔存取、遊戲進度存讀、以及跨場景的無縫切換與狀態保留。

# ==========================================
# 📂 檔案路徑定義 (File Paths)
# ==========================================
const SAVE_PATH = "user://data.sav"
const SETTINGS_PATH = "user://settings.cfg" 

# ==========================================
# ⚙️ 玩家偏好設定 (Global Settings)
# ==========================================
## 專屬廣播訊號！只要設定被改，就發射這個訊號通知全畫面
signal settings_changed

## 玩家在設定選單中選擇的預設模式 (false=跑步, true=行走)
var config_default_walking: bool = false 
## 預設開啟螢幕震動
var config_enable_screen_shake: bool = true
## 預設開啟受擊白光
var config_enable_hit_flash: bool = true
## 玩家的全螢幕偏好狀態
var config_fullscreen: bool = false

# ==========================================
# 🌍 全域狀態與節點參考 (State & References)
# ==========================================
## 記錄所有地圖的動態狀態 (例如哪些怪物死了)
var world_stats := {}
## 記錄玩家初始的基礎數值 (用於開新遊戲時還原)
var default_player_stats: Dictionary 
## 轉場防呆鎖，防止連續觸發傳送
var is_transitioning := false

## 記錄玩家跨場景的戰鬥狀態 (合軸、武器能量、當前武器、CD等)
var player_combat_state: Dictionary = {}

@onready var player_stats: Stats = $PlayerStats
@onready var color_rect: ColorRect = $ColorRect

# ==========================================
# 🚀 初始化 (Initialization)
# ==========================================
func _ready() -> void:
	color_rect.color.a = 0.0
	default_player_stats = player_stats.to_dict()
	
	load_settings()
	
	# 🌟 新增：遊戲開機時，立刻套用讀取出來的全螢幕偏好
	if config_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		
	# 🌟 新增：遊戲開機時，立刻從 user:// 檔案中把自定義按鍵加載進系統
	_load_custom_keybindings_at_launch()
	
# ==========================================
# ⚙️ 設定檔獨立存讀系統 (Settings System)
# ==========================================
## 儲存玩家偏好設定 (寫入 cfg 檔)
func save_settings() -> void:
	var config = ConfigFile.new()
	# 設定寫法：設定區塊(Section), 鍵名(Key), 數值(Value)
	config.set_value("Controls", "default_walking", config_default_walking)
	
	# 🌟 新增：將震動與白光設定存入 "Visuals" (視覺) 區塊
	config.set_value("Visuals", "enable_screen_shake", config_enable_screen_shake)
	config.set_value("Visuals", "enable_hit_flash", config_enable_hit_flash)
	
	config.set_value("Visuals", "fullscreen", config_fullscreen)
	
	config.save(SETTINGS_PATH)

## 讀取玩家偏好設定 (遊戲啟動時自動呼叫)
func load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_PATH)
	
	if err == OK:
		# 讀取成功：套用設定檔裡的數值 (最後一個參數是找不到時的預設值)
		config_default_walking = config.get_value("Controls", "default_walking", false)
		
		# 🌟 新增：讀取震動與白光設定 (找不到時預設給 true)
		config_enable_screen_shake = config.get_value("Visuals", "enable_screen_shake", true)
		config_enable_hit_flash = config.get_value("Visuals", "enable_hit_flash", true)
		config_fullscreen = config.get_value("Visuals", "fullscreen", false)
	else:
		# 讀取失敗 (例如第一次玩)：自動建一個預設的並存起來
		save_settings()

# ==========================================
# ⌨️ 獨立按鍵自動開機加載系統
# ==========================================
func _load_custom_keybindings_at_launch() -> void:
	var config = ConfigFile.new()
	# 如果玩家根本沒改過按鍵（沒有存檔），直接安全退出，沿用專案項目預設按鍵
	if config.load("user://keybindings.cfg") != OK: return
	
	# 掃描並註冊我們自定義按鍵清單中的所有動作代號
	var actions = ["move_left", "move_right", "jump", "attack", "heavy_attack", "martial_modifier", "art_1", "art_2", "art_3", "ultimate", "silde", "switch_weapon", "interact"]
	
	for action_name in actions:
		var has_key = config.has_section_key("Controls", action_name + "_key")
		var has_mouse = config.has_section_key("Controls", action_name + "_mouse")
		if not (has_key or has_mouse): continue
		
		# 抹除項目預設，換上玩家自定義的配置
		InputMap.action_erase_events(action_name)
		
		if has_key:
			var k_data = config.get_value("Controls", action_name + "_key")
			var k = InputEventKey.new()
			k.keycode = k_data.get("keycode", 0)
			k.physical_keycode = k_data.get("physical_keycode", 0)
			InputMap.action_add_event(action_name, k)
			
		if has_mouse:
			var m_data = config.get_value("Controls", action_name + "_mouse")
			var m = InputEventMouseButton.new()
			m.button_index = m_data.get("button_index", 0)
			InputMap.action_add_event(action_name, m)
			
	print("🟢 [全域系統] 偵測到本地自定義按鍵存檔，已於開機自動完成全神經加載。")
	
# ==========================================
# 🗺️ 場景切換邏輯 (Scene Transition)
# ==========================================
## 核心轉場函數，支援傳送點對接與狀態初始化
func change_scene(path: String, params := {}) -> void:
	if is_transitioning: return
	is_transitioning = true 
	
	if CombatManager.has_method("force_reset_time"):
		CombatManager.force_reset_time()
			
	var tree := get_tree() 
	tree.paused = true  
	
	# 🌟 效能極致優化：提早發送非同步載入請求！
	# 讓 Godot 在我們播淡出動畫和存檔的時候，背景就已經在偷偷搬磚讀取新地圖了！
	ResourceLoader.load_threaded_request(path, "", true)
	
	
	# --- 1. 畫面淡出 ---
	var tween := create_tween() 
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(color_rect, "color:a", 1.0, 0.1) 
	await tween.finished 
	
	
	# --- 2. 儲存舊地圖狀態 ---
	var is_loading = params.get("is_loading_save", false)
	
	# 🚨 如果正在讀檔，絕對不准觸發「離開前存檔」，否則會把剛讀出來的資料洗掉！
	if tree.current_scene is World and not is_loading: 
		var old_name = tree.current_scene.scene_file_path.get_basename().get_file()
		world_stats[old_name] = tree.current_scene.to_dict()
		
		# 換場景前，把玩家身上的戰鬥資料打包帶走！
		if "player" in tree.current_scene and tree.current_scene.player:
			if tree.current_scene.player.has_method("export_combat_state"):
				player_combat_state = tree.current_scene.player.export_combat_state()
	
	# --- 3. 執行中繼初始化 ---
	if "init" in params: 
		params.init.call()
	
	# --- 4. 載入新地圖 ---
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await tree.process_frame 
		
	if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
		var next_scene_pack = ResourceLoader.load_threaded_get(path)
		
		# 🌟 強化 2：音訊緩衝呼吸大法！
		# 在執行最吃 CPU 的場景替換前，讓主程式刻意停頓兩幀
		# 這能讓底層的音效系統有足夠時間「囤積」音樂數據，完美覆蓋掉替換時的卡頓
		await tree.process_frame
		await tree.process_frame
		
		tree.change_scene_to_packed(next_scene_pack)
		
	
		await tree.process_frame 
	else:
		printerr("❌ 場景載入失敗: ", path)
		tree.paused = false
		is_transitioning = false
		return
	
	# --- 5. 還原新地圖狀態與玩家位置 ---
	if tree.current_scene is World: 
		var new_name = tree.current_scene.scene_file_path.get_basename().get_file()
		
		# 還原怪物生死狀態
		if new_name in world_stats: 
			tree.current_scene.from_dict(world_stats[new_name])
			
		# 新玩家誕生後，把記憶背包裡的資料塞給他！
		if "player" in tree.current_scene and tree.current_scene.player:
			if not player_combat_state.is_empty() and tree.current_scene.player.has_method("import_combat_state"):
				tree.current_scene.player.import_combat_state(player_combat_state)
				
		# 依據傳送門 (entry_point) 對接位置
		if "entry_point" in params:
			for node in tree.get_nodes_in_group("entry_points"):
				if node.name == params.entry_point:
					tree.current_scene.update_player(node.global_position, node.direction) 
					break
					
		# 依據存檔座標 (position) 直接空降
		if "position" in params and "direction" in params:
			tree.current_scene.update_player(params.position, params.direction)
			
	# --- 6. 畫面淡入與解鎖 ---
	tween = create_tween() 
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS) # 確保淡入也不受 pause 影響
	tween.tween_property(color_rect, "color:a", 0.0, 0.2) 
	tree.paused = false  
	
	await tween.finished 
	is_transitioning = false 

# ==========================================
# 💾 遊戲進度存讀系統 (Save Data System)
# ==========================================
## 將當前進度寫入 user://data.sav
func save_game() -> void: 
	var scene := get_tree().current_scene
	var scene_name := scene.scene_file_path.get_basename().get_file()
	world_stats[scene_name] = scene.to_dict()  
	
	# 🌟 存檔前，確保拿到了最新的戰鬥背包
	if scene is World and "player" in scene and scene.player.has_method("export_combat_state"):
		player_combat_state = scene.player.export_combat_state()
		
	var data := {
		"world_stats": world_stats,      
		"stats": player_stats.to_dict(), 
		"scene": scene.scene_file_path,  
		"player": {
			"direction": scene.player.direction, 
			"position": {
				"x": scene.player.global_position.x,
				"y": scene.player.global_position.y,
			},
		},
		"combat_state": player_combat_state # 🌟 核心修復：把戰鬥背包真正寫入 JSON 存檔中！
	}
	
	# 🚨 關鍵偵測：檢查到底存了什麼鬼東西進去！
	print("💾 [存檔偵測] 武器清單內容: ", player_combat_state.get("equipped_weapon_ids"))
	
	var json := JSON.stringify(data, "\t")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file: return
	file.store_string(json)
	
## 讀取 user://data.sav 並恢復世界
## 讀取 user://data.sav 並恢復世界
func load_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ) 
	if not file: return
		
	var json := file.get_as_text()
	var data := JSON.parse_string(json) as Dictionary 
	
	player_combat_state = data.get("combat_state", {}) # 🌟 從硬碟讀取記憶背包
	
	change_scene(data.scene, {
		"direction": data.player.direction,
		"position": Vector2(data.player.position.x, data.player.position.y),
		"is_loading_save": true, # 🚨 核心防呆：告訴轉場系統「我是讀檔，絕對不要洗掉我的資料！」
		"init": func (): 
			world_stats = data.world_stats
			player_stats.from_dict(data.stats)
	})

## 初始化世界並開始新遊戲
func new_game() -> void:
	player_combat_state = {} # 🌟 開新遊戲時，清空記憶背包
	change_scene("res://Worlds/home.tscn", {
		"init": func ():
			world_stats = {}
			player_stats.from_dict(default_player_stats)
	})
	
## 強制退出至主選單
func back_to_title() -> void:
	# 暴力保險：確保解除暫停與顯示滑鼠
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	change_scene("res://ui/title_screen.tscn")
	
## 檢查是否存在存檔檔
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)
