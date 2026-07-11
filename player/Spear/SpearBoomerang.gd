class_name SpearBoomerang
extends Node2D
## 迴旋長槍投射物 (Boomerang Projectile) - 幽靈防斷連版

@export var speed: float = 650.0             # 飛出去的速度
@export var max_distance: float = 320.0      # 最遠飛行距離
@export var return_speed_mult: float = 1.2   # 飛回來時的加速倍率
@export var wall_collision_mask: int = 1     # 去程撞牆反彈用的偵測層（Environment）

var direction: int = 1
var thrower: Node2D = null
var weapon: Spear = null ## 🌟 接住的瞬間要通知本體，讓收槍強化技的判定窗開起來
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
	# 這個保底路徑代表槍沒有正常被接住，要記得解鎖武器，不然玩家會永遠卡在丟槍狀態
	get_tree().create_timer(5.0).timeout.connect(func():
		if is_instance_valid(self):
			_notify_lost_if_needed()
			queue_free()
	)

func _physics_process(delta: float) -> void:
	# 🌟 如果已經接住了，停止移動與旋轉，靜靜當個幽靈等 Hitbox 下班
	if is_caught: return 

	if not is_instance_valid(thrower):
		_notify_lost_if_needed()
		queue_free()
		return

	if sprite:
		sprite.rotation += rotation_speed * direction * delta

	if not is_returning:
		# 🪃 階段一：純靠數學往前飛 (完全借鑑劍氣)，撞到牆會反彈
		var step = speed * delta
		if _is_wall_ahead(step):
			direction *= -1

		global_position.x += direction * step
		traveled_distance += step

		if traveled_distance >= max_distance:
			is_returning = true

	else:
		# 🪃 階段二：飛回主人手中，穿牆無視任何阻擋
		var target_pos = thrower.global_position + Vector2(0, -30)
		var move_dir = (target_pos - global_position).normalized()
		
		global_position += move_dir * (speed * return_speed_mult) * delta
		
		# 🌟 核心修復：回到主人身邊時，執行「幽靈化」！
		if global_position.distance_to(target_pos) < 50.0:
			catch_boomerang()

## 去程專用：前方 probe_dist 距離內有沒有撞到牆（Environment 層），有的話回傳 true 讓外面反彈方向
func _is_wall_ahead(probe_dist: float) -> bool:
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(global_position, global_position + Vector2(direction * (probe_dist + 6.0), 0))
	query.collision_mask = wall_collision_mask
	return space_state.intersect_ray(query).size() > 0

const GHOST_COLOR_INTERRUPTED := Color(1.0, 0.25, 0.2, 0.7) ## 玩家主動打斷 (提早誤按收槍)：紅色殘影
const GHOST_COLOR_CAUGHT := Color(0.3, 1.0, 0.4, 0.7)        ## 正常飛回觸碰到玩家：綠色殘影

# ==========================================
# 👻 幽靈化邏輯：等待 Hitbox 結算
# ==========================================
func catch_boomerang() -> void:
	_go_ghost(GHOST_COLOR_CAUGHT)

	# 🌟 十字火花只在「這次接槍真的有機會施放強化技」時才出現——
	# 玩家在空中摸到槍不會進入強化技的轉身流程，這時候就不必噴這個特效
	if is_instance_valid(thrower) and thrower.has_method("spawn_anim_vfx") and thrower.has_method("is_on_floor") and thrower.is_on_floor():
		thrower.spawn_anim_vfx("Cross slash sparks", 0.0, -40.0, Vector2(1.5, 0.4), 0.0, Color(1, 1, 1, 1), Color(1, 1, 1, 1), false, 2, 1.0)

	# 🌟 通知本體：槍接住了，開啟收槍強化技判定窗
	if is_instance_valid(weapon) and weapon.has_method("notify_spear_caught"):
		weapon.notify_spear_caught()

	# ⚡ 絕對不呼叫 queue_free()！
	# 讓這顆隱形的節點繼續活著，Hitbox 裡面的 sticky_multi_hit 迴圈就能無情地把剩下的傷害跳完！
	# 等到 5 秒時間一到，_ready 裡面的計時器自然會把它收走。

## 玩家在槍還沒飛回來前就先誤按攻擊鍵：本體會強制呼叫這個把槍立刻拉回、消失——
## 跟正常接住的差別只在於「不」通知本體開強化技判定窗（誤按沒有強化技），殘影顏色也不同
func force_early_recall() -> void:
	if is_caught: return
	_go_ghost(GHOST_COLOR_INTERRUPTED)

func _go_ghost(ghost_color: Color) -> void:
	is_caught = true

	# 🌟 用 global_transform 的縮放而不是 sprite.scale：Sprite2D 是掛在有自己縮放 (0.5) 的 Graphics 節點底下，
	# 只拿 sprite 自己的 local scale 會漏掉父節點那層，殘影就會比實際圖像大一圈
	if is_instance_valid(sprite):
		CombatManager.spawn_ghost(sprite, global_position, sprite.global_transform.get_scale(), ghost_color)

	hide() # 隱藏迴旋鏢外觀

	# 關閉觸發器，不再抓取新怪物
	hitbox.set_deferred("monitoring", false)
	hitbox.set_deferred("monitorable", false)

## 保底用：槍沒有正常被接住就消失了（保底計時器到期、或丟槍者中途失效），只解鎖武器不開強化技窗口
func _notify_lost_if_needed() -> void:
	if is_caught: return
	if is_instance_valid(weapon) and weapon.has_method("notify_spear_lost"):
		weapon.notify_spear_lost()
