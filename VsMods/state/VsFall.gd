class_name VsPlayerFallState
extends VsPlayerState

## 下落狀態 (Fall State)
## 處理空中下墜、空中位移與著地 (Landing) 判定。
func _ready():
	can_block = true # 🌟 在這裡加上！待機可以防禦


func enter() -> void:
	# 防呆機制：確保下落時沒有無敵穿透
	player.set_pass_through(false)
	player.animation.play("fall") 

func process_physics(delta: float) -> VsState:
	# ==========================================
	# 接收全域中斷 (空中衝刺)
	# ==========================================
	var interrupt_state = super(delta) 
	if interrupt_state != null:
		return interrupt_state
	
	# 🌟 1. 攔截大招與特殊技能
	var special_action = check_offensive_skills()
	if special_action != null:
		return special_action
		
	# 🌟 2. 攔截空中專屬普攻與技能 
	var air_move = check_air_moves()
	if air_move != null:
		return air_move
	
	# 允許空中水平位移
	do_move(player.get_move_dir())
	
	# 空中二段跳判定 (如果玩家是走下懸崖而不是跳下去的，還能保留一次跳躍機會)
	if Input.is_action_just_pressed(player.jump_key) and player.jump_count < player.max_jumps:
		return state_machine.jump_state
	
	# 著地判定與狀態分流
	if player.is_on_floor():
		player.jump_count = 0 
		
		# 依據著地瞬間的輸入狀態決定後續動作 (落地無縫奔跑)
		if player.get_move_dir() == 0.0:
			return state_machine.idle_state
		else:
			return state_machine.run_state
			
	return null
