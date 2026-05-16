class_name BossMeleeState
extends BossState

var combo_count: int = 1

# ==========================================
# 🎬 狀態初始化
# ==========================================
func enter() -> void:
	# 讀取大腦傳來的指令，如果沒有就預設打 A1
	var next_move = boss.get_meta("next_melee", "A1")
	
	if next_move == "A1":
		combo_count = 1
		_play_attack_anim("attack_1")
	elif next_move == "A3":
		combo_count = 3
		_play_attack_anim("attack_3")
	elif next_move == "A6":
		combo_count = 6
		_play_attack_anim("attack_6")
	elif next_move == "A7":
		combo_count = 7 
		_play_attack_anim("attack_7") # A7 還沒做好，先播 A1 代替

func _play_attack_anim(anim_name: String) -> void:
	boss.face_player() # 每一刀揮出前，都會重新瞄準玩家一次
	
	if boss.animation_player.has_animation(anim_name):
		boss.play_safe_anim(anim_name)
	else:
		printerr("⚠️ BOSS 找不到攻擊動畫: ", anim_name)
		state_machine.transition_to("Decision")

# ==========================================
# 🏃 物理更新與連段派生 (A1 -> A2 -> A3)
# ==========================================
func physics_update(delta: float) -> void:
	# 腳步摩擦力煞車
	boss.velocity.x = move_toward(boss.velocity.x, 0.0, boss.acceleration * delta)
	boss.velocity.y += boss.default_gravity * delta
	boss.custom_move_and_slide() # ✅ 遵守最高指導原則
	
	# 🎬 動畫播完的「派生判定」
	if not boss.animation_player.is_playing():
		if combo_count == 1:
			combo_count = 2
			_play_attack_anim("attack_2")
			
		elif combo_count == 2:
			# 🌟 A1A2 打完後，60% 機率打 A3，40% 見好就收！
			if randf() < 0.60:
				combo_count = 3
				_play_attack_anim("attack_3")
			else:
				state_machine.transition_to("Decision")
				
		elif combo_count in [3, 6, 7]: # 單發招式播完，退回大腦
			state_machine.transition_to("Decision")

# ==========================================
# 🛡️ 狀態離開防呆
# ==========================================
func exit() -> void:
	boss.disable_hitbox()
