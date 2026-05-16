class_name VsPlayerDownState
extends VsPlayerState

## 倒地狀態 (Down State / Hard Knockdown)
## 處理被重擊擊飛後的落地彈跳、地面滑行煞車，以及高手的「落地受身 (Tech Recovery)」機制。

var lie_down_timer: float = 1.0
var has_bounced: bool = false 

func enter() -> void:
	lie_down_timer = 1.0
	has_bounced = false
	
	# 落地反作用力：強制給予一個微幅向上的彈跳力道，製造墜地的重量感
	player.velocity.y = -200.0 
	
	# 動能衰減：撞擊地面瞬間損失 20% 水平速度
	player.velocity.x *= 0.8 
	
	# 播放墜落與撞地的過渡動畫
	player.animation.play("hurt_fly_start")
	player.animation.queue("lie_down") 

func process_physics(delta: float) -> VsState:
	# 執行基底狀態的重力運算，把人往地上拉
	super(delta) 
	
	if player.is_on_floor():
		# 🌟 階段 1：首次徹底觸地判定 (彈跳結束)
		if not has_bounced:
			has_bounced = true
			player.animation.play("hurt_fly_loop_2") # 播放痛苦掙扎或躺平的動畫
		
		# 🌟 階段 2：躺在地上 (受身判定區與煞車)
		else:
			# ---------------------------------------------------------
			# 🛡️ 全向落地受身 (Omni-Directional Tech Recovery)
			# ---------------------------------------------------------
			# 只要玩家在黃金時間內雙擊方向鍵 (不論前後)，即可消耗體力翻滾逃脫！
			var tech_dir = player.double_tapped_dir 
			
			# 設定受身視窗：例如 lie_down_timer 起始是 1.0，那麼 0.85 以上就是落地後的前 0.15 秒黃金時機
			if tech_dir != 0 and lie_down_timer > 0.85:
				if player.current_stamina >= player.small_dash_cost:
					player.current_stamina -= player.small_dash_cost
					
					# 關鍵：將角色朝向強制設定為「受身衝刺的方向」，方便接續後續動作
					player.get_node("Graphics").scale.x = tech_dir
					
					# 瞬間脫離倒地狀態，進入衝刺翻滾狀態！
					return state_machine.small_dash_state
			# ---------------------------------------------------------

		# 地面滑行物理：依據 Hitbox 傳過來的專屬擊退摩擦力，平滑煞車直到停止
		player.velocity.x = move_toward(player.velocity.x, 0.0, player.received_friction * delta)
		
		# 躺平時間倒數 (僅在完全貼地時進行)
		lie_down_timer -= delta
		if lie_down_timer <= 0.0:
			# 躺夠了，強制進入起身狀態 (GetupState)
			return state_machine.getup_state 
			
	return null
