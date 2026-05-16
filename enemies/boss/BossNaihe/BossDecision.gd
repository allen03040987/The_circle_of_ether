class_name BossDecisionState
extends BossState

var decision_timer: float = 0.0

func enter() -> void:
	boss.play_safe_anim("idle")
	# 攻擊間隔，產生不規律的戰鬥節奏
	decision_timer = randf_range(1.0, 2.2)

func physics_update(delta: float) -> void:
	boss.velocity.x = move_toward(boss.velocity.x, 0.0, boss.acceleration * delta)
	boss.velocity.y += boss.default_gravity * delta
	boss.custom_move_and_slide()
	
	boss.face_player()
	
	decision_timer -= (delta * boss.action_speed_mult)
	if decision_timer <= 0:
		_make_decision()

func _make_decision() -> void:
	if not is_instance_valid(boss.player_target): return
	
	var dist = boss.global_position.distance_to(boss.player_target.global_position)
	var roll = randf() # 擲骰子
	
	if dist > 150:
		# 🟢 較遠距離：A5突刺(25%)、A6地刺(25%)、未來A8(25%)、靠近(25%)
		if roll < 0.25:
			state_machine.transition_to("DashAttack") # A5 突刺
		elif roll < 0.50:
			boss.set_meta("next_melee", "A6")
			state_machine.transition_to("MeleeAttack") # 轉交給近戰狀態放 A6
		elif roll < 0.75:
			print("🔧 [預留] 準備施放遠距離 A8！目前暫用 Chase 代替")
			state_machine.transition_to("Chase")
		else:
			state_machine.transition_to("Chase") # 走過去靠近玩家
			
	elif dist < 60: 
		# 🔴 較近距離：A4後撤(60%)、未來A7(30%)、A1A2聯招(10%)
		if roll < 0.60:
			state_machine.transition_to("RetreatAttack") # A4 後撤接劈砍
		elif roll < 0.90:
			print("🔧 [預留] 準備施放近距離 A7！目前暫用 A1 代替")
			boss.set_meta("next_melee", "A7")
			state_machine.transition_to("MeleeAttack")
		else:
			boss.set_meta("next_melee", "A1")
			state_machine.transition_to("MeleeAttack")
			
	else:
		# 🟡 一定距離 (中間)：A1A2聯招(40%)、A3單放(30%)、未來A7(30%)
		if roll < 0.40:
			boss.set_meta("next_melee", "A1")
			state_machine.transition_to("MeleeAttack")
		elif roll < 0.70:
			boss.set_meta("next_melee", "A3")
			state_machine.transition_to("MeleeAttack")
		else:
			print("🔧 [預留] 準備施放中距離 A7！目前暫用 A1 代替")
			boss.set_meta("next_melee", "A7")
			state_machine.transition_to("MeleeAttack")
