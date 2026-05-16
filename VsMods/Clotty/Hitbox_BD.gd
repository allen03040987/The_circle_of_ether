class_name ClottySkill_BD
extends VsPlayerState

# ==========================================
# 🦵 技能 BD (下段掃擊 / 終極動態防連段版)
# ==========================================
@export_group("⚙️ 技能參數")
@export var mp_cost: float = 15.0          

@export var hitbox_1_path: NodePath 
@export var hitbox_2_path: NodePath 

# --- 內部記憶體 ---
var current_phase: int = 1      
var _phase_2_triggered: bool = false 
var _phase_2_shook: bool = false 
var _is_punish_mode: bool = false 

func can_cast() -> bool:
	if not player.is_on_floor(): return false 
	if player.current_mp < mp_cost: return false 
	return true

func enter() -> void:
	current_phase = 1
	_phase_2_triggered = false
	_phase_2_shook = false
	_is_punish_mode = false
	player.current_mp -= mp_cost
	player.auto_face_opponent()
	
	var hitbox_1 = get_node_or_null(hitbox_1_path) as VsHitbox
	var hitbox_2 = get_node_or_null(hitbox_2_path) as VsHitbox
	
	# 🌟 洗掉記憶並設定基礎屬性
	if hitbox_1: 
		hitbox_1.hit_targets.clear()
		hitbox_1.can_hit_otg = false # 🌟 【需求 1】強制關閉第一段的掃地判定！
		
	if hitbox_2: 
		hitbox_2.hit_targets.clear()
		hitbox_2.hitstun_time = 1.2
		hitbox_2.ground_knockback = Vector2(100, 0) 
		hitbox_2.air_knockback = Vector2(100, 0)    
		hitbox_2.causes_down = false                

	# ==========================================
	# 🛡️ 動態防無限連：嚴格的對手狀態審查
	# ==========================================
	if player.opponent:
		var opp = player.opponent
		
		# 🌟 【需求 2】對手在空中？直接轉懲罰模式剷倒！
		if not opp.is_on_floor():
			_is_punish_mode = true
		elif opp.vs_state_machine.current_state != null:
			# 轉成小寫，防止大小寫比對失敗 (例如 VsHurtState 也能被抓到)
			var state_name = opp.vs_state_machine.current_state.name.to_lower()
			
			# 🌟 【終極修復】：只要名字有受擊字眼，或硬直計時器 > 0
			if "hurt" in state_name or "knock" in state_name or opp.hitstun_time_left > 0.0:
				# ⚠️ 關鍵防護：排除待機、移動、蹲下，防止「殘留計時器」導致誤判打飛！
				if not ("idle" in state_name or "move" in state_name or "crouch" in state_name or "walk" in state_name):
					_is_punish_mode = true

	if hitbox_1:
		if _is_punish_mode:
			# ⚠️ 懲罰模式：對手在空中或硬直中 ➡️ 第一段直接剷飛他！
			hitbox_1.causes_down = true
			hitbox_1.ground_knockback = Vector2(250, -150) 
			hitbox_1.air_knockback = Vector2(250, -150) 
			hitbox_1.hitstun_time = 0.5
		else:
			# ✅ 正常模式：對手清醒站著 ➡️ 正常大硬直，準備派生！
			hitbox_1.causes_down = false
			hitbox_1.ground_knockback = Vector2(50, 0)
			hitbox_1.air_knockback = Vector2(50, 0)
			hitbox_1.hitstun_time = 1.0

	player.strike_impulse(150.0)
	player.play_safe_anim("skill_BD")

func process_physics(delta: float) -> VsState:
	var interrupt = check_interrupts()
	if interrupt != null:
		return interrupt
		
	player.velocity.x = move_toward(player.velocity.x, 0.0, player.ground_friction * delta)
	player.custom_move_and_slide() 
	
	# ==========================================
	# 🎯 第一段：命中即派生 (懲罰模式下絕對不派生！)
	# ==========================================
	if current_phase == 1 and not _phase_2_triggered and not _is_punish_mode:
		var hitbox_1 = get_node_or_null(hitbox_1_path) as VsHitbox
		if hitbox_1 and hitbox_1.hit_targets.size() > 0:
			_phase_2_triggered = true
			_trigger_phase_2_派生特寫()
			return null
			
	# ==========================================
	# 💥 第二段：獨立震動偵測
	# ==========================================
	if current_phase == 2 and not _phase_2_shook:
		var hitbox_2 = get_node_or_null(hitbox_2_path) as VsHitbox
		if hitbox_2 and hitbox_2.hit_targets.size() > 0:
			_phase_2_shook = true
			player.play_camera_shake(30.0, 0.2)

	# ==========================================
	# 🎬 動畫播完檢測
	# ==========================================
	if not player.animation.is_playing():
		if current_phase == 1:
			if Input.is_action_pressed(player.down_key):
				return state_machine.crouch_state
			return state_machine.idle_state
				
		elif current_phase == 2:
			player.trigger_cinematic_zoom(true, 1.0, 0.2)
			if Input.is_action_pressed(player.down_key):
				return state_machine.crouch_state
			return state_machine.idle_state
			
	return null

func _trigger_phase_2_派生特寫() -> void:
	current_phase = 2
	player.play_safe_anim("skill_BD_end")
	player.strike_impulse(250.0)
	player.trigger_cinematic_zoom(true, 1.4, 0.15)

func exit() -> void:
	player.deactivate_all_hitboxes()
	player.trigger_cinematic_zoom(true, 1.0, 0.2)
