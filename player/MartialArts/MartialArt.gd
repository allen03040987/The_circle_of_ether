class_name MartialArt
extends Node
## 武藝基底組件 (Martial Art Base Component)

@export var art_id: String = "base_art"
@export var art_name: String = "未命名武藝"
@export var icon: Texture2D
@export var energy_cost: float = 10.0 # 🔋 預留未來的能量限制

var player: CharacterBody2D
var weapon: Node 
var is_active: bool = false

func setup(_player: CharacterBody2D, _weapon: Node) -> void:
	player = _player
	weapon = _weapon

# 🌟 拔除原本的 _process 與冷卻判斷
func enter() -> void:
	is_active = true
	print("🥋 發動武藝：", art_name)

func get_current_velocity(_delta: float) -> Vector2:
	return player.velocity

func is_handling_gravity() -> bool:
	return false

func is_finished() -> bool:
	return not is_active

func cancel() -> void:
	is_active = false
