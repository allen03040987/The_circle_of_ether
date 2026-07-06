class_name SickleHook
extends Node2D

var fly_direction: Vector2 = Vector2.RIGHT
var direction: int = 1
var thrower: Node = null
var speed: float = 1100.0
var max_distance: float = 500.0

var _traveled_distance: float = 0.0

enum HookState { FLY_OUT, RETURN, STUCK, FADING }
var current_state: HookState = HookState.FLY_OUT

var stuck_target: Node2D = null
var stuck_offset: Vector2 = Vector2.ZERO
var is_wall_hook: bool = false
@onready var hitbox: Hitbox = $Hitbox

# 🌟 新增：鎖鏈視覺線條
var chain_line: Line2D

func _ready() -> void:
	rotation = fly_direction.angle()
	
	# 🌟 核心修復：如果往左飛，把 Y 軸翻轉，抵銷 180 度的上下顛倒！
	if fly_direction.x < 0:
		scale.y = -1
		
	if has_node("WallDetector"):
		$WallDetector.body_entered.connect(_on_wall_entered)
		
	# 🌟 程式動態生成一條鎖鏈線條
	chain_line = Line2D.new()
	chain_line.width = 2.0
	chain_line.default_color = Color(0.7, 1.5, 0.5, 0.8) # 青綠色，與火花統一
	chain_line.z_index = -1 # 讓線條藏在鐮刀圖案的後面
	
	# 如果你有鎖鏈的圖片，把註解打開並載入你的圖片即可變成真實鎖鏈！
	chain_line.texture = preload("res://player/Sickle/chain.png")
	chain_line.texture_mode = Line2D.LINE_TEXTURE_TILE
	
	add_child(chain_line)

func _process(_delta: float) -> void:
	if is_instance_valid(chain_line) and is_instance_valid(thrower):
		chain_line.clear_points()
		# 點 0：鐮刀本體的中心點
		chain_line.add_point(Vector2.ZERO)
		
		# 🌟 核心修復：鎖鏈連回玩家的終點也必須吃「動態鏡像翻轉」！
		# 完全對齊主腳本的 Vector2(10.0 * direction, -30.0)
		var player_chest_offset = Vector2(10.0 * direction, -30.0)
		var thrower_local_pos = to_local(thrower.global_position + player_chest_offset)
		
		# 點 1：玩家胸口動態發射點的相對座標
		chain_line.add_point(thrower_local_pos)

func _physics_process(delta: float) -> void:
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0.0 else 1.0
	
	match current_state:
		HookState.FLY_OUT:
			var step = fly_direction * (speed * speed_mult) * delta
			global_position += step
			_traveled_distance += step.length()
			
			if _traveled_distance >= max_distance:
				current_state = HookState.RETURN
				_disable_hitbox() 
		
		HookState.RETURN:
			if is_instance_valid(thrower):
				var target_pos = thrower.global_position + Vector2(0, -20)
				var dir = global_position.direction_to(target_pos)
				var step = dir * (speed * 1.5 * speed_mult) * delta 
				global_position += step
				
				if global_position.distance_to(target_pos) <= step.length() * 1.5 or global_position.distance_to(target_pos) < 20.0:
					queue_free()
			else:
				queue_free()
				
		HookState.STUCK:
			if is_wall_hook:
				pass # 🌟 牆壁是死物，不需要跟隨，永遠留在原地！
			elif is_instance_valid(stuck_target):
				global_position = stuck_target.global_position + stuck_offset
			else:
				fade_and_die() # 只有怪物死掉才消失

func stick_to_target(target: Node2D) -> void:
	current_state = HookState.STUCK 
	stuck_target = target
	stuck_offset = global_position - target.global_position
	_disable_hitbox()

func _on_wall_entered(body: Node2D) -> void:
	if current_state == HookState.FLY_OUT:
		current_state = HookState.STUCK
		stuck_target = null 
		is_wall_hook = true # 🌟 核心修復：大喊一聲「我是牆壁！不要殺我！」
		_disable_hitbox()
		
		if is_instance_valid(thrower) and thrower.current_weapon.has_method("trigger_wall_hook"):
			thrower.current_weapon.trigger_wall_hook(self)

func fade_and_die() -> void:
	if current_state == HookState.FADING: return 
	current_state = HookState.FADING 
	
	# 🌟 終極安全鎖：如果節點正在被傳送門拔除，絕對不准建立 Tween，直接自我銷毀！
	if not is_inside_tree():
		queue_free()
		return
		
	var tween = create_tween()
	if tween:
		tween.tween_property(self, "modulate:a", 0.0, 0.3)
		tween.tween_callback(queue_free)
	else:
		queue_free()

func _disable_hitbox() -> void:
	if hitbox:
		for child in hitbox.get_children():
			if child is CollisionShape2D:
				child.set_deferred("disabled", true)
