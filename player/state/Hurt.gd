extends State
class_name PlayerHurtState

func enter() -> void:
	player.is_ult_requested = false
	player.is_combo_requested = false
	player.is_heavy_requested = false
	
	if player.scabbard:
		player.scabbard.fade_in()
	
	var hurtbox = player.get_node_or_null("Graphics/Hurtbox")
	if hurtbox:
		hurtbox.set_deferred("monitorable", false)
		hurtbox.set_deferred("monitoring", false)
	
	player.animation_player.stop()
	player.play_safe_anim("hurt")
	
	if player.pending_damage:

		var d_kb = player.pending_damage["knockback_force"]
		player.velocity = d_kb
		
		if not is_zero_approx(d_kb.x):
			player.direction = player.Direction.LEFT if d_kb.x > 0 else player.Direction.RIGHT
		
		player.pending_damage = null
		
	
	
	if CombatManager.has_method("apply_hitstop"):
		CombatManager.apply_hitstop(0.05, 0.05)

func physics_update(delta: float) -> void:
	# 🌟 核心修復 1：同狀態連續受擊強制重啟
	if player.pending_damage:
		enter()
		return

	if player.stats.health <= 0:
		if is_zero_approx(player.velocity.x) and player.is_on_floor(): 
			state_machine.transition_to("Dying")
		_apply_hurt_physics(delta)
		return 
		
	_apply_hurt_physics(delta)

	if not player.animation_player.is_playing():
		# 🌟 核心修復 3：空中受擊解鎖！
		# 如果動畫播完了但人還在空中，直接切換到 Fall 狀態，不要死等落地！
		if not player.is_on_floor():
			state_machine.transition_to("Fall")
		elif is_zero_approx(player.velocity.x):
			state_machine.transition_to("Idle")

func _apply_hurt_physics(delta: float) -> void:
	var knockback_friction = player.RUN_SPEED * 3.0 
	player.velocity.x = move_toward(player.velocity.x, 0.0, knockback_friction * delta)
	
	var max_safe_speed = player.RUN_SPEED * 2.0
	player.velocity.x = clamp(player.velocity.x, -max_safe_speed, max_safe_speed)
	
	player.velocity.y += player.default_gravity * delta
	player.custom_move_and_slide()

func exit() -> void:
	var hurtbox = player.get_node_or_null("Graphics/Hurtbox")
	if hurtbox:
		hurtbox.set_deferred("monitorable", true)
		hurtbox.set_deferred("monitoring", true)
