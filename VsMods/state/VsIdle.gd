class_name VsPlayerIdleState
extends VsPlayerState

## 待機狀態 (Idle State)
## 處理基礎站立、重置跳躍次數，並作為所有地面動作與狀態切換的起點。


func enter() -> void: 
	player.jump_count = 0 # 落地瞬間重置跳躍次數
	
	# 防呆機制：只要回到待機，強制恢復實體碰撞 (關閉穿透)
	player.set_pass_through(false)
	
	player.animation.play(idle_anim)
	
func process_physics(delta: float) -> VsState:
	
	# ==========================================
	# 1. 觸發「全域中斷」(衝刺、蹲下)
	# ==========================================
	var interrupt_state = super(delta) 
	if interrupt_state != null:
		return interrupt_state # 若老爸核准了衝刺，直接切換，終止後續邏輯
		 
	# 隨時盯著對手 (確保在待機時總是面朝對手)
	player.auto_face_opponent()
	
	# 沙包攔截：僅套用重力，禁止沙包產生任何主動行為與狀態切換
	if player.is_dummy:
		return null
		
	# ------------------------------------------
	# 狀態轉移判定：移動類
	# ------------------------------------------
	if Input.is_action_just_pressed(player.jump_key):
		return state_machine.jump_state 
		
	if Input.get_axis(player.left_key, player.right_key) != 0.0:
		return state_machine.run_state
		
	# 邊緣防護：如果腳下懸空 (走下台階)，強制切換至下落狀態
	if not player.is_on_floor():
		return state_machine.fall_state
	
	# ------------------------------------------
	# 狀態轉移判定：攻擊類 (依據優先級攔截)
	# ------------------------------------------
	# 🌟 優先檢查大招與特殊技能 (U 鍵 / Custom 鍵)
	var special_action = check_offensive_skills()
	if special_action != null:
		return special_action
		
	# 🌟 檢查一般普攻與搓招 (J 與 K 鍵)
	var ground_move = check_ground_moves()
	if ground_move != null:
		return ground_move
	
	# 如果只是單純按了 J 鍵 (無方向)，且沒有被搓招攔截
	if Input.is_action_just_pressed(player.attack_key):
		return state_machine.attack_state 
	
	# 確保待機時完全靜止，防止殘留動能導致滑行
	player.velocity.x = 0.0
	return null
