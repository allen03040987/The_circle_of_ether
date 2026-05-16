class_name VsPlayerCrouchState
extends VsPlayerState

## 蹲下狀態 (Crouch State)
## 降低被擊中判定，並作為下段攻擊 (Low Attacks) 與防禦 (Low Guard) 的前置狀態。

func _ready():
	can_block = true # 🌟 在這裡加上！待機可以防禦

func enter() -> void:
	player.animation.play("crouch") 

func process_physics(delta: float) -> VsState:
	
	# 🌟 1. 核心修復：先呼叫 super 處理重力與防踩頭，並攔截位移中斷
	var parent_state = super(delta) 
	if parent_state != null:
		return parent_state # 例如突然被揍，或自己按了衝刺，優先切換！
		
	# 🌟 2. 讓蹲下也能開大招與時停！
	var special_action = check_offensive_skills()
	if special_action != null:
		return special_action
		
	# 🌟 3. 讓蹲下也能搓出專屬下段招式 (下+前+K, 下+J 等等)
	var ground_move = check_ground_moves()
	if ground_move != null:
		return ground_move
		
	# 物理：保持蹲下的地面摩擦力 (防止滑步)
	player.velocity.x = move_toward(player.velocity.x, 0.0, player.ground_friction * delta)
	
	# 視角：隨時盯著對手，防止被跳背
	player.auto_face_opponent() 
	
	# 只要放開下鍵，就站起來
	if not Input.is_action_pressed(player.down_key):
		return state_machine.idle_state 
		
	# 防禦邏輯已在 Hurtbox 處理，這裡只需回傳 null 繼續維持蹲下即可
	return null
