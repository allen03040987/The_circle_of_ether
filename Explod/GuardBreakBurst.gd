extends Node2D
## 彈刀成功特效：噴出一圈黃色矩形碎片，播完自動銷毀

@onready var particles: CPUParticles2D = $CPUParticles2D

func _ready() -> void:
	particles.emitting = true
	get_tree().create_timer(particles.lifetime + 0.1, false, false, false).timeout.connect(queue_free)
