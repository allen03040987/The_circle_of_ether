extends State
## 下墜狀態 (Fall State)
## 處理角色自由落體的過程。可能是跳躍到達頂點後觸發，也可能是直接走下懸崖觸發。

const LAND_SFX = preload("res://sound/SFX/land.wav")

# ==========================================
# 🎬 狀態生命週期：進入狀態
# ==========================================
func enter() -> void:
	player.play_safe_anim("fall")

# ==========================================
# 🏃 物理更新 (每秒 60 次)
# ==========================================
func physics_update(delta: float) -> void:
	var movement := Input.get_axis("move_left", "move_right")
	
	# 1. 🍎 處理重力與「沉重感」
	# 🌟 巧思：當角色開始往下掉 (y > 0) 時，將重力放大 1.2 倍。
	# 這能讓跳躍的軌跡變成「上慢下快」，手感會更俐落扎實，不會有太空漫步的感覺。
	var cur_gravity = player.default_gravity
	if player.velocity.y > 0:
		cur_gravity *= 1.2 
		
	# ==========================================
	# 🌀 動態空中物理 (必須與 Jump.gd 保持一致)
	# ==========================================
	var target_max_speed = player.RUN_SPEED
	if player.is_walking:
		target_max_speed = player.WALK_SPEED * 1.3 
		
	if not is_zero_approx(movement):
		# 空中加速
		player.velocity.x = move_toward(player.velocity.x, movement * target_max_speed, player.AIR_ACCELERATION * delta)
		player.direction = player.Direction.LEFT if movement < 0 else player.Direction.RIGHT
	else:
		# 空氣阻力
		var air_drag = player.AIR_ACCELERATION * 0.5 
		player.velocity.x = move_toward(player.velocity.x, 0.0, air_drag * delta)

	player.velocity.y += cur_gravity * delta
	
	# 3. 🛑 限制最高落速 (終端速度 Terminal Velocity)
	# 防止從太高的地方掉下來速度無上限累積，導致直接穿破地板判定 (Tunneling)
	player.velocity.y = min(player.velocity.y, player.TERMINAL_VELOCITY)
		
	# 4. 🚀 執行移動
	player.custom_move_and_slide()
	
	# ==========================================
	# 🚦 狀態切換決策
	# ==========================================
	
	# 🌍 落地判定
	if player.is_on_floor():
		if LAND_SFX:
			AudioManager.play_sfx(LAND_SFX, -10.0, 1.0)
		
		if is_zero_approx(movement):
			state_machine.transition_to("Idle")
		else:
			# 只要交給 Run 狀態，它在 enter() 時就會自己決定要播走路還是跑步動畫
			state_machine.transition_to("Run") 
		return
		
	# 🐺 預輸入：跳躍 (郊狼時間 Coyote Time)
	# 如果玩家剛走下懸崖 (coyote_timer 還在跑)，而且按下了跳躍，就網開一面讓他跳！
	if player.jump_request_timer.time_left > 0 and player.coyote_timer.time_left > 0:
		state_machine.transition_to("Jump")
		return
		
	# ⚡ 預輸入：空中閃避 (衝刺)
	if player.slide_request_timer.time_left > 0 and player.stats.energy >= 3:
		if player.slide_cooldown_timer.is_stopped():
			state_machine.transition_to("Slide")
			return

	# 🌟 空中不可格擋：格擋預輸入留著不清，等落地後交給 Idle/Run/RunStop 接手判斷

	# 🧱 邊緣判定：滑牆
	if player.can_wall_slide():
		state_machine.transition_to("WallSlide")
		return

	# ⚔️ 戰鬥大門：聽從 Player.gd 的攻擊緩衝請求
	if player.is_combo_requested or player.is_heavy_requested:
		state_machine.transition_to("WeaponAttack")
		return
