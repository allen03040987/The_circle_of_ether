class_name VsArtButton
extends DraggableArtButton
## 武藝池格子的可重用樣板（VsArtButton.tscn）：名稱文字（NameLabel）跟右上角
## 「!」詳情按鈕（InfoButton）都是場景裡的真實節點，可以直接在編輯器裡拖動
## 調整位置/大小/樣式——兩者都用錨點定位（不是寫死像素），執行期即使按鈕被
## 縮放成別的寬高（每欄寬度依畫面排版動態計算，不同離線/線上版面會不一樣），
## 子節點還是會跟著等比例貼齊，不用另外處理。
##
## 按鈕本體的 .text 留空，名稱一律顯示在 NameLabel——DraggableArtButton 原本
## 用 .text 當拖曳預覽文字來源，這裡覆寫 _get_drag_data() 改讀 NameLabel.text。

signal info_requested(art_id: String)

@onready var name_label:  Label  = $NameLabel
@onready var info_button: Button = $InfoButton

func _ready() -> void:
	info_button.focus_mode = Control.FOCUS_NONE
	info_button.pressed.connect(func(): info_requested.emit(art_id))

func setup(new_art_id: String, display_name: String) -> void:
	art_id = new_art_id
	name_label.text = display_name

## 裝備中/選取中的變色效果呼叫這個，而不是直接對按鈕本體
## add_theme_color_override("font_color", ...)——名稱文字現在是獨立的
## NameLabel，按鈕本體沒有文字可以變色。
func set_name_color(color: Color) -> void:
	name_label.add_theme_color_override("font_color", color)

func _get_drag_data(_at_position: Vector2) -> Variant:
	if art_id == "":
		return null
	var preview := Button.new()
	preview.text = name_label.text
	preview.size = size
	preview.add_theme_font_size_override("font_size", name_label.get_theme_font_size("font_size"))
	preview.modulate.a = 0.75
	set_drag_preview(preview)
	return {"art_id": art_id}
