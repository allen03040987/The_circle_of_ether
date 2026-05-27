extends Node2D

func play_and_free(anim_name: String, time_scale: float = 1.0) -> void:
	if has_node("AnimationPlayer"):
		var anim = $AnimationPlayer
		anim.speed_scale = time_scale
		anim.play(anim_name)
		# 動畫播完自動銷毀自己，絕不留垃圾
		anim.animation_finished.connect(func(_name): queue_free())
	else:
		# 防呆：如果沒動畫，0.5秒後自動銷毀
		get_tree().create_timer(0.5).timeout.connect(queue_free)
