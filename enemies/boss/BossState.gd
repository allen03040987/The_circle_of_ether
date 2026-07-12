class_name BossState
extends EnemyState
## BOSS 專屬狀態基底——繼承通用的 EnemyState，只是多開一個 boss 型別的便利參考給代碼提示用

# 把原本的 player 換成 boss，這樣就有代碼提示了！
var boss: BossNaihe

func _ready() -> void:
	super._ready()
	boss = owner as BossNaihe
