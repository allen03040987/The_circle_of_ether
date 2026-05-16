class_name VsPlayerState 
extends VsState

## 所有玩家戰鬥狀態的「超級老爸 (Base Class)」。
## 提供物理重力、按鍵派生審查 (搓招) 以及防踩頭機制，供所有子狀態繼承使用。

# ==========================================
# 📍 節點參考與環境變數
# ==========================================
@onready var player: VsPlayer = get_parent().get_parent() as VsPlayer

var state_machine: VsStateMachine:
	get: return get_parent() as VsStateMachine

var gravity: float = 1000.0
var idle_anim := "idle"
var run_anim := "running"
var last_dir: float = 0.0

## 這個狀態是否允許被「衝刺/後撤」或「蹲下」打斷？(預設為 true，攻擊狀態通常會覆寫為 false)
@export var can_dash_cancel: bool = true

## 預設為 false 這招放的時候，允許被自動切換成防禦嗎？
@export var can_block: bool = false

# ==========================================
# 🛑 1. 全域位移與姿態攔截 (衝刺、蹲下)
# ==========================================
func check_interrupts() -> VsState:
	if can_dash_cancel: 
		
		# --- 小衝刺 (雙擊方向鍵) ---
		if player.double_tapped_dir != 0.0 and player.current_stamina >= player.small_dash_cost:
			if not self is VsPlayerHurtState and not self is VsPlayerDownState and not self is VsPlayerSmallDashState:
				var is_free_state = (self is VsPlayerIdleState or self is VsPlayerRunState or self is VsPlayerCrouchState or self is VsPlayerJumpState or self is VsPlayerFallState)
				var facing_dir = player.get_node("Graphics").scale.x
				var is_back_dashing = (player.double_tapped_dir != facing_dir)
				
				# 允許在自由狀態，或者「向後退(後撤步)」時觸發
				if is_free_state or is_back_dashing:
					player.current_stamina -= player.small_dash_cost
					player.get_node("Graphics").scale.x = player.double_tapped_dir
					return state_machine.small_dash_state
		
		# --- 大衝刺 (按鍵觸發) ---
		if Input.is_action_just_pressed(player.big_dash_key) and player.current_stamina >= player.big_dash_cost:
			if self is VsPlayerIdleState or self is VsPlayerRunState or self is VsPlayerFallState or self is VsPlayerJumpState:
				return state_machine.big_dash_state

	# --- 蹲下攔截 ---
	if player.is_on_floor() and Input.is_action_pressed(player.down_key):
		if self is VsPlayerIdleState or self is VsPlayerRunState:
			return state_machine.crouch_state

	return null 

# ==========================================
# ⚔️ 2. 戰鬥指令包 A：大招與特殊技 (U / Special / Custom)
# ==========================================
func check_offensive_skills() -> VsState:
	if Input.is_action_just_pressed(player.ultimate_key):
		if Input.is_action_pressed(player.down_key):
			if state_machine.ultimate_state_2 != null and state_machine.ultimate_state_2.can_cast(): return state_machine.ultimate_state_2
		else:
			if state_machine.ultimate_state != null and state_machine.ultimate_state.can_cast(): return state_machine.ultimate_state
			
	if Input.is_action_just_pressed(player.special_key):
		if state_machine.special_state != null and state_machine.special_state.can_cast(): return state_machine.special_state
			
	if Input.is_action_just_pressed(player.custom_key):
		if state_machine.custom_state != null and state_machine.custom_state.can_cast(): return state_machine.custom_state
			
	return null
	
# ==========================================
# 🥊 3. 戰鬥指令包 B：地面普攻與技能搓招 (J / K 系列)
# ==========================================
func check_ground_moves() -> VsState:
	var pressed_skill = Input.is_action_just_pressed(player.skill_key)
	var pressed_atk = Input.is_action_just_pressed(player.attack_key)

	if not pressed_skill and not pressed_atk: return null

	# 取得戰鬥朝向 (以對手位置為絕對基準，若無對手則看自己面朝哪)
	var holding_down = Input.is_action_pressed(player.down_key)
	var combat_facing = player.get_node("Graphics").scale.x
	if player.opponent != null:
		var dir_to_opponent = sign(player.opponent.global_position.x - player.global_position.x)
		if dir_to_opponent != 0: combat_facing = dir_to_opponent

	var holding_left = Input.is_action_pressed(player.left_key)
	var holding_right = Input.is_action_pressed(player.right_key)
	var holding_forward = (combat_facing == 1.0 and holding_right) or (combat_facing == -1.0 and holding_left)
	var holding_backward = (combat_facing == 1.0 and holding_left) or (combat_facing == -1.0 and holding_right)

	# 🌟 K 鍵 (技能) 派生
	if pressed_skill:
		if holding_down and holding_forward and state_machine.skill_k1 != null and state_machine.skill_k1.can_cast(): return state_machine.skill_k1
		if holding_down and holding_backward and state_machine.skill_k2 != null and state_machine.skill_k2.can_cast(): return state_machine.skill_k2
		if holding_down and not holding_forward and not holding_backward and state_machine.skill_k3 != null and state_machine.skill_k3.can_cast(): return state_machine.skill_k3
		if not holding_down and state_machine.skill_neutral != null and state_machine.skill_neutral.can_cast(): return state_machine.skill_neutral

	# 🌟 J 鍵 (普攻) 派生
	elif pressed_atk:
		if holding_down and not holding_forward and not holding_backward and state_machine.attack_bd != null and state_machine.attack_bd.can_cast(): return state_machine.attack_bd
		if not holding_down and state_machine.attack_state != null and state_machine.attack_state.can_cast(): return state_machine.attack_state

	return null

# ==========================================
# ✈️ 4. 戰鬥指令包 C：空戰專用指令 
# ==========================================
func check_air_moves() -> VsState:
	var holding_down = Input.is_action_pressed(player.down_key)
	var combat_facing = player.get_node("Graphics").scale.x
	
	if player.opponent != null:
		var dir_to_opponent = sign(player.opponent.global_position.x - player.global_position.x)
		if dir_to_opponent != 0: combat_facing = dir_to_opponent

	var holding_left = Input.is_action_pressed(player.left_key)
	var holding_right = Input.is_action_pressed(player.right_key)
	var holding_forward = (combat_facing == 1.0 and holding_right) or (combat_facing == -1.0 and holding_left)
	var holding_backward = (combat_facing == 1.0 and holding_left) or (combat_facing == -1.0 and holding_right)

	# 🌟 空中大招攔截 (下+U)
	if Input.is_action_just_pressed(player.ultimate_key):
		if holding_down and state_machine.ultimate_state_2 != null and state_machine.ultimate_state_2.can_cast():
			return state_machine.ultimate_state_2

	# 🌟 空中技能 K 鍵派生
	if Input.is_action_just_pressed(player.skill_key):
		if holding_down and holding_forward and state_machine.skill_k1 != null and state_machine.skill_k1.can_cast(): 
			return state_machine.skill_k1
		if holding_down and holding_backward and state_machine.skill_k2 != null and state_machine.skill_k2.can_cast(): 
			return state_machine.skill_k2
		if holding_down and not holding_forward and not holding_backward and state_machine.skill_k3 != null and state_machine.skill_k3.can_cast(): 
			return state_machine.skill_k3
		if not holding_down and state_machine.air_skill != null and state_machine.air_skill.can_cast():
			return state_machine.air_skill

	# 🌟 空中普攻 J 鍵派生
	if Input.is_action_just_pressed(player.attack_key):
		if state_machine.air_attack != null and state_machine.air_attack.can_cast(): 
			return state_machine.air_attack
			
	return null

# ==========================================
# 🏃 5. 核心物理運算 (重力與防踩頭)
# ==========================================
func process_physics(delta: float) -> VsState:
	var interrupt = check_interrupts()
	if interrupt != null:
		return interrupt
		
	player.velocity.y += gravity * delta
	player.custom_move_and_slide()
	
	# 🛡️ 神級防踩頭系統 (Anti-Mario System)
	# 防止玩家站在對手頭上，若偵測到腳下是另一名玩家，強行給予水平推力將其滑開。
	if player.is_on_floor():
		for i in range(player.get_slide_collision_count()):
			var col = player.get_slide_collision(i)
			var collider = col.get_collider()
			
			if collider != player and collider is VsPlayer:
				# 法線 y < -0.5 代表踩在對方正上方
				if col.get_normal().y < -0.5:
					var slide_dir = sign(player.global_position.x - collider.global_position.x)
					if slide_dir == 0: slide_dir = 1.0 
					player.velocity.x = slide_dir * 800.0
					
	return null

# ==========================================
# 🛠️ 6. 通用輔助函數
# ==========================================
func do_move(move_dir: float) -> void:
	player.velocity.x = player.move_speed * move_dir
	if move_dir < 0:
		player.get_node("Graphics").scale.x = -1   
	elif move_dir > 0:
		player.get_node("Graphics").scale.x = 1
		
## 供各個技能覆寫 (Override) 使用的施法條件檢查。預設回傳 true。
func can_cast() -> bool:
	return true
