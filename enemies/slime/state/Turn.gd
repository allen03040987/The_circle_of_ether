extends SlimeState
## 走到巡邏邊界/撞牆/懸崖後，停下來等 turn_wait_time，時間到就掉頭繼續巡邏

const MAX_CONSECUTIVE_TURNS := 2 ## 連續掉頭這麼多次還是卡住，代表兩個方向都走不了，乾脆放棄別再掉頭

func enter() -> void:
	slime.velocity.x = 0
	slime.animation_player.play("idle")
	slime.consecutive_turns += 1

func physics_update(delta: float) -> void:
	if check_death(): return
	var target = check_damage_interrupt()
	if target != "":
		state_machine.transition_to(target)
		return

	if slime.can_see_player() and slime.attack_cooldown <= 0:
		state_machine.transition_to("Retreat")
		return

	slime.velocity.y += slime.default_gravity * delta
	slime.custom_move_and_slide()

	if state_machine.state_time >= slime.turn_wait_time:
		# 🔧 兩邊都走不了時（一邊超出巡邏範圍/懸崖、另一邊有牆），掉頭只會讓她立刻在 Walk 裡
		# 被打回這裡，每 turn_wait_time 一次、無限循環——偵測到卡住就乾脆待著不再嘗試，
		# 等 can_see_player() 或被打斷等外部事件改變狀況再說
		if slime.consecutive_turns >= MAX_CONSECUTIVE_TURNS:
			return
		slime.direction *= -1
		state_machine.transition_to("Walk")
