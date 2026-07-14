extends State
## 牆跳狀態 (Wall Jump State)
## 角色從牆壁上借力跳出的過程。包含短暫的「操作剝奪期」。

const JUMP_SFX = preload("res://sound/SFX/jump.wav")

# ⏱️ 動作蜜糖 (Game Feel)：牆跳瞬間的時間慢動作特效參數
const WALL_JUMP_TIME_STOP_SCALE := 0.88
const WALL_JUMP_TIME_STOP_DURATION := 0.3

# ==========================================
# 🎬 狀態生命週期：進入狀態
# ==========================================
func enter() -> void:

	if JUMP_SFX:
		AudioManager.play_sfx(JUMP_SFX, -10.0, 1.0)
	player.play_safe_anim("wall_jump")
	player.jump_request_timer.stop()

	# ⏱️ 動作蜜糖 (Game Feel)：牆跳瞬間的時間慢動作特效
	# 🔧 改走 Player 的時停仲裁介面（trigger_time_stop → CombatManager.set_domain_time），
	# 不再直接寫 Engine.time_scale，避免跟太刀/符咒/鐮刀大招的時停互踩。
	# trigger_time_stop 內建保護：如果當下已有更強或更久的時停在跑，這次請求會被忽略。
	if player.has_method("trigger_time_stop"):
		player.trigger_time_stop(WALL_JUMP_TIME_STOP_DURATION, WALL_JUMP_TIME_STOP_SCALE)

	# 🚀 給予牆跳的基礎反彈力 (WALL_JUMP_VELOCITY 是一個 Vector2，例如 (300, -500))
	player.velocity = player.WALL_JUMP_VELOCITY
	
	# 🧭 決定彈出的方向：利用法線 (往牆壁外推)
	var wall_normal_x = player.get_wall_normal().x
	# 防呆：如果剛好離開牆壁的瞬間才判定跳躍，法線可能是 0，此時用背對的方向當作法線
	if wall_normal_x == 0:
		wall_normal_x = -player.direction
		
	# 把基礎反彈力的 X 軸，乘上法線方向 (彈離牆壁)
	player.velocity.x *= wall_normal_x

# 🚪 離開狀態：時停交給 Player 的倒數機制（trigger_time_stop 的 duration）自動解除，
# 這裡不再手動還原 Engine.time_scale，避免搶先結束其他系統正在進行的時停。

# ==========================================
# 🏃 物理更新 (每秒 60 次)
# ==========================================
func physics_update(delta: float) -> void:
	var movement := Input.get_axis("move_left", "move_right")
	
	# 🌟 核心防呆：操作剝奪 (Input Deprivation)
	# 玩家通常在滑牆時會一直按著朝牆壁的方向鍵。
	# 如果不鎖定，跳出去的瞬間，玩家殘留的按鍵會立刻把角色「拉回」牆上，看起來就像跳不遠。
	if state_machine.state_time < 0.18:
		# 🔒 鎖定期 (前 0.18 秒)：只套用重力，玩家的 movement 輸入無效
		player.velocity.y += player.default_gravity * delta
		player.velocity.y = min(player.velocity.y, player.TERMINAL_VELOCITY)
	else:
		# 🔓 解鎖後：恢復空中的水平控制力 (邏輯同 JumpState)
		player.velocity.x = move_toward(player.velocity.x, movement * player.RUN_SPEED, player.AIR_ACCELERATION * delta)
		player.velocity.y += player.default_gravity * delta
		player.velocity.y = min(player.velocity.y, player.TERMINAL_VELOCITY)
		
		# 轉向
		if not is_zero_approx(movement):
			player.direction = player.Direction.LEFT if movement < 0 else player.Direction.RIGHT
			
	player.custom_move_and_slide()
	
	# ==========================================
	# 🚦 狀態切換決策
	# ==========================================
	
	# ⚡ 空中閃避
	if player.slide_request_timer.time_left > 0 and player.stats.energy >= 3:
		if player.slide_cooldown_timer.is_stopped():
			state_machine.transition_to("Slide")
			return

	# 🌟 空中不可格擋：格擋預輸入留著不清，等落地後交給 Idle/Run/RunStop 接手判斷

	# 🏔️ 到達最高點，速度開始往下掉，進入下墜
	if player.velocity.y >= 0:
		state_machine.transition_to("Fall")
		return
		
	# 🧱 如果兩側有很近的牆壁，也就是俗稱的「蹬牆跳 (Wall Kick)」，可以馬上再接滑牆
	if player.can_wall_slide():
		state_machine.transition_to("WallSlide")
