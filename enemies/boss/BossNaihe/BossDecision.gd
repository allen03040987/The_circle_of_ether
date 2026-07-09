class_name BossDecisionState
extends BossState

# 🌟 補回：超過這個距離就先追擊拉近，不再無腦嘗試遠程攻擊
@export var chase_trigger_distance: float = 300.0

var decision_timer: float = 0.0
var last_attack: String = "" # 🌟 新增：讓 Boss 有記憶，記住上一招放了什麼

func enter() -> void:
	boss.play_safe_anim("idle")
	# 🌟 加快攻擊頻率：原本 1.0 ~ 2.2 秒，現在縮短為 0.5 ~ 1.2 秒！
	# (如果覺得太瘋狗，可以微調成 0.8 ~ 1.5)
	decision_timer = randf_range(0.5, 1.0)

func physics_update(delta: float) -> void:
	boss.velocity.x = move_toward(boss.velocity.x, 0.0, boss.acceleration * delta)
	boss.velocity.y += boss.default_gravity * delta
	boss.custom_move_and_slide()
	
	boss.face_player()
	
	decision_timer -= (delta * boss.action_speed_mult)
	if decision_timer <= 0:
		_make_decision()

## 供外部（BossNaihe 的受擊處理）在閘門到期當下強制立刻決策，不必等 decision_timer 倒數完
func force_next_decision() -> void:
	_make_decision()

func _make_decision() -> void:
	if not is_instance_valid(boss.player_target): return

	# 🌟 硬直懲罰閘門：被打斷後要等隨機 2~4 秒且落地，才會繼續出招（期間持續播 idle）
	if not boss.is_hurt_gate_open():
		decision_timer = 0.1
		return

	var dist = boss.global_position.distance_to(boss.player_target.global_position)

	# 🔧 距離太遠時：30% A5 突進、30% A6 蔓延地刺、40% 追近再回來決策
	if dist > chase_trigger_distance:
		var far_roll = randf()
		if far_roll < 0.30:
			last_attack = "A5"
			state_machine.transition_to("DashAttack")
		elif far_roll < 0.60:
			last_attack = "A6"
			boss.set_meta("next_melee", "A6")
			state_machine.transition_to("MeleeAttack")
		else:
			state_machine.transition_to("Chase")
		return

	var next_state = "MeleeAttack"
	var next_melee = ""

	# 🌟 防連發機制：如果抽到同一招，最多重新擲骰子 3 次
	for i in range(3):
		var roll = randf()
		next_state = "MeleeAttack"
		next_melee = ""
		
		if dist < 60:
			# 🔴 較近距離：A4後撤(60%)、A7近劈(30%)、A1(10%)
			if roll < 0.60: next_state = "RetreatAttack"; next_melee = "A4"
			elif roll < 0.90: next_state = "MeleeAttack"; next_melee = "A7"
			else: next_state = "MeleeAttack"; next_melee = "A1"

		else:
			# 🟡 中距離 (60~300)：A4後撤(20%)、A8吸引突進(20%)、A7近劈(30%)、A1(10%)
			if roll < 0.30: next_state = "RetreatAttack"; next_melee = "A4"
			elif roll < 0.60: next_state = "MeleeAttack"; next_melee = "A8"
			elif roll < 0.80: next_state = "MeleeAttack"; next_melee = "A7"
			else: next_state = "MeleeAttack"; next_melee = "A1"
		
		# 💡 如果這招跟上一招不一樣，就滿意地跳出迴圈！
		if next_melee != last_attack:
			break

	# 記錄這次出的招式
	if next_melee != "":
		last_attack = next_melee
		boss.set_meta("next_melee", next_melee)
		
	state_machine.transition_to(next_state)
