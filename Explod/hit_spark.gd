extends Node2D

@onready var particles: CPUParticles2D = $CPUParticles2D
@onready var anim_player: AnimationPlayer = $AnimationPlayer 

func _ready() -> void:
	particles.emitting = false

	if anim_player.has_animation("slash"):
		anim_player.play("slash")
		anim_player.animation_finished.connect(func(_anim_name):
			queue_free()
		)
	else:
		# 🌟 核心修復：拔除 ignore_time_scale 與 process_always 的特權！
		# Godot 4 預設就是 (1.0, true, false, false)，我們手動設為 false 讓它會被暫停
		get_tree().create_timer(1.0, false, false, false).timeout.connect(queue_free)
