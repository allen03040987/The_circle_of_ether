extends SlimeState
## 🔧 跟原本 enum FSM 的行為對齊：原本的手寫迴圈沒有「同狀態不重入」防呆，
## 已經在 Hurt 中被連續打，一樣會重新套用擊退+重播動畫。但 classes/StateMachine.gd::transition_to()
## 對同一個狀態物件是no-op（防止原地反覆橫跳），所以「重新進 Hurt」要繞過 transition_to()，直接呼叫 _apply_hit()
## ——這正是 BossNaihe/Hurt.gd 當初遇到並修掉的同一個坑。

const MAX_STUCK_TIME := 3.0 ## 保險：萬一落點卡在奇怪地形導致 is_on_floor() 一直不成立，最多卡這麼久就強制放行，不會永遠打不醒

var _recovery_timer: float = 0.0

func enter() -> void:
	_apply_hit()

func physics_update(delta: float) -> void:
	if check_death(): return

	var target = check_damage_interrupt()
	if target == "hurt":
		_apply_hit()
	elif target == "launched":
		state_machine.transition_to("launched")
		return

	var knockback_friction = slime.max_speed * 3.0
	slime.velocity.x = move_toward(slime.velocity.x, 0.0, knockback_friction * delta)
	slime.velocity.y += slime.default_gravity * delta
	slime.custom_move_and_slide()

	_recovery_timer += delta
	var recovery_ready = not slime.animation_player.is_playing() and _recovery_timer >= slime.hurt_recovery_time
	if (recovery_ready and slime.is_on_floor()) or _recovery_timer >= MAX_STUCK_TIME:
		state_machine.transition_to("walk")

func _apply_hit() -> void:
	# 🔧 每次被打都重新計時：連續挨打不會提早跳出硬直
	_recovery_timer = 0.0
	slime.animation_player.stop()
	slime.animation_player.play("hit")
	var p_knockback: Vector2 = slime.pending_damage["knockback_force"]
	slime.velocity.x = p_knockback.x
	slime.velocity.y = p_knockback.y
	if not is_zero_approx(p_knockback.x):
		slime.direction = Enemy.Direction.LEFT if p_knockback.x > 0 else Enemy.Direction.RIGHT
	slime.pending_damage = null
