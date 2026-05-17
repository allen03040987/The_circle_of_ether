extends Node2D

@onready var particles: CPUParticles2D = $CPUParticles2D
@onready var anim_player: AnimationPlayer = $AnimationPlayer 

func _ready() -> void:
	particles.emitting = false 
	rotation_degrees = randf_range(0, 360) # 如果是 slash 記得改回 -15 到 15
	
	# ⚠️ 這裡記得換成對應的動畫名稱 "slash" 或 "impact"
	if anim_player.has_animation("slash"):
		anim_player.play("slash")
		anim_player.animation_finished.connect(func(_anim_name):
			queue_free()
		)
	else:
		get_tree().create_timer(1.0).timeout.connect(queue_free)

func trigger_particles() -> void:
	particles.emitting = true

