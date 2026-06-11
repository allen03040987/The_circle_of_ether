extends Node2D

@onready var particles: CPUParticles2D = $CPUParticles2D
@onready var anim_player: AnimationPlayer = $AnimationPlayer 

func _ready() -> void:
	# 🌟 核心防護：讓整個特效節點及其子節點完全無視 Engine.time_scale！
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	particles.emitting = false 
	rotation_degrees = randf_range(0, 360) # 如果是 slash 記得改回 -15 到 15
	
	# ⚠️ 這裡記得換成對應的動畫名稱 "slash" 或 "impact"
	if anim_player.has_animation("impact"):
		anim_player.play("impact")
		anim_player.animation_finished.connect(func(_anim_name):
			queue_free()
		)
	else:
		# 🌟 核心修復：使用 SceneTreeTimer 時，第 4 個參數必須設為 true (ignore_time_scale)
		get_tree().create_timer(1.0, true, false, true).timeout.connect(queue_free)

func trigger_particles() -> void:
	particles.emitting = true

