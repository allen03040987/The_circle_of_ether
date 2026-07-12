extends State
class_name PlayerLaunchedState

var has_landed: bool = false 

func enter() -> void:
	if player.scabbard:
		player.scabbard.fade_in()
	
	has_landed = false
	
	# 🌟 統一關閉判定框，防止被奇怪的持續傷害卡死
	var hurtbox = player.get_node_or_null("Graphics/Hurtbox")
	if hurtbox:
		hurtbox.set_deferred("monitorable", false)
		hurtbox.set_deferred("monitoring", false)
	
	if player.pending_damage:
		# 這裡正確執行扣血與擊退！
		player.velocity = player.pending_damage.knockback_force
		
		player.direction = player.Direction.LEFT if player.pending_damage.knockback_force.x > 0 else player.Direction.RIGHT
		player.pending_damage = null
		
	player.play_safe_anim("launched_up") 
	

func physics_update(delta: float) -> void:
	# 🌟 核心修復 1：同狀態被連續擊打的「強制重啟」！
	# 如果無敵時間結束，在空中又被打到，直接強制重新執行 enter()！
	if player.pending_damage:
		enter() 
		return

	if player.stats.health <= 0 and player.is_on_floor() and player.velocity.y >= 0 and is_zero_approx(player.velocity.x):
		state_machine.transition_to("Dying")
		return

	if player.is_on_floor():
		var knockback_friction = player.RUN_SPEED * 2.0 
		player.velocity.x = move_toward(player.velocity.x, 0.0, knockback_friction * delta)
		
	var max_safe_speed = player.RUN_SPEED * 2.0
	player.velocity.x = clamp(player.velocity.x, -max_safe_speed, max_safe_speed)
	
	# 🌟 刪除重複的重力，只留一行！
	player.velocity.y += player.default_gravity * delta
	player.custom_move_and_slide()
	
	if not player.is_on_floor():
		if player.velocity.y > 0 and player.animation_player.current_animation != "launched_down":
			player.play_safe_anim("launched_down")
	else:
		if not has_landed:
			has_landed = true
			player.play_safe_anim("launched_slide")

	if player.is_on_floor() and player.velocity.y >= 0 and is_zero_approx(player.velocity.x) and player.stats.health > 0:
		if not player.animation_player.is_playing():
			state_machine.transition_to("Idle")

# 🌟 離開時記得把判定框開回來
func exit() -> void:
	# 🛡️ 浮空整段(up/down/slide)已經交給 Player.is_in_hitstun() 判斷無敵，這裡落地站穩要離場時再補一段緩衝
	player.grant_invincibility(0.2)

	var hurtbox = player.get_node_or_null("Graphics/Hurtbox")
	if hurtbox:
		hurtbox.set_deferred("monitorable", true)
		hurtbox.set_deferred("monitoring", true)
