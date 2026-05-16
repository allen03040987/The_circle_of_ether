class_name VsPlayerJumpState 
extends VsPlayerState

## 跳躍狀態 (Jump State)
## 處理起跳瞬間的推力、空中位移，以及多段跳躍 (二段跳) 邏輯。

func _ready():
	can_block = true # 🌟 在這裡加上！待機可以防禦


func enter() -> void:
	player.animation.play("jump")
	
	# 讀取玩家本體的專屬跳躍力度 (給予向上的負速度)
	player.velocity.y = player.jump_force
	player.jump_count += 1

func process_physics(delta: float) -> VsState:
	# ==========================================
	# 接收全域中斷 (空中衝刺、空中技能)
	# ==========================================
	var interrupt_state = super(delta) 
	if interrupt_state != null:
		return interrupt_state
	
	# 🌟 1. 攔截大招與特殊技能 (讓玩家在空中也能開大招或時停)
	var special_action = check_offensive_skills()
	if special_action != null:
		return special_action
		
	# 🌟 2. 攔截空中專屬普攻與技能 (空中 J / 空中 K)
	var air_move = check_air_moves()
	if air_move != null:
		return air_move
	
	# 處理空中左右橫移 (吃空氣阻力或移動速度)
	do_move(player.get_move_dir())            
	
	# 多段跳躍 (二段跳) 邏輯判定
	if Input.is_action_just_pressed(player.jump_key) and player.jump_count < player.max_jumps:
		# 再次給予向上的專屬跳躍力度
		player.velocity.y = player.jump_force 
		player.jump_count += 1
		# 重新播放動畫以重置視覺表現
		player.animation.play("jump")     
	
	# 當垂直速度大於等於零，代表達到最高點準備下墜，切換至下落狀態
	if player.velocity.y >= 0:
		return state_machine.fall_state
		
	return null
