class_name World 
extends Node2D 

@export_group("地圖設定")
@export var is_base: bool = false

# 🌟 新增：相機與視野設定
@export_group("相機視野 (Zoom)")
## 預設的視野大小 (數值越小看越遠，預設是 Vector2(1,1))
@export var default_zoom: Vector2 = Vector2(0.85, 0.85) 
## BOSS 戰專用的超廣角視野 
@export var boss_zoom: Vector2 = Vector2(0.65, 0.65)

@export_group("音效設定")
@export var level_bgm: AudioStream
@export var bgm_volume: float = -10.0

@onready var tile_map: TileMap = $TileMap
@onready var camera_2d: Camera2D = $Player/Camera2D
@onready var player: Player = $Player


# ==========================================
# ⚙️ 初始化 (Initialization)
# ==========================================
func _ready() -> void:
	var used := tile_map.get_used_rect().grow(-1)
	var tile_size := tile_map.tile_set.tile_size
	
	camera_2d.limit_top = used.position.y * tile_size.y
	camera_2d.limit_right = used.end.x * tile_size.x
	camera_2d.limit_bottom = used.end.y * tile_size.y
	camera_2d.limit_left = used.position.x * tile_size.x
	camera_2d.reset_smoothing()
	
	# 🌟 改由戰鬥管理器統一設定並紀錄初始基礎視野
	CombatManager.update_base_zoom(default_zoom, 0.0)
	
	if level_bgm:
		AudioManager.play_bgm(level_bgm, bgm_volume)
	
	if player:
		player.update_movement_by_scene(is_base)

# ==========================================
# 🗺️ 玩家與場景管理 (Player & Scene Management)
# ==========================================
## 切換地圖/重生時，更新玩家位置並重置相機
func update_player(pos: Vector2, direction: Player.Direction) -> void:
	if not is_node_ready():
		await ready
	player.global_position = pos
	player.direction = direction
	
	# 傳送瞬間停用平滑處理，防止相機穿牆閃爍
	camera_2d.reset_smoothing() 
	camera_2d.force_update_scroll() 
	
# ==========================================
# 💾 場景狀態存讀檔 (Save/Load Scene State)
# ==========================================
## 將當前地圖的狀態 (如怪物存活名單) 打包成字典
func to_dict() -> Dictionary:
	var enemies_alive := []
	
	for node in get_tree().get_nodes_in_group("enemies"):
		# 取得該敵人相對於當前場景根節點的唯一路徑
		var path := get_path_to(node) as String
		enemies_alive.append(path)
		
	return {
		enemies_alive = enemies_alive
	}
	
## 根據傳入的字典還原場景狀態 (剔除已死的怪物)
func from_dict(dict: Dictionary) -> void:
	for node in get_tree().get_nodes_in_group("enemies"):
		var path := get_path_to(node) as String 
		
		# 若不再 enemies 名單上，代表之前已經死了，立刻清除
		if path not in dict.enemies_alive: 
			node.queue_free()

# ==========================================
# 🎥 動態相機控制 (Camera Control)
# ==========================================
## 切換 BOSS 戰鬥視角 (is_boss_fight: true 變廣角，false 變回原樣)
## 切換 BOSS 戰鬥視角
func set_boss_camera_mode(is_boss_fight: bool) -> void:
	var target_zoom = boss_zoom if is_boss_fight else default_zoom
	# 🌟 直接委託仲裁官，這樣就不會跟大招特寫打架！
	CombatManager.update_base_zoom(target_zoom, 1.5)
