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
		get_tree().create_timer(1.0, false, false, false).timeout.connect(queue_free)
