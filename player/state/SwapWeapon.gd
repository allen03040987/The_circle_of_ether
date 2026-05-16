class_name SwapWeaponState
extends State 

func enter(_msg := {}) -> void:
	# 進入狀態時，直接播放動畫
	player.play_safe_anim("swap_weapon")

func physics_update(delta: float) -> void:
	# ==========================================
	# 🛡️ 解決滑行 Bug：物理煞車接管
	# ==========================================
	if player.is_on_floor():
		# 地面切換：快速煞車至停止
		player.velocity.x = move_toward(player.velocity.x, 0.0, player.FLOOR_ACCELERATION * delta)
	else:
		# 空中切換：保留微小的滑行慣性
		player.velocity.x = move_toward(player.velocity.x, 0.0, player.FLOOR_ACCELERATION * 0.2 * delta)

	# 處理重力
	player.velocity.y += player.default_gravity * delta

	# 🌟 嚴守位移最高指導原則：絕對只能用 custom_move_and_slide
	player.custom_move_and_slide()

	# ==========================================
	# 🎬 解決卡死與回不去 Bug：自然過渡
	# ==========================================
	# 如果動畫播完了，或者被異常切換了，自然回歸日常狀態
	if not player.animation_player.is_playing() or player.animation_player.current_animation != "swap_weapon":
		if player.is_on_floor():
			state_machine.transition_to("Idle")
		else:
			state_machine.transition_to("Fall")
