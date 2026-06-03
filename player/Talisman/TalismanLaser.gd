class_name TalismanLaser
extends Area2D
## 符咒強化普攻投射物：追蹤激光條

@onready var hitbox: Hitbox = $Hitbox

# 將原本的 tracking_range 替換成這兩個矩形變數
@export var speed: float = 1100.0            
@export var tracking_length: float = 600.0   # 雷達向前的偵測距離
@export var tracking_width: float = 400.0    # 雷達的寬度 (上下範圍)
@export var steer_force: float = 8.0        

var fly_direction: Vector2 = Vector2.RIGHT
var direction: int = 1 
var target_enemy: Node2D = null
var is_tracking: bool = true
var lifetime: float = 0.5                    
var thrower: Node2D = null
var _is_dying: bool = false

func _ready() -> void:
	# 1. 綁定命中信號，一旦打到人立刻解除追蹤
	if hitbox:
		hitbox.hit.connect(_on_laser_hit)
	
	# 2. 出生時立刻搜尋範圍內最近的敵人
	_find_nearest_target()

func _process(delta: float) -> void:
	# ==========================================
	# 🌟 核心修復：壽命倒數與漸出觸發機制
	# ==========================================
	if not _is_dying:
		lifetime -= delta
		if lifetime <= 0.0:
			_is_dying = true
			
			# 💥 安全防護：漸出期間立刻關閉 Hitbox 判定，避免造成邊消失邊打人的幽靈傷害
			if is_instance_valid(hitbox):
				hitbox.set_deferred("monitoring", false)
				hitbox.set_deferred("monitorable", false)
			
			# 🎬 建立漸出 Tween 
			var tween = create_tween()
			tween.tween_property(self, "modulate:a", 0.0, 0.15) # 0.15 秒內優雅淡出
			tween.tween_callback(queue_free)

	# ==========================================
	# 🎯 追蹤邏輯 (只有在未進入漸出狀態時才允許修正航向)
	# ==========================================
	if is_tracking and not _is_dying:
		if is_instance_valid(target_enemy):
			var dist = global_position.distance_to(target_enemy.global_position)
			
			if dist <= tracking_length:
				var target_dir = (target_enemy.global_position - global_position).normalized()
				fly_direction = fly_direction.move_toward(target_dir, steer_force * delta).normalized()
			else:
				target_enemy = null 
		else:
			_find_nearest_target()

	# 🌟 同步更新整數面向
	direction = 1 if fly_direction.x >= 0 else -1

	# 🌟 移動與旋轉更新 (即使進入漸出，也會依照最後的殘留角度直線滑行，動態手感極佳)
	global_position += fly_direction * speed * delta
	rotation = fly_direction.angle()

func _find_nearest_target() -> void:
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	
	# 🌟 改用矩形形狀
	var rect = RectangleShape2D.new()
	# Godot 4 的 RectangleShape2D 使用 size (完整寬高)
	rect.size = Vector2(tracking_length, tracking_width)
	query.shape = rect
	
	# 🌟 核心數學：將矩形的中心點沿著飛行方向往前推一半的距離，並套用雷射當前的角度
	var center_offset = fly_direction * (tracking_length / 2.0)
	query.transform = Transform2D(fly_direction.angle(), global_position + center_offset)
	
	if is_instance_valid(hitbox):
		query.collision_mask = hitbox.collision_mask
		
	query.collide_with_areas = true
	query.collide_with_bodies = false
	
	var results = space_state.intersect_shape(query)
	var min_dist = tracking_length * 2.0 # 給一個夠大的初始值
	var nearest: Node2D = null
	
	for res in results:
		var area = res.collider
		if area is CollisionObject2D and "hurt" in area:
			var victim = area.owner if is_instance_valid(area.owner) else area
			
			if is_instance_valid(thrower) and victim == thrower:
				continue
				
			var dist = global_position.distance_to(area.global_position)
			if dist < min_dist:
				min_dist = dist
				nearest = area 
				
	target_enemy = nearest

func _on_laser_hit(_hurtbox: Node) -> void:
	# 🌟 核心需求：命中敌人後，激光絕不消失，清除追蹤鎖定，以當前殘留角度直線暴衝貫穿
	if is_tracking:
		is_tracking = false
		target_enemy = null
		print("⚡ [激光] 成功貫穿目標！解鎖追蹤，維持原角度直線推進。")
