class_name BossIdleState
extends BossState

var idle_timer: float = 0.0

func enter() -> void:
	boss.play_safe_anim("idle")
	boss.velocity.x = 0.0 # 停下腳步
	# 每次發呆 1 ~ 2 秒
	idle_timer = randf_range(1.0, 2.0)

func physics_update(delta: float) -> void:
	# 處理重力與摩擦力
	boss.velocity.x = move_toward(boss.velocity.x, 0.0, boss.acceleration * delta)
	boss.velocity.y += boss.default_gravity * delta
	boss.custom_move_and_slide()
	
	# 待機時依然盯著玩家看
	boss.face_player()
	
	# 時間到了就開始追擊
	idle_timer -= (delta * boss.action_speed_mult)
	if idle_timer <= 0:
		state_machine.transition_to("Chase")
