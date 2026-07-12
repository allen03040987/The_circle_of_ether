extends SlimeState
## 巡邏：進場時隨機挑一個不超過 max_walk_distance 的距離、以及一個隨機速度，走到這個距離、撞牆、或懸崖，就轉去 Turn 掉頭

var _start_x: float = 0.0
var _target_distance: float = 0.0
var _current_speed: float = 0.0

func enter() -> void:
	slime.animation_player.play("walk")
	_start_x = slime.global_position.x
	_target_distance = randf_range(0.0, slime.max_walk_distance)
	_current_speed = randf_range(slime.min_walk_speed, slime.max_speed)

func physics_update(delta: float) -> void:
	if check_death(): return
	var target = check_damage_interrupt()
	if target != "":
		state_machine.transition_to(target)
		return

	if slime.can_see_player() and slime.attack_cooldown <= 0:
		state_machine.transition_to("Retreat")
		return

	# 撞牆、前方是懸崖、或走完這次隨機挑的距離——都停下來掉頭
	if slime.wall_checker.is_colliding() or not slime.floor_checker.is_colliding() \
		or absf(slime.global_position.x - _start_x) >= _target_distance:
		state_machine.transition_to("Turn")
		return

	slime.consecutive_turns = 0 # 這一步真的走出去了，代表沒卡住，重置卡住計數
	slime.move(_current_speed, delta)
