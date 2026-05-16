extends State
class_name PlayerLaunchedState

var has_landed: bool = false 

func enter() -> void:
	# --- 1. 視覺與變數初始化 ---
	if player.scabbard:
		player.scabbard.fade_in()
	
	has_landed = false
	
	# --- 2. 結算傷害與擊退 ---
	if player.pending_damage:
		player.stats.health -= player.pending_damage.amount
		player.velocity = player.pending_damage.knockback_force
		
		player.direction = player.Direction.LEFT if player.pending_damage.knockback_force.x > 0 else player.Direction.RIGHT
		player.pending_damage = null
		
	player.play_safe_anim("launched_up") 
	player.invincible_timer.start(0.5)

func physics_update(delta: float) -> void:
	# 💀 最高優先級：死亡攔截
	if player.stats.health <= 0 and player.is_on_floor() and player.velocity.y >= 0 and is_zero_approx(player.velocity.x):
		state_machine.transition_to("Dying")
		return

	# ==========================================
	# 📐 物理計算
	# ==========================================
	if player.is_on_floor():
		var knockback_friction = player.RUN_SPEED * 2.0 
		player.velocity.x = move_toward(player.velocity.x, 0.0, knockback_friction * delta)
		
	player.velocity.y += player.default_gravity * delta
	# 防止被挑飛時產生全壘打
	var max_safe_speed = player.RUN_SPEED * 2.0
	player.velocity.x = clamp(player.velocity.x, -max_safe_speed, max_safe_speed)
	
	player.velocity.y += player.default_gravity * delta
	player.custom_move_and_slide()
	
	# ==========================================
	# 🎬 動畫無縫切換邏輯
	# ==========================================
	if not player.is_on_floor():
		if player.velocity.y > 0 and player.animation_player.current_animation != "launched_down":
			player.play_safe_anim("launched_down")
	else:
		if not has_landed:
			has_landed = true
			player.play_safe_anim("launched_slide")

	# ==========================================
	# 🚪 狀態結束判定
	# ==========================================
	if player.is_on_floor() and player.velocity.y >= 0 and is_zero_approx(player.velocity.x) and player.stats.health > 0:
		if not player.animation_player.is_playing():
			state_machine.transition_to("Idle")
