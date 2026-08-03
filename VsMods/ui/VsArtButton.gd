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

## display_name 現在是局內徽章同款的單字（VsGameManager.get_art_badge_char()），
## 不是招式全名——2026-07-27 使用者要求選武藝時顯示的就是局內實際看到的那個
## 單字徽章，不是文字說明；字體也套用同一個 VsGameManager.get_badge_font()。
func setup(new_art_id: String, display_name: String) -> void:
	art_id = new_art_id
	name_label.text = display_name
	var font := VsGameManager.get_badge_font()
	if font:
		name_label.add_theme_font_override("font", font)
	# 單字徽章比原本的「武藝一」全名短很多，字級沿用 3 字詞的舊尺寸（9）看起來
	# 太小——比照局內徽章的字級（BattleHud.BADGE_SIZE=18 用 13），這裡框高
	# 15px 比較接近，用同一個數字視覺上還算合適。
	name_label.add_theme_font_size_override("font_size", 13)

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
