extends SlimeState
## 落地緩衝：跳撲落地後停頓 landing_recovery_time 秒才繼續巡邏，這段期間被打一樣會轉去 Hurt/Launched

func enter() -> void:
	slime.velocity.x = 0
	slime.animation_player.play("idle")

func physics_update(delta: float) -> void:
	if check_death(): return
	var target = check_damage_interrupt()
	if target != "":
		state_machine.transition_to(target)
		return

	slime.velocity.y += slime.default_gravity * delta
	slime.custom_move_and_slide()

	if state_machine.state_time >= slime.landing_recovery_time:
		state_machine.transition_to("Walk")
