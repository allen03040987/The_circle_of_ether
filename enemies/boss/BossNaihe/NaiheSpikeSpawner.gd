class_name NaiheSpikeSpawner
extends Node2D

const SPIKE_SCENE = preload("res://enemies/boss/BossNaihe/NaiheSpike.tscn")

@export var max_spikes: int = 5       
@export var spawn_interval: float = 0.25 
@export var spacing: float = 140.0    

var direction: int = 1

func _ready() -> void:
	top_level = true
	# 🚨 把這裡的 _spawn_sequence() 刪掉！什麼都別做，等 Boss 下令！

# 🌟 新增這個函數，讓 Boss 設定好位置後手動啟動！
func start_spawning(start_pos: Vector2, dir: int) -> void:
	global_position = start_pos
	direction = dir
	_spawn_sequence()

func _spawn_sequence() -> void:
	for i in range(max_spikes):
		_spawn_single_spike(i)
		
		# 絕對抗時停計時
		if CombatManager.has_method("get_skill_timer"):
			await CombatManager.get_skill_timer(spawn_interval).timeout
		else:
			await get_tree().create_timer(spawn_interval, false, false, true).timeout
			
	queue_free()

func _spawn_single_spike(index: int) -> void:
	if not SPIKE_SCENE: return
	var spike = SPIKE_SCENE.instantiate()
	get_tree().current_scene.add_child(spike)
	
	var offset_x = (index * spacing) * direction
	spike.global_position = global_position + Vector2(offset_x, 0)
	spike.direction = direction
