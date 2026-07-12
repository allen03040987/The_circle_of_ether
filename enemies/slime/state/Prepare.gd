extends SlimeState
## 退完距離後，站著等 prepare_wait_time，最後 warning_icon_lead_time 秒跳出警示圖示預告，時間到就跳撲

func enter() -> void:
	slime.velocity.x = 0
	slime.animation_player.play("idle")
	slime.show_attack_warning(slime.warning_icon, slime.prepare_wait_time - slime.warning_icon_lead_time)

func exit() -> void:
	slime.hide_attack_warning(slime.warning_icon)

func physics_update(delta: float) -> void:
	if check_death(): return
	var target = check_damage_interrupt()
	if target != "":
		state_machine.transition_to(target)
		return

	slime.velocity.y += slime.default_gravity * delta
	slime.custom_move_and_slide()

	if state_machine.state_time >= slime.prepare_wait_time:
		state_machine.transition_to("Attack")
