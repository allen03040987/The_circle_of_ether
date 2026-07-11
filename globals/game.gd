class_name GameManager
extends Node
## 遊戲全域管理器 (Autoload)
## 負責處理設定檔存取、遊戲進度存讀、跨場景切換與狀態保留。

# ==========================================
# 📂 檔案路徑與廣播
# ==========================================
const SAVE_PATH = "user://data.sav"
const SETTINGS_PATH = "user://settings.cfg"
const LOADOUT_PATH = "user://loadout.cfg" ## 🌟 裝備配置獨立存成設定檔，跟存讀檔系統脫鉤——玩家在裝備介面改了配置，不用特地存檔，下次開遊戲一樣讀得到

signal settings_changed

# ==========================================
# ⚙️ 全域偏好設定
# ==========================================
var config_auto_run: bool = false
var config_enable_screen_shake: bool = true
var config_enable_hit_flash: bool = true
var config_enable_damage_numbers: bool = true
var config_fullscreen: bool = false
var config_music_volume: float = 1.0
var config_sfx_volume: float = 1.0
var config_dev_mode: bool = false ## 開發模式：目前效果是血包上限拉到 99，方便測試不用一直補

# ==========================================
# 🎒 裝備配置 (獨立於存讀檔系統之外)
# ==========================================
var saved_equipped_weapon_ids: Array[String] = []
var saved_martial_arts_config: Dictionary = {}
var has_saved_loadout: bool = false

# ==========================================
# 🌍 全域狀態與節點參考
# ==========================================
var world_stats := {}
var default_player_stats: Dictionary 
var is_transitioning := false
var player_combat_state: Dictionary = {}

@onready var player_stats: Stats = $PlayerStats
@onready var color_rect: ColorRect = $ColorRect

# ==========================================
# 🚀 初始化
# ==========================================
func _ready() -> void:
	color_rect.color.a = 0.0
	default_player_stats = player_stats.to_dict()
	
	load_settings()
	load_loadout_config()

	if config_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	_load_custom_keybindings_at_launch()
	apply_audio_volumes()

# ==========================================
# ⚙️ 設定檔存讀系統
# ==========================================
func save_settings() -> void:
	var config = ConfigFile.new()
	config.set_value("Controls", "auto_run", config_auto_run)
	config.set_value("Visuals", "enable_screen_shake", config_enable_screen_shake)
	config.set_value("Visuals", "enable_hit_flash", config_enable_hit_flash)
	config.set_value("Visuals", "enable_damage_numbers", config_enable_damage_numbers)
	config.set_value("Visuals", "fullscreen", config_fullscreen)
	config.set_value("Audio", "music_volume", config_music_volume)
	config.set_value("Audio", "sfx_volume", config_sfx_volume)
	config.set_value("Debug", "dev_mode", config_dev_mode)
	config.save(SETTINGS_PATH)

func load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_PATH)

	if err == OK:
		config_auto_run = config.get_value("Controls", "auto_run", false)
		config_enable_screen_shake = config.get_value("Visuals", "enable_screen_shake", true)
		config_enable_hit_flash = config.get_value("Visuals", "enable_hit_flash", true)
		config_enable_damage_numbers = config.get_value("Visuals", "enable_damage_numbers", true)
		config_fullscreen = config.get_value("Visuals", "fullscreen", false)
		config_music_volume = config.get_value("Audio", "music_volume", 1.0)
		config_sfx_volume = config.get_value("Audio", "sfx_volume", 1.0)
		config_dev_mode = config.get_value("Debug", "dev_mode", false)
	else:
		save_settings()

# ==========================================
# 🎒 裝備配置存讀 (獨立於存讀檔系統，改完立刻生效、立刻寫檔)
# ==========================================
func save_loadout_config(weapon_ids: Array[String], arts_config: Dictionary) -> void:
	saved_equipped_weapon_ids = weapon_ids.duplicate()
	saved_martial_arts_config = arts_config.duplicate(true)
	has_saved_loadout = true

	var config = ConfigFile.new()
	config.set_value("Loadout", "equipped_weapon_ids", saved_equipped_weapon_ids)
	config.set_value("Loadout", "martial_arts_config", saved_martial_arts_config)
	config.save(LOADOUT_PATH)

func load_loadout_config() -> void:
	var config = ConfigFile.new()
	var err = config.load(LOADOUT_PATH)
	if err != OK: return

	var raw_ids = config.get_value("Loadout", "equipped_weapon_ids", [])
	var safe_ids: Array[String] = []
	for id in raw_ids: safe_ids.append(str(id))

	saved_equipped_weapon_ids = safe_ids
	saved_martial_arts_config = config.get_value("Loadout", "martial_arts_config", {})
	has_saved_loadout = not saved_equipped_weapon_ids.is_empty()

## 把目前的音樂/音效音量設定套用到對應的 Audio Bus (BGM / SFX)
func apply_audio_volumes() -> void:
	_set_bus_volume("BGM", config_music_volume)
	_set_bus_volume("SFX", config_sfx_volume)

func _set_bus_volume(bus_name: String, linear_volume: float) -> void:
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx == -1: return

	var v = clampf(linear_volume, 0.0, 1.0)
	AudioServer.set_bus_mute(bus_idx, v <= 0.0)
	if v > 0.0:
		AudioServer.set_bus_volume_db(bus_idx, linear_to_db(v))

func _load_custom_keybindings_at_launch() -> void:
	var config = ConfigFile.new()
	if config.load("user://keybindings.cfg") != OK: return
	
	InputMap.load_from_project_settings()
	
	var actions = ["move_left", "move_right", "jump", "attack", "heavy_attack", "martial_modifier", "art_1", "art_2", "art_3", "guard", "slide", "switch_weapon", "interact"]
	
	for action_name in actions:
		var has_key = config.has_section_key("Controls", action_name + "_key")
		var has_mouse = config.has_section_key("Controls", action_name + "_mouse")
		if not (has_key or has_mouse): continue
		
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

# ==========================================
# 🗺️ 場景切換邏輯 (非同步載入)
# ==========================================
func change_scene(path: String, params := {}) -> void:
	if is_transitioning: return
	is_transitioning = true 
	
	if CombatManager.has_method("force_reset_time"):
		CombatManager.force_reset_time()
			
	var tree := get_tree() 
	tree.paused = true  
	
	ResourceLoader.load_threaded_request(path, "", true)
	
	var tween := create_tween() 
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(color_rect, "color:a", 1.0, 0.1) 
	await tween.finished 
	
	var is_loading = params.get("is_loading_save", false)
	
	if tree.current_scene is World and not is_loading: 
		var old_name = tree.current_scene.scene_file_path.get_basename().get_file()
		world_stats[old_name] = tree.current_scene.to_dict()
		
		if "player" in tree.current_scene and tree.current_scene.player:
			if tree.current_scene.player.has_method("export_combat_state"):
				player_combat_state = tree.current_scene.player.export_combat_state()
	
	if "init" in params: 
		params.init.call()
	
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		await tree.process_frame 
		
	if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
		var next_scene_pack = ResourceLoader.load_threaded_get(path)
		
		await tree.process_frame
		await tree.process_frame
		
		tree.change_scene_to_packed(next_scene_pack)
		await tree.process_frame 
	else:
		printerr("❌ 場景載入失敗: ", path)
		tree.paused = false
		is_transitioning = false
		return
	
	if tree.current_scene is World: 
		var new_name = tree.current_scene.scene_file_path.get_basename().get_file()
		
		if new_name in world_stats: 
			tree.current_scene.from_dict(world_stats[new_name])
			
		if "player" in tree.current_scene and tree.current_scene.player:
			if not player_combat_state.is_empty() and tree.current_scene.player.has_method("import_combat_state"):
				tree.current_scene.player.import_combat_state(player_combat_state)
				
		if "entry_point" in params:
			for node in tree.get_nodes_in_group("entry_points"):
				if node.name == params.entry_point:
					tree.current_scene.update_player(node.global_position, node.direction) 
					break
					
		if "position" in params and "direction" in params:
			tree.current_scene.update_player(params.position, params.direction)
			
	tween = create_tween() 
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(color_rect, "color:a", 0.0, 0.2) 
	tree.paused = false  
	
	await tween.finished 
	is_transitioning = false 

# ==========================================
# 💾 遊戲進度存讀系統
# ==========================================
func save_game() -> void: 
	var scene := get_tree().current_scene
	var scene_name := scene.scene_file_path.get_basename().get_file()
	world_stats[scene_name] = scene.to_dict()  
	
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
		"combat_state": player_combat_state
	}
	
	var json := JSON.stringify(data, "\t")
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file: return
	file.store_string(json)
	
func load_game() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ) 
	if not file: return
		
	var json := file.get_as_text()
	var data := JSON.parse_string(json) as Dictionary 
	
	# 防呆：如果存檔損毀或為空，阻擋崩潰
	if typeof(data) != TYPE_DICTIONARY:
		printerr("❌ 存檔讀取失敗：檔案損毀或格式錯誤")
		return
	
	player_combat_state = data.get("combat_state", {}) 
	
	change_scene(data.scene, {
		"direction": data.player.direction,
		"position": Vector2(data.player.position.x, data.player.position.y),
		"is_loading_save": true,
		"init": func (): 
			world_stats = data.world_stats
			player_stats.from_dict(data.stats)
	})

func new_game() -> void:
	player_combat_state = {} 
	change_scene("res://Worlds/home.tscn", {
		"init": func ():
			world_stats = {}
			player_stats.from_dict(default_player_stats)
	})
	
func back_to_title() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	change_scene("res://ui/title_screen.tscn")
	
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)
