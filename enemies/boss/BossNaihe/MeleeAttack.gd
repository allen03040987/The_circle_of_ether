class_name BossMeleeState
extends BossState

var combo_count: int = 1

# ==========================================
# 🎬 狀態初始化
# ==========================================
func enter() -> void:
	boss.enter_attack_state() # 🛡️ HIGH 階整段近戰連段(A1~A9 不管怎麼派生)期間都算攻擊中，自動開白色霸體

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
		# 🌟 黃圈技範例：這招前搖足足 1.44 秒，開 1.0 秒判定窗，期間被「對策技」(breaks_guard) 命中就會被彈開
		boss.start_guard_window(1.0)
		# 🔧 標記這招的 Hitbox 是黃圈技專屬：只有對策技能破解，逆鱗返這類通用彈反型招式對它無效
		var weapon_hb = boss.get_node_or_null("Graphics/WeaponHitbox") as Hitbox
		if weapon_hb: weapon_hb.requires_countermeasure = true
		_play_attack_anim("attack_7")
	elif next_move == "A8":
		combo_count = 8
		_play_attack_anim("attack_8")
	else:
		# 🔧 保底：next_melee 若殘留無法辨識的值（例如 A4，那是 RetreatAttack 專屬招），一律當 A1 處理，避免啞火站定原地
		combo_count = 1
		_play_attack_anim("attack_1")

func _play_attack_anim(anim_name: String) -> void:
	boss.face_player() # 每一刀揮出前，都會重新瞄準玩家一次
	
	# ==========================================
	# 🌟 臨時測試：強制修改 Boss 近戰判定框的火花
	# ==========================================
	# (請確認你的 Boss 近戰判定框節點名稱是不是叫 "Hitbox"，如果不是請改一下字串)
	var hitbox = boss.get_node_or_null("WeaponHitbox") as Hitbox 
	
	# ==========================================
	
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
		
		# 🌟 在這裡插入 A8 轉 A9 的無縫派生
		elif combo_count == 8:
			print("🌪️ A8 吸取完畢！玩家已進入斬殺線，發動 A9！")
			combo_count = 9
			_play_attack_anim("attack_2")
			
		elif combo_count in [3, 6, 7, 9]: # 🌟 記得把 9 加進這個陣列，讓 A9 播完能退回 Decision
			state_machine.transition_to("Decision")

# ==========================================
# 🛡️ 狀態離開防呆
# ==========================================
func exit() -> void:
	boss.exit_attack_state()
	boss.disable_hitbox()
	# 🔧 離開時清掉黃圈技標記，避免殘留影響下一招
	var weapon_hb = boss.get_node_or_null("Graphics/WeaponHitbox") as Hitbox
	if weapon_hb: weapon_hb.requires_countermeasure = false
