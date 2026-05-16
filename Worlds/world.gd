class_name World 
extends Node2D 

@export_group("地圖設定")
## 勾選此項代表該場景是基地/安全區，會強制玩家行走
@export var is_base: bool = false

@onready var tile_map: TileMap = $TileMap
@onready var camera_2d: Camera2D = $Player/Camera2D
@onready var player: Player = $Player


# ==========================================
# ⚙️ 初始化 (Initialization)
# ==========================================
func _ready() -> void:
	# 根據 TileMap 的實際大小限制攝影機邊界
	var used := tile_map.get_used_rect().grow(-1)
	var tile_size := tile_map.tile_set.tile_size
	
	camera_2d.limit_top = used.position.y * tile_size.y
	camera_2d.limit_right = used.end.x * tile_size.x
	camera_2d.limit_bottom = used.end.y * tile_size.y
	camera_2d.limit_left = used.position.x * tile_size.x
	camera_2d.reset_smoothing()
	# 通知玩家根據地圖屬性初始化移動模式
	if player:
		player.update_movement_by_scene(is_base)

# ==========================================
# 🗺️ 玩家與場景管理 (Player & Scene Management)
# ==========================================
## 切換地圖/重生時，更新玩家位置並重置相機
func update_player(pos: Vector2, direction: Player.Direction) -> void:
	player.global_posidtion = pos
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
