class_name BossDormantState
extends BossState

func enter() -> void:
	# 播放一個待命的動畫，例如單膝跪地、背對玩家、或是單純的 idle
	if boss.animation_player.has_animation("idle"):
		boss.play_safe_anim("idle")
		
	boss.velocity = Vector2.ZERO

func physics_update(delta: float) -> void:
	# 睡覺時還是要吃重力，確保他會穩穩踩在地板上
	boss.velocity.y += boss.default_gravity * delta
	boss.move_and_slide()
	
	# 🌟 注意：我們這裡不呼叫 _make_decision，也不盯著玩家轉向
	# 他會完全靜止，直到有人叫醒他
