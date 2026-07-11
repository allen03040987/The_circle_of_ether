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

## 給 UI 播放「用成功了」的綠色殘影、「沒道具了」的紅色警示——所有道具共用同一套訊號，不用每個子類自己再接一次
signal used()
signal denied()

func setup(p: Node) -> void:
	player = p
	current_charges = max_charges

## 使用道具，回傳是否成功消耗（給輸入層判斷要不要顯示「沒有道具」的警示）。
## 子類別覆寫 _do_use()，不要直接覆寫這個——訊號要統一從這裡發送
func use() -> bool:
	var success = _do_use()
	if success: used.emit()
	else: denied.emit()
	return success

## 子類別的實際使用邏輯，回傳是否成功消耗
func _do_use() -> bool:
	return false

func refill() -> void:
	current_charges = max_charges
