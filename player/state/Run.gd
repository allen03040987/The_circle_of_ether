extends State
## 奔跑狀態 (Run State)
## 預設從走路開始，持續移動 WALK_TO_RUN_RAMP_DURATION 秒後漸進加速到全速奔跑；
## 開啟「自動奔跑」設定，或剛從閃避(Slide)銜接移動的話，直接以全速奔跑起步，跳過加速過程。
## 待在強制走路區域（目前只有大本營場景 World.is_base 在用，見 Player.update_movement_by_scene()——
## 未來的「安全區」觸發器也應該走同一套機制）一律鎖死在走路速度，蓋過自動奔跑與衝刺銜接。
##
## 🌟 move_ramp_time 記錄「實際連續移動了多久」，跟 is_walking(目前的速度級距/動畫) 是兩件事：
## 自動奔跑只是讓速度立刻拉滿、動畫立刻變成奔跑，不代表移動時間也跳過——放開移動鍵時，
## 是否要轉去 RunStop 播煞車滑行，一律看 move_ramp_time 有沒有累積滿 1.5 秒（或衝刺銜接直接視為滿），
## 跟自動奔跑有沒有開無關，這樣才不會出現「隨便點一下方向鍵也在原地滑行」的怪異手感。

const WALK_TO_RUN_RAMP_DURATION: float = 1.5

# ==========================================
# 🎬 狀態生命週期 (State Lifecycle)
# ==========================================
func enter() -> void:
	# 閃避銜接移動：直接視為已經爬滿加速進度，起步就是全速奔跑，也直接夠格觸發 RunStop
	if player.dash_chain_timer.time_left > 0:
		player.dash_chain_timer.stop()
		player.move_ramp_time = WALK_TO_RUN_RAMP_DURATION

	# 進入狀態的第一瞬間，用跟 physics_update() 同一套規則決定現在該是走路還是奔跑
	# （不能只看 player.is_walking 的舊值——它預設是 false，第一次進 Run 會誤判成「已經在跑」）
	var should_run = not player.is_force_walk_zone and (Game.config_auto_run or player.move_ramp_time >= WALK_TO_RUN_RAMP_DURATION)
	player.is_walking = not should_run
	player.play_safe_anim("walking" if player.is_walking else "running")

	player.is_input_locked = false

func physics_update(delta: float) -> void:
	# 判斷有無輸入方向
	var movement := Input.get_axis("move_left", "move_right")

	if is_zero_approx(movement):
		# 🌟 是否夠格觸發 RunStop 一律看「實際移動了多久」，不看自動奔跑/目前速度級距，
		# 避免自動奔跑下隨便點一下方向鍵就在原地滑行
		var stop_qualifies_for_slide = player.move_ramp_time >= WALK_TO_RUN_RAMP_DURATION
		player.move_ramp_time = 0.0 # 停下來了，下次移動要重新從走路開始爬升
		if stop_qualifies_for_slide:
			state_machine.transition_to("RunStop")
		else:
			state_machine.transition_to("Idle")
		return

	# 🌟 全速奔跑時瞬間反向掉頭：跟放開移動鍵一視同仁，先進 RunStop 減速，
	# 不允許無縫 180 度掉頭（按鍵切換夠快的話 Input.get_axis 可能完全不會經過 0，
	# 單看「movement 是否歸零」抓不到這種瞬間反向，必須額外比對方向有沒有變）。
	# 🔧 比對「目前實際速度方向」(velocity.x)，不能比對 player.direction(面向)——
	# 面向在完全停下來後還是會保留上一次的朝向，用它判斷會導致從靜止起步按
	# 跟上次朝向相反的方向，被誤判成「正在反向掉頭」直接卡進 RunStop 動不了
	var new_direction = player.Direction.RIGHT if movement > 0 else player.Direction.LEFT
	var is_actually_moving_opposite = not is_zero_approx(player.velocity.x) and sign(player.velocity.x) != new_direction
	var has_earned_run_stop = player.move_ramp_time >= WALK_TO_RUN_RAMP_DURATION
	if has_earned_run_stop and is_actually_moving_opposite:
		player.move_ramp_time = 0.0
		state_machine.transition_to("RunStop")
		return

	# 轉向邏輯（還在走路階段、方向沒變，或剛好從靜止起步，才會走到這裡真的更新方向）
	player.direction = new_direction

	# 🌟 移動時間持續累積：跟下面「目前速度上限」是兩件獨立的事，自動奔跑/走路都一樣要走這步，
	# 只有強制走路區域整個鎖住不累積（離開時才重新從走路開始爬）
	if not player.is_force_walk_zone:
		player.move_ramp_time = minf(player.move_ramp_time + delta, WALK_TO_RUN_RAMP_DURATION)

	# ==========================================
	# 🌟 動態速度計算：走路 -> 奔跑 漸進加速
	# ==========================================
	var current_max_speed: float
	var should_run: bool

	if player.is_force_walk_zone:
		current_max_speed = player.WALK_SPEED
		should_run = false
	elif Game.config_auto_run:
		current_max_speed = player.RUN_SPEED
		should_run = true
	else:
		var ramp_t = player.move_ramp_time / WALK_TO_RUN_RAMP_DURATION
		current_max_speed = lerp(player.WALK_SPEED, player.RUN_SPEED, ramp_t)
		should_run = player.move_ramp_time >= WALK_TO_RUN_RAMP_DURATION

	# 🌟 武器自身的移速倍率（例如長槍丟出去、還沒接回來時身法變輕巧）
	if is_instance_valid(player.current_weapon):
		current_max_speed *= player.current_weapon.get_speed_multiplier()

	var wanted_walking = not should_run
	if player.is_walking != wanted_walking:
		player.is_walking = wanted_walking
		player.play_safe_anim("walking" if wanted_walking else "running")

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

	# 預輸入：格擋
	if player.guard_request_timer.time_left > 0:
		state_machine.transition_to("Guard")
		return

	# ==========================================
	# ⚔️ 戰鬥大門 (統一聽從 Player 的緩衝請求)
	# ==========================================
	# 絕對不准在這裡使用 Input.is_action_pressed！
	# 所有的輸入資格審查與緩衝，都已經在 Player.gd 的 _unhandled_input 處理完畢了。

	if player.is_combo_requested or player.is_heavy_requested:
		state_machine.transition_to("WeaponAttack")
		return
