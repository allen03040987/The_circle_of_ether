extends Node2D

@onready var particles: CPUParticles2D = $CPUParticles2D
@onready var anim_player: AnimationPlayer = $AnimationPlayer 

func _ready() -> void:
	particles.emitting = false 
	rotation_degrees = randf_range(0, 360) # 如果是 slash 記得改回 -15 到 15
	
	# ⚠️ 這裡記得換成對應的動畫名稱 "slash" 或 "impact"
	if anim_player.has_animation("impact"):
		anim_player.play("impact")
		anim_player.animation_finished.connect(func(_anim_name):
			queue_free()
		)
	else:
		get_tree().create_timer(1.0).timeout.connect(queue_free)

func trigger_particles() -> void:
	particles.emitting = true

# ==========================================
# 🌟 終極抗時停裝甲：每一幀動態對抗世界時間
# ==========================================
func _process(_delta: float) -> void:
	# 即時抓取當下的時間流速，確保永遠不會錯過時停！
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	
	if anim_player: anim_player.speed_scale = speed_mult
	if particles: particles.speed_scale = speed_mult
