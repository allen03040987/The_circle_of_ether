extends State
class_name WeaponAttackState
## 戰鬥總監狀態 (Weapon Attack State)
## 職責：處理所有武器攻擊期間的轉向、連段派生 (Combo)、打斷，並將物理移動委託給武器計算。

var _frames_in_state: int = 0

func _update_facing() -> void:
	# 領域展開(鎖死)期間禁止轉向，防止搖桿偷渡
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
		
	# ==========================================
	# 🌟 嚴格檢驗版：魔女時間專屬閃避偏移
	# ==========================================
	if player.has_meta("dodge_offset") and player.has_meta("saved_combo_step") and player.has_meta("dodge_combo_deadline"):
		var current_time := Time.get_ticks_msec()
		var deadline := player.get_meta("dodge_combo_deadline") as int
		
		# 檢查當前時間是否還在寬限期之內
		if current_time <= deadline:
			if "combo_step" in player.current_weapon:
				var saved_step = player.get_meta("saved_combo_step")
				player.current_weapon.combo_step = maxi(0, saved_step - 1)
				print("🔄 [魔女偏移] 簽證有效！重新執行中斷的第 ", saved_step, " 段！")
				
				# 欺騙武器的超時機制
				if "last_attack_time" in player.current_weapon:
					player.current_weapon.last_attack_time = current_time / 1000.0
		else:
			print("⏳ [魔女偏移] 簽證已過期，連段記憶失效。")
			
		# 不論成功與否，進入攻擊後立刻撕毀簽證
		player.remove_meta("dodge_offset")
		player.remove_meta("saved_combo_step")
		player.remove_meta("dodge_combo_deadline")
	else:
		# 🗑️ 防呆清理：如果根本沒拿到簽證(普通閃避)，就把垃圾清掉，保證從第 1 段開始
		if player.has_meta("saved_combo_step"): player.remove_meta("saved_combo_step")
		if player.has_meta("dodge_offset"): player.remove_meta("dodge_offset")
		if player.has_meta("dodge_combo_deadline"): player.remove_meta("dodge_combo_deadline")
		
	# --- 輸入緩衝與優先級發放維持原樣 ---
	var wants_heavy = player.is_heavy_requested 
	var wants_light = player.is_combo_requested
	
	player.can_combo = false
	player.is_combo_requested = false
	player.is_heavy_requested = false
	player.combo_buffer_time = 0.0
	player.heavy_buffer_time = 0.0

	_update_facing()
	
	if player.is_ult_requested:
		player.is_ult_requested = false
		if player.current_weapon.has_method("start_ultimate"):
			player.current_weapon.start_ultimate()
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

	# --- 🛑 鎖死判定：未鎖死才允許派生與打斷 ---
	if not player.is_input_locked:
		
		# 👑 特權 1：大招強制打斷普攻
		if player.is_ult_requested:
			if player.current_weapon.has_method("can_use_ultimate") and player.current_weapon.can_use_ultimate():
				player.is_ult_requested = false
				_frames_in_state = 0 
				player.can_combo = false 
				player.combo_buffer_time = 0.0
				player.heavy_buffer_time = 0.0
				
				_update_facing() 
				player.current_weapon.cancel_attack() 
				player.current_weapon.start_ultimate()
				
				if player.scabbard:
					player.scabbard.fade_out()
				return
			else:
				player.is_ult_requested = false 

		# 🔗 特權 2：連段派生 (Combo Chaining)
		if player.can_combo and _frames_in_state > 3:
			if player.is_heavy_requested:
				_frames_in_state = 0 
				player.can_combo = false 
				player.is_heavy_requested = false
				player.heavy_buffer_time = 0.0
				
				_update_facing()
				player.current_weapon.start_heavy_attack()
				return 
				
			elif player.is_combo_requested:
				_frames_in_state = 0 
				player.can_combo = false 
				player.is_combo_requested = false
				player.combo_buffer_time = 0.0
				
				_update_facing()
				player.current_weapon.start_light_attack()
				return 
				
		# ⚡ 特權 3：閃避取消 (Dodge Cancel)
		if player.slide_request_timer.time_left > 0 and player.stats.energy >= 3:
			if player.current_weapon.can_be_canceled_by_dodge():
				
				# 🌟 1. 僅保留段數記憶，不立刻給予「閃避偏移」特權！
				if player.current_weapon.get("current_action_type") == Weapon.ActionType.NORMAL:
					player.set_meta("saved_combo_step", player.current_weapon.combo_step)
				else:
					if player.has_meta("saved_combo_step"): player.remove_meta("saved_combo_step")
				
				# 🌟 2. 呼叫代打殘影
				if player.has_method("spawn_phantom_striker"):
					player.spawn_phantom_striker(player.current_weapon)
					
				# 🌟 3. 閃避閃白光
				if player.has_method("_flash_character"):
					player._flash_character()
				
				state_machine.transition_to("Slide")
				return

	# ==========================================
	# 🏃 物理移動委託 (最高位移原則)
	# ==========================================
	var target_velocity: Vector2 = player.current_weapon.get_current_velocity(delta)
	player.velocity = target_velocity
	
	if not player.current_weapon.is_handling_gravity():
		player.velocity.y += player.default_gravity * delta
		
	player.custom_move_and_slide() # ✅ 嚴格遵守最高指導原則
	
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

# ==========================================
# 🚪 離開狀態 (Exit)
# ==========================================		
func exit() -> void:
	if is_instance_valid(player.current_weapon):
		# 這裡只負責讓武器收招，記憶邏輯已經移交給 physics_update 和 Slide 處理！
		if player.current_weapon.get("is_attacking"):
			player.current_weapon.cancel_attack()
