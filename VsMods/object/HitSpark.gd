extends Node2D

@onready var animation_player: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	# 一出生就自動播放動畫
	animation_player.play("default")

	# 等待動畫播放完畢的信號，然後自我毀滅！
	await animation_player.animation_finished
	queue_free()
