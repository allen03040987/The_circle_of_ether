class_name VsPlayerBigDashState
extends VsPlayerState

## 大衝刺狀態 (Big Dash State)
## 處理按下專屬衝刺鍵時的高速突進，包含殘影生成與「衝刺取消 (Dash Cancel)」派生攻擊。

@export var dash_speed: float = 510.0
@export var dash_duration: float = 0.28
@export var ghost_color: Color = Color(0.8, 0.3, 1.0, 0.6) 
@export var ghost_interval: float = 0.04 

var timer: float = 0.0
var ghost_timer: float = 0.0 

func enter() -> void:
	# 消耗體力並啟動動畫
	player.current_stamina -= player.big_dash_cost
	player.animation.play("dash_big")
	
	timer = dash_duration
	ghost_timer = 0.0 
	
	# 強制賦予水平速度，並暫停 Y 軸重力 (讓空中衝刺能保持水平飛行)
	var facing_dir = player.get_node("Graphics").scale.x
	player.velocity.x = facing_dir * dash_speed
	player.velocity.y = 0.0 

func exit() -> void:
	# 🌟 煞車防滑：離開衝刺時 (不管是自然結束還是被攻擊打斷)，強制切斷物理速度，防止異常滑行！
	player.velocity.x = 0.0
	player.deactivate_all_hitboxes()

func process_physics(delta: float) -> VsState:
	# 🌟 快速急停：按住「下」時，立即中斷衝刺進入蹲下
	if Input.is_action_pressed(player.down_key) and player.is_on_floor():
		return state_machine.crouch_state

	# --- 衝刺取消 (Dash Cancel) 神級攔截網 ---
	# 允許在衝刺的過程中，直接用跳躍或攻擊打斷衝刺，保持壓制節奏！
	if Input.is_action_just_pressed(player.jump_key):
		return state_machine.jump_state
	
	var pressed_skill = Input.is_action_just_pressed(player.skill_key)
	var pressed_atk = Input.is_action_just_pressed(player.attack_key)
	
	if pressed_skill or pressed_atk:
		# 取得以對手為基準的絕對戰鬥朝向
		var combat_facing = player.get_node("Graphics").scale.x
		if player.opponent != null:
			var dir_to_opponent = sign(player.opponent.global_position.x - player.global_position.x)
			if dir_to_opponent != 0: combat_facing = dir_to_opponent

		var holding_down = Input.is_action_pressed(player.down_key)
		var holding_left = Input.is_action_pressed(player.left_key)
		var holding_right = Input.is_action_pressed(player.right_key)

		var holding_forward = (combat_facing == 1.0 and holding_right) or (combat_facing == -1.0 and holding_left)
		var holding_backward = (combat_facing == 1.0 and holding_left) or (combat_facing == -1.0 and holding_right)

		# 衝刺派生：技能 (K)
		if pressed_skill:
			if holding_down and holding_forward and state_machine.skill_k1 != null and state_machine.skill_k1.can_cast(): return state_machine.skill_k1
			if holding_down and holding_backward and state_machine.skill_k2 != null and state_machine.skill_k2.can_cast(): return state_machine.skill_k2
			if state_machine.skill_neutral != null and state_machine.skill_neutral.can_cast(): return state_machine.skill_neutral
		
		# 衝刺派生：普攻 (J)
		elif pressed_atk:
			if state_machine.attack_state != null and state_machine.attack_state.can_cast(): 
				return state_machine.attack_state

	# --- 物理與殘影生成 ---
	ghost_timer -= delta
	if ghost_timer <= 0.0:
		player.spawn_afterimage(ghost_color, 0.3, Vector2(0, -20)) 
		ghost_timer = ghost_interval
		
	# 強制抵抗重力
	player.velocity.y = 0.0 
	player.custom_move_and_slide()
	
	# 衝刺時間倒數
	timer -= delta
	if timer <= 0.0:
		if player.is_on_floor():
			# 衝刺結束時若按著下就繼續蹲著，否則站起來
			return state_machine.crouch_state if Input.is_action_pressed(player.down_key) else state_machine.idle_state
		return state_machine.fall_state # 若在空中衝刺結束，開始下墜
		
	return null
