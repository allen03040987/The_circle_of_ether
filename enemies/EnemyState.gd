class_name EnemyState
extends State
## 敵人專屬狀態基底：跟 enemies/boss/BossState.gd 同一個模式，只是型別換成通用的 Enemy——
## 讓 Slime 之類非 Boss 的敵人也能用同一套 node-based StateMachine，不用各自重新發明。

var enemy: Enemy

func _ready() -> void:
	await owner.ready
	enemy = owner as Enemy
	state_machine = get_parent() as StateMachine
