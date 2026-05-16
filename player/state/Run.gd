extends State

# ==========================================
# 🎬 狀態生命週期 (State Lifecycle)
# ==========================================
func enter() -> void:
	# 進入狀態的第一瞬間，先確認玩家現在是想跑還是想走
	if player.is_walking:
		player.play_safe_anim("walking")
	else:
		player.play_safe_anim("running")
		
	player.is_input_locked = false
	
func physics_update(delta: float) -> void:
	# 判斷有無輸入方向
	var movement := Input.get_axis("move_left", "move_right")
	
	if is_zero_approx(movement):
		state_machine.transition_to("Idle")
		return
		
	# 轉向邏輯
	player.direction = player.Direction.RIGHT if movement > 0 else player.Direction.LEFT
	
	# ==========================================
	# 🌟 動態速度計算：依據 is_walking 決定極速
	# ==========================================
	var current_max_speed = player.WALK_SPEED if player.is_walking else player.RUN_SPEED
	
	player.velocity.x = move_toward(player.velocity.x, movement * current_max_speed, player.FLOOR_ACCELERATION * delta)
	
	player.custom_move_and_slide()
	
	# ==========================================
	# 🚦 狀態切換決策 (State Transitions)
	# ==========================================
	
	# 邊緣判定：腳離開地板，啟動郊狼時間並下墜
	if not player.is_on_floor():
		player.coyote_timer.start() 
		state_machine.transition_to("Fall")
		return
		
	# 預輸入：跳躍
	if player.jump_request_timer.time_left > 0:
		state_machine.transition_to("Jump")
		return
		
	# 預輸入：閃避
	if player.slide_request_timer.time_left > 0 and player.stats.energy >= 3:
		if player.slide_cooldown_timer.is_stopped():
			state_machine.transition_to("Slide")
			return
		
	# ==========================================
	# ⚔️ 戰鬥大門 (統一聽從 Player 的緩衝請求)
	# ==========================================
	# 絕對不准在這裡使用 Input.is_action_pressed！
	# 所有的輸入資格審查與緩衝，都已經在 Player.gd 的 _unhandled_input 處理完畢了。
	
	if player.is_combo_requested or player.is_heavy_requested or player.is_ult_requested:
		state_machine.transition_to("WeaponAttack")
		return
		
	# 如果輸入歸零，且速度也降到接近 0 (煞車完成)，就回到待機
	if is_zero_approx(movement) and is_zero_approx(player.velocity.x):
		state_machine.transition_to("Idle")
