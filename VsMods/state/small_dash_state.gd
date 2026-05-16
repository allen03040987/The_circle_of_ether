class_name VsPlayerSmallDashState
extends VsPlayerState

## 小衝刺狀態 (Small Dash / Step Dash)
## 處理雙擊方向鍵觸發的墊步。通常速度較快、距離較短，且伴隨輕微的速度衰減。

@export var dash_speed: float = 600.0
@export var dash_duration: float = 0.2

@export_group("👻 殘影設定")
@export var ghost_color: Color = Color(0.4, 0.8, 1.0, 0.6) 
@export var ghost_interval: float = 0.04 

var timer: float = 0.0
var ghost_timer: float = 0.0 

func enter() -> void:
	player.current_stamina -= player.small_dash_cost
	player.animation.play("dash_small") 
	timer = dash_duration
	ghost_timer = 0.0 
	
	var facing_dir = player.get_node("Graphics").scale.x
	player.velocity.x = facing_dir * dash_speed
	player.velocity.y = 0.0

func exit() -> void:
	# 🌟 煞車防滑：強制切斷動能與判定
	player.velocity.x = 0.0
	player.deactivate_all_hitboxes()

func process_physics(delta: float) -> VsState:
	# 🌟 快速急停：按住「下」時，立即中斷衝刺進入蹲下
	if Input.is_action_pressed(player.down_key) and player.is_on_floor():
		return state_machine.crouch_state

	# --- 衝刺取消 (Dash Cancel) 神級攔截網 ---
	if Input.is_action_just_pressed(player.jump_key):
		return state_machine.jump_state
	
	var pressed_skill = Input.is_action_just_pressed(player.skill_key)
	var pressed_atk = Input.is_action_just_pressed(player.attack_key)
	
	if pressed_skill or pressed_atk:
		var combat_facing = player.get_node("Graphics").scale.x
		if player.opponent != null:
			var dir_to_opponent = sign(player.opponent.global_position.x - player.global_position.x)
			if dir_to_opponent != 0: combat_facing = dir_to_opponent

		var holding_down = Input.is_action_pressed(player.down_key)
		var holding_left = Input.is_action_pressed(player.left_key)
		var holding_right = Input.is_action_pressed(player.right_key)

		var holding_forward = (combat_facing == 1.0 and holding_right) or (combat_facing == -1.0 and holding_left)
		var holding_backward = (combat_facing == 1.0 and holding_left) or (combat_facing == -1.0 and holding_right)

		if pressed_skill:
			if holding_down and holding_forward and state_machine.skill_k1 != null and state_machine.skill_k1.can_cast(): return state_machine.skill_k1
			if holding_down and holding_backward and state_machine.skill_k2 != null and state_machine.skill_k2.can_cast(): return state_machine.skill_k2
			if state_machine.skill_neutral != null and state_machine.skill_neutral.can_cast(): return state_machine.skill_neutral
		elif pressed_atk:
			if state_machine.attack_state != null and state_machine.attack_state.can_cast(): 
				return state_machine.attack_state

	# --- 物理與殘影生成 ---
	ghost_timer -= delta
	if ghost_timer <= 0.0:
		player.spawn_afterimage(ghost_color, 0.3, Vector2(0, -20))
		ghost_timer = ghost_interval 
	
	# 🌟 小衝刺特有物理：不像是大衝刺的定速，小衝刺會受到地面摩擦力的一半影響，產生「滑行衰減」的手感！
	player.velocity.x = move_toward(player.velocity.x, 0.0, player.ground_friction * 0.5 * delta)
	player.velocity.y = 0.0
	
	player.custom_move_and_slide()
	
	timer -= delta
	if timer <= 0.0:
		if player.is_on_floor():
			return state_machine.crouch_state if Input.is_action_pressed(player.down_key) else state_machine.idle_state
		return state_machine.fall_state
		
	return null
