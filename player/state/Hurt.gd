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
		
		# 🌟 修復 1：刪除雙倍扣血！(Player.gd 已經扣過血了，這裡不准再扣！)
		
		player.velocity = d_kb
		
		if not is_zero_approx(d_kb.x):
			player.direction = player.Direction.LEFT if d_kb.x > 0 else player.Direction.RIGHT
		
		player.pending_damage = null
		
	player.invincible_timer.start(0.25)
	
	# 🌟 修復 2：統一把卡肉交給 CombatManager！
	# (刪除你原本寫的 Engine.time_scale 與 await，防止破壞領域展開與全域時停)
	if CombatManager.has_method("apply_hitstop"):
		CombatManager.apply_hitstop(0.05, 0.05)

func physics_update(delta: float) -> void:
	if player.stats.health <= 0:
		if is_zero_approx(player.velocity.x) and player.is_on_floor(): 
			state_machine.transition_to("Dying")
		_apply_hurt_physics(delta)
		return 
		
	_apply_hurt_physics(delta)

	if not player.animation_player.is_playing():
		if player.is_on_floor() and is_zero_approx(player.velocity.x):
			state_machine.transition_to("Idle")

func _apply_hurt_physics(delta: float) -> void:
	var knockback_friction = player.RUN_SPEED * 3.0 
	player.velocity.x = move_toward(player.velocity.x, 0.0, knockback_friction * delta)
	
	# 🌟 終極修復 3：萬能限速器 (Velocity Clamp)！
	# 不管物理引擎怎麼暴走，受傷時的速度絕對不准超過 RUN_SPEED 的 2 倍！
	var max_safe_speed = player.RUN_SPEED * 2.0
	player.velocity.x = clamp(player.velocity.x, -max_safe_speed, max_safe_speed)
	
	player.velocity.y += player.default_gravity * delta
	player.custom_move_and_slide()

func exit() -> void:
	var hurtbox = player.get_node_or_null("Graphics/Hurtbox")
	if hurtbox:
		hurtbox.set_deferred("monitorable", true)
		hurtbox.set_deferred("monitoring", true)
