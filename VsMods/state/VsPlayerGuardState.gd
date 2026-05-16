class_name VsPlayerGuardState
extends VsPlayerState

## 防禦狀態 (Guard State / Block Stun)
## 當玩家成功拉後或蹲下擋住攻擊時進入此狀態。處理防禦硬直 (Block Stun) 與防禦滑行 (Pushback)。

func enter() -> void:
	# 播放舉起武器擋格的動畫
	player.animation.play("guard") 

func process_physics(delta: float) -> VsState:
	# 即使在防禦中，也要隨時緊盯對手 (防止對手用瞬移技打背)
	player.auto_face_opponent()
	
	# 1. 處理防禦被擊退時的摩擦力滑行 (讀取 Hurtbox 計算後的 pushback 數據)
	player.velocity.x = move_toward(player.velocity.x, 0.0, player.received_friction * delta)
	
	# 執行基底的重力運算
	super(delta)
	
	# 2. 扣除防禦硬直時間 (Block Stun)
	# (注意：VsHurtbox 中已將防禦硬直設定為受擊硬直的 0.6 倍，讓防禦方有幀數優勢)
	player.hitstun_time_left -= delta
	
	# 3. 硬直結束，判斷該回歸什麼狀態
	if player.hitstun_time_left <= 0.0:
		if Input.is_action_pressed(player.down_key):
			return state_machine.crouch_state # 如果玩家還按著下，繼續蹲著
		else:
			return state_machine.idle_state   # 否則站起來恢復自由
			
	return null
