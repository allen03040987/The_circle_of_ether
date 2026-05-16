extends State
## 跳躍狀態 (Jump State)
## 處理角色往上飛升的過程。當 Y 軸速度不再為負值 (到達頂點) 時，切換至下墜狀態。

# ==========================================
# 🎬 狀態生命週期：進入狀態
# ==========================================
func enter() -> void:
	player.play_safe_anim("jump")
	
	# 🚀 給予瞬間的向上爆發力
	player.velocity.y = player.JUMP_VELOCITY
	
	# 🛑 既然已經跳了，就把跳躍請求和郊狼時間的計時器關掉，防止重複觸發
	player.jump_request_timer.stop()
	player.coyote_timer.stop()

# ==========================================
# 🏃 物理更新 (每秒 60 次)
# ==========================================
func physics_update(delta: float) -> void:
	var movement := Input.get_axis("move_left", "move_right")
	
	# ==========================================
	# 🌀 動態空中物理 (動態極速與阻力)
	# ==========================================
	
	# 1. 決定當前的空中水平極速
	# 🌟 巧思：如果是走路模式，給予 1.3 倍的寬容度，否則走路跳的距離會短得可憐
	var target_max_speed = player.RUN_SPEED
	if player.is_walking:
		target_max_speed = player.WALK_SPEED * 1.3
		
	# 2. 處理水平加速度與「空氣阻力」
	if not is_zero_approx(movement):
		# 有輸入時：朝輸入方向加速，但最高不超過 target_max_speed
		player.velocity.x = move_toward(
			player.velocity.x, 
			movement * target_max_speed, 
			player.AIR_ACCELERATION * delta
		)
		player.direction = player.Direction.LEFT if movement < 0 else player.Direction.RIGHT
	else:
		# 無輸入時：模擬「空氣阻力 (Drag)」
		# 使用較小的數值讓它在空中緩慢減速，維持拋物線手感
		var air_drag = player.AIR_ACCELERATION * 0.5 
		player.velocity.x = move_toward(player.velocity.x, 0.0, air_drag * delta)

	# 3. 🍎 處理重力：每幀向下疊加重力，對抗起跳時的 JUMP_VELOCITY
	player.velocity.y += player.default_gravity * delta
	
	# 4. 🚀 執行移動
	player.custom_move_and_slide()
	
	# ==========================================
	# 🚦 狀態切換決策
	# ==========================================
	
	# 🏔️ 頂點判定：當 Y 軸速度大於等於 0 (代表往上的力被重力抵銷完了)，開始下墜
	if player.velocity.y >= 0:
		state_machine.transition_to("Fall")
		return
		
	# ⚡ 預輸入：空中閃避 (衝刺)
	if player.slide_request_timer.time_left > 0 and player.stats.energy >= 3:
		if player.slide_cooldown_timer.is_stopped():
			state_machine.transition_to("Slide")
			return
	
	# 🧱 邊緣判定：如果碰到牆壁，可以滑牆
	if player.can_wall_slide():
		state_machine.transition_to("WallSlide")
		return
		
	# ⚔️ 戰鬥大門：聽從 Player.gd 的攻擊緩衝請求
	if player.is_combo_requested or player.is_heavy_requested or player.is_ult_requested:
		state_machine.transition_to("WeaponAttack")
		return
