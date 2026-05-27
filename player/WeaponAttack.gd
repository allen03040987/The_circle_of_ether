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
		
	# 防呆：沒武器直接踢回 Idle
	if not is_instance_valid(player.current_weapon):
		state_machine.transition_to("Idle")
		return
		
	# 🌟 新增：還原由閃避偏移（Dodge Offset）保留下來的武器連段段數
	if player.has_meta("dodge_offset") and player.has_meta("saved_combo_step"):
		if "combo_step" in player.current_weapon:
			player.current_weapon.combo_step = player.get_meta("saved_combo_step")
			print("🔥 [Dodge Offset] 成功接續連段！當前段數還原為：", player.current_weapon.combo_step)
		player.remove_meta("dodge_offset")
		player.remove_meta("saved_combo_step")
		
	# --- 嚴格輸入緩衝判定 ---
	var wants_heavy = player.is_heavy_requested 
	var wants_light = player.is_combo_requested
	
	player.can_combo = false
	player.is_combo_requested = false
	player.is_heavy_requested = false
	player.combo_buffer_time = 0.0
	player.heavy_buffer_time = 0.0

	_update_facing()
	
	# --- 攻擊優先級派發 ---
	# 👑 優先度 1：大招 (Ultimate)
	if player.is_ult_requested:
		player.is_ult_requested = false
		if player.current_weapon.has_method("start_ultimate"):
			player.current_weapon.start_ultimate()
		return
		
	# ⚔️ 優先度 2：常規輕重擊
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
				
				# 🌟 1. 啟用連段偏移標記 (讓本體閃避完可以接續下一刀)
				player.set_meta("dodge_offset", true)
				
				# 🌟 2. 核心修正：呼叫真正的「代打殘影系統」！讓分身留在原地把這刀砍完！
				if player.has_method("spawn_phantom_striker"):
					player.spawn_phantom_striker(player.current_weapon)
					
				# 🌟 3. (選擇性) 加上跟切換武器一樣的閃白光特效，讓閃避取消的打擊感更強烈
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
		# 如果是因閃避而取消，先將武器當前的連段段數備份起來
		if player.has_meta("dodge_offset") and "combo_step" in player.current_weapon:
			player.set_meta("saved_combo_step", player.current_weapon.combo_step)
			
		if player.current_weapon.get("is_attacking"):
			player.current_weapon.cancel_attack()
