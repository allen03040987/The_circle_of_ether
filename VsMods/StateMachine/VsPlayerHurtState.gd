class_name VsPlayerHurtState
extends VsPlayerState

## 受擊狀態 (HurtState)
## 專門處理被攻擊後的硬直動畫、空中擊飛與落地受身邏輯。

var stun_timer: float = 0.0
var is_aerial_hurt: bool = false # 記憶這次受擊是不是「空中受擊」

func enter() -> void:
	# 防呆機制：只要進入受擊狀態，強制關閉穿透，恢復實體碰撞！
	player.set_pass_through(false)
	
	# 🌟 只要被打的瞬間「腳不在地上」，或是「被往上打飛 (knockback.y < 0)」，都算空中受擊！
	is_aerial_hurt = not player.is_on_floor() or player.received_knockback.y < 0
	
	if is_aerial_hurt:
		player.animation.play("hurt_fly_start")
		player.animation.queue("hurt_fly_loop")
	else:
		match player.received_hit_type:
			VsHitbox.HitType.LIGHT:
				player.animation.play("hurt_light")  
			VsHitbox.HitType.MEDIUM:
				player.animation.play("hurt_medium") 
			VsHitbox.HitType.HEAVY:
				player.animation.play("hurt_heavy")  
	
	stun_timer = player.hitstun_time_left
	player.velocity = player.received_knockback

func process_physics(delta: float) -> VsState:
	# 繼承基礎狀態的重力與移動運算
	super(delta) 
	
	# ==========================================
	# 1. 玩家還在空中 (等待落地)
	# ==========================================
	if not player.is_on_floor():
		return null
		
	# ==========================================
	# 2. 玩家碰到了地板
	# ==========================================
	else:
		# 情況 A：這是一個從空中掉下來的墜落！
		if is_aerial_hurt:
			if player.received_causes_down:
				return state_machine.down_state  # 招式附帶強制倒地 ➡️ 狠狠摔在地上，進入 DownState
			else:
				return state_machine.idle_state  # 沒強制倒地 ➡️ 完美落地受身 (Air Reset)！直接回歸待機
			
		# 情況 B：這是一個扎實的平地受擊！
		else:
			# 處理平地受擊的摩擦滑行與硬直倒數
			player.velocity.x = move_toward(player.velocity.x, 0.0, player.received_friction * delta)
			stun_timer -= delta
			
			# 硬直結束後的狀態分流
			if stun_timer <= 0.0:
				if player.received_causes_down:
					return state_machine.down_state  # 🌟 隱藏機制：平地癱軟倒地 (Crumple)
				else:
					return state_machine.idle_state  # 硬直結束，恢復自由
			
	return null
