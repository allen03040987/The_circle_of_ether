extends Button
class_name ArtSlotButton
## 裝備槽按鈕——接受 DraggableArtButton 拖放；點擊選取的邏輯（白色線框標示）
## 由外層腳本（SelectScreen.gd/ArtsReselectOverlay.gd）處理，這裡只負責
## Godot 原生拖放 API 需要的兩個虛函式。

signal art_dropped(art_id: String)

func _can_drop_data(_at_position: Vector2, data) -> bool:
	return data is Dictionary and data.has("art_id")

func _drop_data(_at_position: Vector2, data) -> void:
	art_dropped.emit(data["art_id"])
