class_name VsPlayerRunState 
extends VsPlayerState

## 跑步狀態 (Run State)
## 處理角色在地面上的持續水平移動，並作為發動各種攻擊或閃避的跳板。

func enter() -> void:
	# 防呆機制：只要回到待機或跑動，強制恢復實體碰撞 (關閉穿透)
	player.set_pass_through(false)
	player.animation.play(run_anim)
	
func exit() -> void:
	# 離開跑步狀態時強制清除水平動能，避免切換到其他狀態時出現「溜冰/滑步」現象
	player.velocity.x = 0.0 
	
func process_physics(delta: float) -> VsState:
	# ==========================================
	# 1. 觸發「全域中斷」(衝刺、蹲下)
	# ==========================================
	var interrupt_state = super(delta) 
	if interrupt_state != null:
		return interrupt_state # 老爸核准了衝刺，直接切換，終止後續邏輯
		
	# 隨時盯著對手 (確保跑步時面朝對手，或者用後退動畫)
	player.auto_face_opponent()
	
	# ------------------------------------------
	# 狀態轉移判定：移動類
	# ------------------------------------------
	if Input.is_action_just_pressed(player.jump_key):
		return state_machine.jump_state 
		
	# 獲取方向並執行位移 (會自動根據方向翻轉角色，或切換倒退跑動畫)
	var move_dir = player.get_move_dir()
	do_move(move_dir) 
	
	# 邊緣防護：跑出懸崖邊緣，強制轉為下落狀態
	if not player.is_on_floor():
		return state_machine.fall_state
		
	# 停止輸入方向鍵時，無縫回歸待機狀態
	if move_dir == 0.0: 
		return state_machine.idle_state

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
		
	# 如果只是單純按了 J 鍵 (無方向派生)
	if Input.is_action_just_pressed(player.attack_key):
		return state_machine.attack_state 
		
	return null
