extends State

# ==========================================
# 🎬 狀態生命週期 (State Lifecycle)
# ==========================================
func enter() -> void:
	# 1. 召回劍鞘 (防止隱形)
	if player.scabbard:
		player.scabbard.fade_in()
	
	# 2. 播放死亡動畫
	player.play_safe_anim("die")
	
	# 3. 停止無敵與特殊狀態，恢復實體
	player.invincible_timer.stop()
	player.is_perfect_dodging = false
	player.graphics.modulate.a = 1.0 

func physics_update(delta: float) -> void:
	# 1. 死亡後依然受重力與摩擦力影響 (避免死在半空中)
	player.velocity.x = move_toward(player.velocity.x, 0.0, player.FLOOR_ACCELERATION * delta)
	player.velocity.y += player.default_gravity * delta
	player.custom_move_and_slide()
	
	# 2. 落地與動畫結束判定
	if not player.animation_player.is_playing() and player.is_on_floor():
		player.set_physics_process(false) # 停止玩家的所有物理運算
		player.die() # 呼叫玩家大腦的死亡函數 (觸發 UI)
