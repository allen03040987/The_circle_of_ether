extends SlimeState
## 跳撲攻擊：往 direction 方向跳起，重力自然把它拉成一個弧形拋物線，落地才算攻擊結束

const MAX_AIRBORNE_TIME := 3.0 ## 保險：跳到懸崖外、落點卡在奇怪地形導致 is_on_floor() 一直不成立時，最多飛這麼久就強制當作落地

func enter() -> void:
	slime.enter_attack_state() # 霸體掛鉤：LOW 階目前是 no-op，但保持跟其他敵人一致的呼叫慣例
	slime.animation_player.play("run") # 沒有專屬跳撲動畫，先沿用既有的 run 當佔位

	slime.velocity = Vector2(slime.direction * slime.hop_velocity.x, slime.hop_velocity.y)

	if slime.hitbox:
		slime.hitbox.damage_amount = slime.base_damage
		slime.hitbox.attack_type = Damage.Type.LIGHT
		slime.hitbox.knockback_force = slime.base_knockback
		if "shake_intensity" in slime.hitbox: slime.hitbox.shake_intensity = 3.0
	slime.hitbox_shape.set_deferred("disabled", false)

func exit() -> void:
	slime.exit_attack_state()
	slime.hitbox_shape.set_deferred("disabled", true)
	slime.velocity.x = 0
	slime.attack_cooldown = slime.attack_cooldown_time

func physics_update(delta: float) -> void:
	if check_death(): return
	var target = check_damage_interrupt()
	if target != "":
		state_machine.transition_to(target)
		return

	slime.velocity.y += slime.default_gravity * delta
	slime.custom_move_and_slide()

	# 🔧 state_time > 0.05 是為了跳過剛起跳那一瞬間——move_and_slide() 還沒真的把它抬離地面前，
	# is_on_floor() 有可能還是 true，會被誤判成「還沒跳就已經落地」
	if state_machine.state_time > 0.05 and (slime.is_on_floor() or state_machine.state_time >= MAX_AIRBORNE_TIME):
		state_machine.transition_to("Land")
