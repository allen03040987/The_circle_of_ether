class_name NaiheSpike
extends Node2D

@onready var hitbox: Hitbox = $Hitbox

var direction: int = 1

func _ready() -> void:
	top_level = true
	hitbox.owner = self
	
	# 🌟 動態賦予絕對擊退方向！
	# 地刺通常會帶有向上的 y 軸擊退 (挑飛)，x 軸則順著地刺蔓延的方向
	var base_kb_x = abs(hitbox.knockback_force.x)
	hitbox.absolute_knockback = Vector2(base_kb_x * direction, hitbox.knockback_force.y)
	
	# 播放地刺破土而出的動畫
	if has_node("AnimationPlayer"):
		$AnimationPlayer.play("emerge")
		# 動畫播完後，地刺自動銷毀
		$AnimationPlayer.animation_finished.connect(func(_anim): queue_free())
	else:
		# 防呆：沒做動畫的話，1秒後自動銷毀
		get_tree().create_timer(1.0).timeout.connect(queue_free)
