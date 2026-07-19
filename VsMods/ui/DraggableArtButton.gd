extends Button
class_name DraggableArtButton
## 武藝池按鈕——可拖曳版本。裝備槽（ArtSlotButton）接住拖曳放開的動作。
## 純 UI 互動，不涉及 rollback 模擬，不用管確定性。

var art_id: String = ""

func _get_drag_data(_at_position: Vector2) -> Variant:
	if art_id == "":
		return null
	var preview := Button.new()
	preview.text = text
	preview.size = size
	preview.add_theme_font_size_override("font_size", get_theme_font_size("font_size"))
	preview.modulate.a = 0.75
	set_drag_preview(preview)
	return {"art_id": art_id}
