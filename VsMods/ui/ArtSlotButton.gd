extends Button
class_name ArtSlotButton
## 裝備槽按鈕——接受 DraggableArtButton 拖放；點擊選取的邏輯（白色線框標示）
## 由外層腳本（SelectScreen.gd/ArtsReselectOverlay.gd）處理，這裡只負責
## Godot 原生拖放 API 需要的兩個虛函式。

signal art_dropped(art_id: String)

## 顯示武藝單字徽章（2026-07-27，跟局內裝備武藝徽章同一套特殊字體，取代
## 原本的招式全名/「武藝N」文字）。art_id 是空字串（未裝備）時顯示「（空）」，
## 維持專案預設字體、不套用徽章字體——徽章字體是給單一漢字設計的，
## 「（空）」不是招式單字，套上去不好看。
func set_slot_display(art_id: String) -> void:
	if art_id == "":
		text = "（空）"
		remove_theme_font_override("font")
		# ⚠ 不能只 remove——PixelTheme 的 Button 預設字級是 14，比徽章單字的
		# 13 還大，移除覆蓋並不會變小，反而更大。要明確指定一個小字級。
		add_theme_font_size_override("font_size", 9)
		return
	text = VsGameManager.get_art_badge_char(art_id)
	var font := VsGameManager.get_badge_font()
	if font:
		add_theme_font_override("font", font)
	# 單字比「（空）」/原本的招式全名短很多，字級跟 VsArtButton.setup() 用
	# 同一個數字（13），跟局內徽章、武藝池按鈕視覺上維持一致大小。
	add_theme_font_size_override("font_size", 13)

func _can_drop_data(_at_position: Vector2, data) -> bool:
	return data is Dictionary and data.has("art_id")

func _drop_data(_at_position: Vector2, data) -> void:
	art_dropped.emit(data["art_id"])
