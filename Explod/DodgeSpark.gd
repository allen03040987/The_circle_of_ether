extends Node2D

@onready var particles: CPUParticles2D = $CPUParticles2D

func _ready() -> void:
	# 確保一出生就開噴
	particles.emitting = true
	
	# 自動銷毀機制：取得粒子的生命週期，加上一點緩衝時間後刪除自己
	var lifetime = particles.lifetime
	get_tree().create_timer(lifetime + 0.1).timeout.connect(queue_free)
