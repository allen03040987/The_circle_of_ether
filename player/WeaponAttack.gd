extends State
class_name WeaponAttackState
## 戰鬥總監狀態 (Weapon Attack State)
## 處理所有武器攻擊期間的轉向、連段派生 (Combo)、打斷與物理委託。

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
		
	# 武器有效性防呆
	if not is_instance_valid(player.current_weapon):
		state_machine.transition_to("Idle")
		return
		
	# --- 輸入雙重判定與緩衝清理 ---
	# 嚴格禁止長按偷渡，一切只聽從 Player 的「點按緩衝 (is_requested)」
	var wants_heavy = player.is_heavy_requested 
	var wants_light = player.is_combo_requested
	
	player.can_combo = false
	player.is_combo_requested = false
	player.is_heavy_requested = false
	player.combo_buffer_time = 0.0
	player.heavy_buffer_time = 0.0

	_update_facing()
	
	# --- 攻擊優先級派發 ---
	# 優先度 0：大招
	if player.is_ult_requested:
		player.is_ult_requested = false
		if player.current_weapon.has_method("start_ultimate"):
			player.current_weapon.start_ultimate()
		return
		
	# 優先度 1：極限閃避反擊 (魔女時間派生)
	if (player.is_counter_requested or player.counter_pickup_timer > 0) and wants_light and not wants_heavy:
		player.is_counter_requested = false
		player.counter_pickup_timer = 0.0
		if player.current_weapon.has_method("start_counter_attack"):
			player.current_weapon.start_counter_attack()
		return

	# 優先度 2：常規輕重擊
	if wants_heavy:
		player.current_weapon.start_heavy_attack()
	elif wants_light:
		player.current_weapon.start_light_attack()
	else:
		# 如果什麼按鍵緩衝都沒有卻進來了，直接踢回待機！
		state_machine.transition_to("Idle")
		
# ==========================================
# 🏃 物理更新 (Physics Update)
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
				
				# 這裡會觸發 cancel_attack()，導致刀鞘被誤叫出來 (fade_in)
				player.current_weapon.cancel_attack() 
				player.current_weapon.start_ultimate()
				
				# 🌟 核心修復：直接無條件把它藏回去！不要再去管 requires_sheath 了！
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
				state_machine.transition_to("Slide")
				return

	# --- 🏃 物理移動委託 (最高位移原則) ---
	var target_velocity: Vector2 = player.current_weapon.get_current_velocity(delta)
	player.velocity = target_velocity
	
	if not player.current_weapon.is_handling_gravity():
		player.velocity.y += player.default_gravity * delta
		
	player.custom_move_and_slide()
	
	# --- 🎬 招式結束判定 ---
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
		if player.current_weapon.is_attacking:
			player.current_weapon.cancel_attack()
