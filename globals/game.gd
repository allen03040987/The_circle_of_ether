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
	
	# 記錄剛出生時的乾淨數值
	default_player_stats = player_stats.to_dict()
	
	# 遊戲一啟動，立刻讀取玩家的偏好設定！
	load_settings()
	
# ==========================================
# ⚙️ 設定檔獨立存讀系統 (Settings System)
# ==========================================
## 儲存玩家偏好設定 (寫入 cfg 檔)
func save_settings() -> void:
	var config = ConfigFile.new()
	# 設定寫法：設定區塊(Section), 鍵名(Key), 數值(Value)
	config.set_value("Controls", "default_walking", config_default_walking)
	config.save(SETTINGS_PATH)

## 讀取玩家偏好設定 (遊戲啟動時自動呼叫)
func load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_PATH)
	
	if err == OK:
		# 讀取成功：套用設定檔裡的數值 (找不到則預設給 false)
		config_default_walking = config.get_value("Controls", "default_walking", false)
	else:
		# 讀取失敗 (例如第一次玩)：自動建一個預設的並存起來
		save_settings()

# ==========================================
# 🗺️ 場景切換邏輯 (Scene Transition)
# ==========================================
## 核心轉場函數，支援傳送點對接與狀態初始化
func change_scene(path: String, params := {}) -> void:
	if is_transitioning: return
	is_transitioning = true 
	
	var tree := get_tree() 
	tree.paused = true  
	
	# --- 1. 畫面淡出 ---
	var tween := create_tween() 
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(color_rect, "color:a", 1.0, 0.1) 
	await tween.finished 
	
	# --- 2. 儲存舊地圖狀態 ---
	if tree.current_scene is World: 
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
	tree.change_scene_to_file(path) 
	await tree.tree_changed  
	
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
	
	var json := JSON.stringify(data, "\t")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file: return
	file.store_string(json)
	
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
		"init": func (): 
			world_stats = data.world_stats
			player_stats.from_dict(data.stats)
	})

## 初始化世界並開始新遊戲
func new_game() -> void:
	player_combat_state = {} # 🌟 開新遊戲時，清空記憶背包
	change_scene("res://Worlds/forest.tscn", {
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
