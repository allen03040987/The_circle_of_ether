extends Node2D
## 敵人黃圈彈刀特效：複製改自 Aggregation ring，動畫剛好 1 秒、黃色調
## 跟一次性特效不同，這個要「持續顯示」，由呼叫端（Enemy.gd 的黃圈判定窗）決定何時呼叫 stop() 結束特效

@onready var particles: CPUParticles2D = $CPUParticles2D
@onready var anim_player: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	particles.emitting = true
	if anim_player.has_animation("pulse"):
		anim_player.play("pulse")

## 供呼叫端結束特效：淡出後自我銷毀
func stop() -> void:
	if anim_player.is_playing():
		anim_player.stop()
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.15).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(queue_free)
