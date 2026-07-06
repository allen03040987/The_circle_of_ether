class_name BossHurtState
extends BossState

func enter() -> void:
	boss.disable_hitbox()

	# 🌟 記錄硬直空窗開始的時間點：只有「第一次」進入 Hurt 會真的啟動計時，
	# 期間內再被打斷不會延長懲罰，避免玩家無限連續打斷讓 BOSS 永遠出不了招
	boss.trigger_hurt_gate()

	# 擊退力已經在 BossNaihe._on_hurtbox_hurt() 統一套用（含後續每一下的重新墊高），
	# 這裡只負責挑動畫，不再碰 velocity
	var anim_name = "hurt_1" if randf() < 0.5 else "hurt_2"
	boss.play_safe_anim(anim_name)

func physics_update(delta: float) -> void:
	# 🌟 擊退摩擦力沿用 Slime 的手感：比一般移動的煞車更快收斂
	var knockback_friction = boss.max_speed * 3.0
	boss.velocity.x = move_toward(boss.velocity.x, 0.0, knockback_friction * delta)
	boss.velocity.y += boss.default_gravity * delta
	boss.custom_move_and_slide()

	# 🌟 硬直懲罰閘門到期（且真的落地）：強制立刻打斷 Hurt 去決策下一招
	# 這裡的 is_on_floor() 是這一幀 custom_move_and_slide() 剛算完的最新結果，
	# 不會像寫在挨打當下的檢查那樣，吃到連段彈跳途中殘留的舊幀擦地髒值
	if boss.is_hurt_gate_open():
		state_machine.transition_to("Decision")
		var decision_state = state_machine.states.get("decision")
		if decision_state:
			decision_state.force_next_decision()
		return

	# 閘門還沒到期：動畫播完且已落地，先回 Decision 播 idle 繼續空窗期（還不會真的出招）
	if not boss.animation_player.is_playing() and boss.is_on_floor():
		state_machine.transition_to("Decision")
