class_name WeaponAttackState
extends State
## 戰鬥總監狀態 (Weapon Attack State)
## 全權接管攻擊時的輸入緩衝分配、物理速度套用、動畫派生，以及魔女時間(極限閃避)的簽證偏移補償。

var _frames_in_state: int = 0

## 處理玩家攻擊時的方向修正
func _update_facing() -> void:
	if player.is_input_locked: return 
	
	var move_dir := Input.get_axis("move_left", "move_right")
	if not is_zero_approx(move_dir):
		player.direction = player.Direction.LEFT if move_dir < 0 else player.Direction.RIGHT

# ==========================================
# 🎬 進入狀態 (Enter)
# ==========================================
func enter() -> void:
	_frames_in_state = 0
	
	if player.scabbard:
		player.scabbard.fade_out() 
		
	if not is_instance_valid(player.current_weapon):
		state_machine.transition_to("Idle")
		return
		
	# ------------------------------------------
	# ⏳ 處理魔女時間專屬閃避偏移 (Dodge Offset)
	# ------------------------------------------
	var has_offset_visa = player.has_meta("dodge_offset") and player.has_meta("saved_combo_step") and player.has_meta("dodge_combo_deadline")
	
	if has_offset_visa:
		var current_time := Time.get_ticks_msec()
		var deadline := player.get_meta("dodge_combo_deadline") as int
		
		if current_time <= deadline and "combo_step" in player.current_weapon:
			var saved_step = player.get_meta("saved_combo_step")
			player.current_weapon.combo_step = maxi(0, saved_step - 1)
			print("🔄 [魔女偏移] 簽證有效！重新執行中斷的第 ", saved_step, " 段！")
			
			if "last_attack_time" in player.current_weapon:
				player.current_weapon.last_attack_time = current_time / 1000.0
		else:
			print("⏳ [魔女偏移] 簽證已過期，連段記憶失效。")
			
		player.remove_meta("dodge_offset")
		player.remove_meta("saved_combo_step")
		player.remove_meta("dodge_combo_deadline")
		
	else:
		if player.has_meta("saved_combo_step"): player.remove_meta("saved_combo_step")
		if player.has_meta("dodge_offset"): player.remove_meta("dodge_offset")
		if player.has_meta("dodge_combo_deadline"): player.remove_meta("dodge_combo_deadline")
		
	# ------------------------------------------
	# 🎯 輸入緩衝與攻擊優先級發放
	# ------------------------------------------
	var wants_martial = player.is_martial_requested
	var martial_slot = player.requested_martial_slot
	var wants_heavy = player.is_heavy_requested 
	var wants_light = player.is_combo_requested
	
	player.can_combo = false
	player.is_martial_requested = false
	player.is_combo_requested = false
	player.is_heavy_requested = false
	player.martial_buffer_time = 0.0
	player.combo_buffer_time = 0.0
	player.heavy_buffer_time = 0.0

	_update_facing()

	if wants_martial:
		if player.current_weapon.has_method("execute_martial_art"):
			player.current_weapon.execute_martial_art(martial_slot)
		else:
			state_machine.transition_to("Idle")
		return
		
	if wants_heavy:
		player.current_weapon.start_heavy_attack()
	elif wants_light:
		player.current_weapon.start_light_attack()
	else:
		state_machine.transition_to("Idle")
		
# ==========================================
# 🏃 物理更新與特權判定 (Physics Update)
# ==========================================
func physics_update(delta: float) -> void:
	if not is_instance_valid(player.current_weapon): return
	_frames_in_state += 1

	if not player.is_input_locked:
		
		# 1. 偵測格擋強制打斷：跟 Slide 同性質的反射型狀態，能直接打斷正在進行的任何招式
		if player.guard_request_timer.time_left > 0:
			_frames_in_state = 0
			player.can_combo = false
			player.combo_buffer_time = 0.0
			player.heavy_buffer_time = 0.0

			player.current_weapon.cancel_attack()
			state_machine.transition_to("Guard")
			return

		# 1.5 偵測武藝強制打斷：權限僅次閃避，不受 can_combo 連段窗口限制，
		# 能直接打斷正在進行的普攻/戰技，或是另一個正在施放的武藝卡帶——
		# 但如果玩家連按的是「同一招」，就不重啟，防止靠連打同招無限刷新（例如卡血條或無敵幀）
		if player.is_martial_requested and player.current_weapon.has_method("execute_martial_art"):
			var m_slot = player.requested_martial_slot
			var weapon = player.current_weapon
			var requested_art = weapon.martial_slots[m_slot - 1] if m_slot >= 1 and m_slot <= weapon.martial_slots.size() else null
			var is_same_art_still_running = is_instance_valid(weapon.active_martial_art) and weapon.active_martial_art == requested_art

			player.is_martial_requested = false
			player.martial_buffer_time = 0.0

			if not is_same_art_still_running:
				_frames_in_state = 0
				player.can_combo = false
				player.is_combo_requested = false
				player.is_heavy_requested = false
				player.combo_buffer_time = 0.0
				player.heavy_buffer_time = 0.0

				_update_facing()
				weapon.cancel_attack()
				weapon.execute_martial_art(m_slot)
				return

		# 2. 偵測連段派生 (Combo Chaining)
		if player.can_combo and _frames_in_state > 3:
			if player.is_heavy_requested:
				_frames_in_state = 0 
				player.can_combo = false 
				player.is_heavy_requested = false
				player.heavy_buffer_time = 0.0
				
				_update_facing()
				player.current_weapon.start_heavy_attack()
				
			elif player.is_combo_requested:
				_frames_in_state = 0 
				player.can_combo = false 
				player.is_combo_requested = false
				player.combo_buffer_time = 0.0
				
				_update_facing()
				player.current_weapon.start_light_attack()
				
		# 3. 偵測閃避取消 (Dodge Cancel)
		if player.slide_request_timer.time_left > 0 and player.stats.energy >= 3:
			if player.current_weapon.can_be_canceled_by_dodge():
				# 🔧 改成位元旗標檢查：招式可能同時掛著「普攻＋空戰」這種複合標籤，用 == 精準比對會漏掉
				var action_type: int = player.current_weapon.get("current_action_type")
				if (action_type & Weapon.ActionType.NORMAL) != 0:
					player.set_meta("saved_combo_step", player.current_weapon.combo_step)
				else:
					if player.has_meta("saved_combo_step"): player.remove_meta("saved_combo_step")
				
				if player.has_method("_flash_character"):
					player._flash_character()
				
				state_machine.transition_to("Slide")
				return

	# ==========================================
	# 🏃 物理移動委託
	# ==========================================
	var target_velocity: Vector2 = player.current_weapon.get_current_velocity(delta)
	player.velocity = target_velocity
	
	if not player.current_weapon.is_handling_gravity():
		player.velocity.y += player.default_gravity * delta
		
	player.custom_move_and_slide() 
	
	# ==========================================
	# 🎬 招式結束判定
	# ==========================================
	if player.current_weapon.is_attack_finished():
		if player.is_on_floor():
			if player.current_weapon.has_method("requires_sheath") and player.current_weapon.requires_sheath():
				state_machine.transition_to("Sheath")
			else:
				state_machine.transition_to("Idle")
		else:
			state_machine.transition_to("Fall")
		return

## 被外力或狀態機強制切換時的清掃邏輯
func exit() -> void:
	if is_instance_valid(player.current_weapon):
		# 🔧 除了 is_attacking，也要看有沒有正在執行中的武藝卡帶——
		# 很多武藝卡帶（例如 Art_Katana_3）自己不會設定 is_attacking = true，
		# 只看 is_attacking 會漏呼叫 cancel_attack()，武藝自己的收尾清理（例如解除時緩）就永遠不會執行
		var has_active_martial_art = is_instance_valid(player.current_weapon.get("active_martial_art"))
		if player.current_weapon.get("is_attacking") or has_active_martial_art:
			player.current_weapon.cancel_attack()
