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

func _make_decision() -> void:
	if not is_instance_valid(boss.player_target): return
	
	var dist = boss.global_position.distance_to(boss.player_target.global_position)

	# 🔧 真正會被選中的追擊分支：距離太遠時，先追近再回來決策，不再嘗試遠程攻擊
	if dist > chase_trigger_distance:
		state_machine.transition_to("Chase")
		return

	var next_state = "MeleeAttack"
	var next_melee = ""

	# 🌟 防連發機制：如果抽到同一招，最多重新擲骰子 3 次
	for i in range(3):
		var roll = randf()
		next_state = "MeleeAttack"
		next_melee = ""
		
		if dist > 150:
			next_state = "MeleeAttack"; next_melee = "A8"
				
		elif dist < 60: 
			# 🔴 較近距離：A4後撤(60%)、A7近劈(30%)、A1(10%)
			if roll < 0.60: next_state = "RetreatAttack"; next_melee = "A4"
			elif roll < 0.90: next_state = "MeleeAttack"; next_melee = "A7"
			else: next_state = "MeleeAttack"; next_melee = "A1"
				
		else:
			# 🟡 中距離：A1(40%)、A3(30%)、A7(30%)
			if roll < 0.40: next_state = "MeleeAttack"; next_melee = "A1"
			elif roll < 0.70: next_state = "MeleeAttack"; next_melee = "A3"
			else: next_state = "MeleeAttack"; next_melee = "A7"
		
		# 💡 如果這招跟上一招不一樣，就滿意地跳出迴圈！
		if next_melee != last_attack:
			break

	# 記錄這次出的招式
	if next_melee != "":
		last_attack = next_melee
		boss.set_meta("next_melee", next_melee)
		
	state_machine.transition_to(next_state)
