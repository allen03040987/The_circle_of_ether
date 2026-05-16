class_name NaiheCannon
extends Node2D

@export var speed: float = 1200.0        # 手砲子彈速度極快
@export var max_distance: float = 600.0  # 射程遠

var direction: int = 1
var traveled_distance: float = 0.0

@onready var hitbox: Hitbox = $Hitbox

func _ready() -> void:
	top_level = true
	hitbox.owner = self
	
	# 給一個保底銷毀時間
	get_tree().create_timer(3.0).timeout.connect(queue_free)

func _physics_process(delta: float) -> void:
	var step = speed * delta
	global_position.x += direction * step
	traveled_distance += step
	
	if traveled_distance >= max_distance:
		_explode()

func _explode() -> void:
	# 這裡未來可以播放爆炸動畫，現在先直接銷毀
	hitbox.set_deferred("monitoring", false)
	hitbox.set_deferred("monitorable", false)
	queue_free()
