class_name Talisman
extends Weapon
## 測試專用白板武器：符咒 (Talisman)

const WEAPON_ID: String = "talisman"

var combo_step: int = 0
var is_attacking: bool = false
var step_cooldown: float = 0.0

func _ready() -> void:
	if owner != null:
		if not owner.is_node_ready(): await owner.ready
		player = owner

# ==========================================
# 🎬 實作 Weapon.gd 合約接口
# ==========================================
func start_light_attack() -> void:
	if step_cooldown > 0: return
	step_cooldown = 0.15
	is_attacking = true
	
	combo_step += 1
	if combo_step > 3: combo_step = 1 # 簡單的三段循環
	
	print("📜 [符咒] 發動普攻第 ", combo_step, " 段！")
	player.play_safe_anim("katana/attack_" + str(combo_step))

func start_heavy_attack() -> void:
	if step_cooldown > 0: return
	step_cooldown = 0.15
	is_attacking = true
	combo_step = 10
	print("💥 [符咒] 發動重擊 (戰技)！")
	player.play_safe_anim("katana/attack_c1")

func start_ultimate() -> void:
	step_cooldown = 0.15
	is_attacking = true
	combo_step = 80
	print("🌟 [符咒] 領域展開！大招發動！")
	player.play_safe_anim("katana/attack_ult")

# ==========================================
# 🏃 物理與狀態控制
# ==========================================
func get_current_velocity(delta: float) -> Vector2:
	if not is_attacking: return player.velocity
	# 簡單的地面煞車摩擦力
	var new_x = move_toward(player.velocity.x, 0.0, player.FLOOR_ACCELERATION * delta)
	return Vector2(new_x, player.velocity.y)

func is_handling_gravity() -> bool:
	return false

func is_attack_finished() -> bool:
	if not is_attacking: return true
	if not player.animation_player.is_playing():
		player.is_input_locked = false
		is_attacking = false
		step_cooldown = 0.0
		return true
	return false

func cancel_attack() -> void:
	player.is_input_locked = false
	is_attacking = false
	combo_step = 0
	step_cooldown = 0.0
	print("🛑 [符咒] 攻擊被打斷！")

func requires_sheath() -> bool:
	return false # 符咒不需要刀鞘

func update_timers_only(delta: float) -> void:
	if step_cooldown > 0: step_cooldown -= delta
