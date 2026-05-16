class_name SpearBoomerang
extends Node2D
## 迴旋長槍投射物 (Boomerang Projectile) - 幽靈防斷連版

@export var speed: float = 600.0             # 飛出去的速度
@export var max_distance: float = 180.0      # 最遠飛行距離
@export var return_speed_mult: float = 1.2   # 飛回來時的加速倍率

var direction: int = 1
var thrower: Node2D = null
var is_returning: bool = false
var is_caught: bool = false # 🌟 新增：是否已經回到手上了？
var traveled_distance: float = 0.0 # 🌟 採用劍氣的絕對距離計算法
var rotation_speed: float = 50.0

@onready var hitbox: Hitbox = $Hitbox
# 🌟 確保路徑與你的劍氣一致
@onready var sprite: Sprite2D = $Graphics/Sprite2D 

func _ready() -> void:
	top_level = true 
	
	# 跟劍氣一樣，設定 owner 讓火花知道方向
	hitbox.owner = self
	
	# 🌟 5 秒後強制安全銷毀 (這足夠讓 5 段黏著打擊完美打完！)
	get_tree().create_timer(5.0).timeout.connect(func():
		if is_instance_valid(self):
			queue_free()
	)

func _physics_process(delta: float) -> void:
	# 🌟 如果已經接住了，停止移動與旋轉，靜靜當個幽靈等 Hitbox 下班
	if is_caught: return 

	if not is_instance_valid(thrower):
		queue_free()
		return

	if sprite:
		sprite.rotation += rotation_speed * direction * delta

	if not is_returning:
		# 🪃 階段一：純靠數學往前飛 (完全借鑑劍氣)
		var step = speed * delta
		global_position.x += direction * step
		traveled_distance += step
		
		if traveled_distance >= max_distance:
			is_returning = true
			
	else:
		# 🪃 階段二：穿牆飛回主人手中
		var target_pos = thrower.global_position + Vector2(0, -30) 
		var move_dir = (target_pos - global_position).normalized()
		
		global_position += move_dir * (speed * return_speed_mult) * delta
		
		# 🌟 核心修復：回到主人身邊時，執行「幽靈化」！
		if global_position.distance_to(target_pos) < 50.0:
			catch_boomerang()

# ==========================================
# 👻 幽靈化邏輯：等待 Hitbox 結算
# ==========================================
func catch_boomerang() -> void:
	is_caught = true
	hide() # 隱藏迴旋鏢外觀
	
	# 關閉觸發器，不再抓取新怪物
	hitbox.set_deferred("monitoring", false) 
	hitbox.set_deferred("monitorable", false)
	
	# ⚡ 絕對不呼叫 queue_free()！
	# 讓這顆隱形的節點繼續活著，Hitbox 裡面的 sticky_multi_hit 迴圈就能無情地把剩下的傷害跳完！
	# 等到 5 秒時間一到，_ready 裡面的計時器自然會把它收走。
