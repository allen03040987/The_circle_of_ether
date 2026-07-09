extends State

# ==========================================
# 🎬 狀態生命週期：進入狀態
# ==========================================
func enter() -> void:
	# 🌟 指令：播放待機動畫。
	player.play_safe_anim("idle")
	player.is_input_locked = false
# ==========================================
# 🏃 物理更新 (每秒 60 次)
# ==========================================
func physics_update(delta: float) -> void:
	# 1. 🛑 處理摩擦力：即使玩家放開鍵盤，角色也會有一點點「殘餘慣性」。
	# 我們讓速度朝著 0.0 前進，前進的步長受 FLOOR_ACCELERATION 影響。
	player.velocity.x = move_toward(player.velocity.x, 0.0, player.FLOOR_ACCELERATION * delta)
	
	# 2. 🍎 處理重力：即使不動，也要保持向下的力，確保踩在地上。
	player.velocity.y += player.default_gravity * delta
	
	# 3. 🚀 執行移動：呼叫玩家自定義的移動函式（確保時停/緩速正常）。
	player.custom_move_and_slide()
	
	# ==========================================
	# 🚦 狀態切換決策 (由上而下判定)
	# ==========================================
	
	# ⚠️ 邊緣檢測：如果突然腳空了 (例如平台消失)，立刻啟動郊狼時間。
	if not player.is_on_floor():
		player.coyote_timer.start() 
		state_machine.transition_to("Fall")
		return
		
	# ⚡ 優先級 1：跳躍與閃避 (最高速反應)
	if player.jump_request_timer.time_left > 0:
		state_machine.transition_to("Jump")
		return
		
	if player.slide_request_timer.time_left > 0 and player.stats.energy >= 3:
		if player.slide_cooldown_timer.is_stopped():
			state_machine.transition_to("Slide")
			return

	if player.guard_request_timer.time_left > 0:
		state_machine.transition_to("Guard")
		return

	# ⚔️ 優先級 2：戰鬥大門 (偵測 Player.gd 緩衝過的攻擊請求)
	if player.is_combo_requested or player.is_heavy_requested:
		state_machine.transition_to("WeaponAttack")
		return
	
	# 🚶 優先級 3：移動偵測
	var movement := Input.get_axis("move_left", "move_right")
	if not is_zero_approx(movement):
		state_machine.transition_to("Run")
