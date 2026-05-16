class_name BossState
extends State
## BOSS 專屬狀態基底

# 把原本的 player 換成 boss，這樣就有代碼提示了！
var boss: BossNaihe 

func _ready() -> void:
	# 覆寫初始化，確保抓到的是 Boss 本體
	await owner.ready
	boss = owner as BossNaihe
	state_machine = get_parent() as StateMachine
