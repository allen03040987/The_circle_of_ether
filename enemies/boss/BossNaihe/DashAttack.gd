class_name BossDashAttackState
extends BossState

var locked_facing_dir: int = 1

# ==========================================
# 🎬 狀態初始化
# ==========================================
func enter() -> void:
	boss.enter_attack_state() # 🛡️ 突進中不能被打斷，整段都算攻擊中，自動開白色霸體

	# 1. 🌟 進入狀態時：對準玩家，並將面向存入變數鎖死！
	boss.face_player()
	locked_facing_dir = boss.direction
	
	# 2. 播放 A5 突進動畫 
	# (💡 記得在 AnimationPlayer 裡利用 strike_impulse 賦予他往前衝的超大動能！)
	boss.play_safe_anim("attack_5")

# ==========================================
# 🏃 物理更新與突進煞車
# ==========================================
func physics_update(delta: float) -> void:
	# 🌟 強制覆寫面向：確保突進途中絕對不轉向，即使玩家閃到背後也一樣
	boss.direction = locked_facing_dir
	
	# 處理重力與摩擦力 (讓 strike_impulse 的強大動能隨著時間自然煞車)
	boss.velocity.x = move_toward(boss.velocity.x, 0.0, boss.acceleration * delta)
	boss.velocity.y += boss.default_gravity * delta
	
	# ✅ 遵守位移最高指導原則
	boss.custom_move_and_slide()
	
	# 動畫播完，突進結束，退回決策大腦
	if not boss.animation_player.is_playing():
		state_machine.transition_to("Decision")

# ==========================================
# 🛡️ 狀態離開防呆
# ==========================================
func exit() -> void:
	boss.exit_attack_state()
	boss.disable_hitbox()
