class_name Item
extends Node
## 消耗道具基底契約 (Consumable Item Base Contract)
## 玩家身上帶的消耗品都繼承這個——沿用武藝卡帶 (MartialArt.gd) 那套「基底契約 + 子類覆寫」的做法。

var player: Node

@export var item_name: String = "未知道具"
@export var icon: Texture2D
@export var max_charges: int = 3
@export var refill_on_save_stone: bool = true ## 存檔點是否會幫這個道具補滿——沿用 save_stone.gd 原本就會回滿血量/能量的邏輯

var current_charges: int = 0

func setup(p: Node) -> void:
	player = p
	current_charges = max_charges

## 使用道具，回傳是否成功消耗（給輸入層判斷要不要顯示「沒有道具」的警示）
func use() -> bool:
	return false

func refill() -> void:
	current_charges = max_charges
