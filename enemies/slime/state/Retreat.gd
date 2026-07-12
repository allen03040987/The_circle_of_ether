extends SlimeState
## 發現玩家後先往後退一小段距離（面向不變，退完準備跳撲）——退到懸崖邊就提前停下，不會真的走下去

var _start_x: float = 0.0

func enter() -> void:
	_start_x = slime.global_position.x
	slime.animation_player.play("walk") # 沒有專屬後退動畫，先沿用既有的 walk 當佔位

func physics_update(delta: float) -> void:
	if check_death(): return
	var target = check_damage_interrupt()
	if target != "":
		state_machine.transition_to(target)
		return

	# 🔧 改用 back_floor_checker（跟 floor_checker 鏡射，永遠看向面向的反方向）預先偵測懸崖，
	# 走到懸崖邊「之前」就停下來，不是等真的踩空(is_on_floor() 反應式偵測)才煞車——
	# 反應式偵測必須整個碰撞形狀都離開地板才會觸發，實際上已經懸空好幾格，這才是真的會掉下去的根因
	if not slime.back_floor_checker.is_colliding():
		slime.velocity.x = 0
		state_machine.transition_to("Prepare")
		return

	slime.velocity.x = -slime.direction * slime.retreat_speed
	slime.velocity.y += slime.default_gravity * delta
	slime.custom_move_and_slide()

	if absf(slime.global_position.x - _start_x) >= slime.retreat_distance:
		slime.velocity.x = 0
		state_machine.transition_to("Prepare")
