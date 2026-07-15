extends Control
## 武藝裝備選擇畫面（Clotty × Clotty）
## 全程式碼建立，不依賴複雜 tscn。
## P1 選上半區、P2 選下半區，各自點擊武藝按鈕裝備 / 解除。

const VIEW_W := 384
const VIEW_H := 216
const BTN_H  := 15
const GAP    := 4

const C_BG        := Color(0.07, 0.07, 0.07)
const C_AVAILABLE := Color(0.18, 0.18, 0.18)
const C_EQUIPPED  := Color(0.85, 0.85, 0.85)
const C_SLOT_EMPTY:= Color(0.12, 0.12, 0.12)
const C_SEPARATOR := Color(0.3, 0.3, 0.3)

var _p1_sel: Array = []   # 已選 art_id 串列（最多3）
var _p2_sel: Array = []

# 按鈕節點暫存
var _p1_art_btns:  Array = []   # 6 個 Button
var _p2_art_btns:  Array = []
var _p1_slot_btns: Array = []   # 3 個 Button（槽位顯示）
var _p2_slot_btns: Array = []

func _ready() -> void:
	_p1_sel = []
	_p2_sel = []
	_build_ui()

# ── 建立 UI ───────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	# 背景
	var bg := ColorRect.new()
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.color = C_BG
	add_child(bg)

	var arts := VsGameManager.CLOTTY_ARTS

	# ── P1 區（上半）─────────────────────────────────────
	var y := GAP
	_section_label("P1 PLAYER", y)
	y += 12

	_p1_art_btns = _art_row_pair(arts, y, 1)
	y += BTN_H * 2 + GAP * 3

	_section_label("裝備：", y)
	y += 12
	_p1_slot_btns = _slot_row(y, 1)
	y += BTN_H + GAP

	_hint_label("（空槽位：能量回復 +%.0f/s）" % VsGameManager.EMPTY_SLOT_REGEN_BONUS, y)
	y += 12

	# 分隔線
	_separator(y)
	y += GAP + 2

	# ── P2 區（下半）─────────────────────────────────────
	_section_label("P2 PLAYER", y)
	y += 12

	_p2_art_btns = _art_row_pair(arts, y, 2)
	y += BTN_H * 2 + GAP * 3

	_section_label("裝備：", y)
	y += 12
	_p2_slot_btns = _slot_row(y, 2)
	y += BTN_H + GAP

	_hint_label("（空槽位：能量回復 +%.0f/s）" % VsGameManager.EMPTY_SLOT_REGEN_BONUS, y)
	y += 14

	# 底部按鈕列
	_separator(y)
	y += GAP + 2
	var back_btn := Button.new()
	back_btn.text     = "← 返回"
	back_btn.position = Vector2(GAP, y)
	back_btn.size     = Vector2(60, BTN_H + 2)
	back_btn.add_theme_font_size_override("font_size", 9)
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://VsMods/ui/LobbyScreen.tscn"))
	add_child(back_btn)

	var start_btn := Button.new()
	start_btn.text     = "開始對戰"
	start_btn.position = Vector2((VIEW_W - 160) / 2, y)
	start_btn.size     = Vector2(160, BTN_H + 2)
	start_btn.add_theme_font_size_override("font_size", 11)
	start_btn.pressed.connect(_on_start)
	add_child(start_btn)

	_refresh_all()

# ── 武藝按鈕 兩行（3+3）────────────────────────────────────────────────────────
func _art_row_pair(arts: Array, y: int, pid: int) -> Array:
	var btns := []
	var bw   := (VIEW_W - GAP * 4) / 3
	for i in 6:
		var col := i % 3
		var row := i / 3
		var bx  := GAP + col * (bw + GAP)
		var by  := y + row * (BTN_H + GAP)
		var btn := Button.new()
		btn.text     = VsGameManager.get_display_name(arts[i])
		btn.position = Vector2(bx, by)
		btn.size     = Vector2(bw, BTN_H)
		btn.add_theme_font_size_override("font_size", 9)
		var art_id: String = arts[i]   # capture
		btn.pressed.connect(func(): _on_art_clicked(pid, art_id))
		add_child(btn)
		btns.append(btn)
	return btns

# ── 槽位行（3 格）──────────────────────────────────────────────────────────────
func _slot_row(y: int, pid: int) -> Array:
	var btns := []
	var bw   := (VIEW_W - GAP * 4) / 3
	for i in 3:
		var bx  := GAP + i * (bw + GAP)
		var btn := Button.new()
		btn.position = Vector2(bx, y)
		btn.size     = Vector2(bw, BTN_H)
		btn.add_theme_font_size_override("font_size", 9)
		var slot_idx := i   # capture
		btn.pressed.connect(func(): _on_slot_clicked(pid, slot_idx))
		add_child(btn)
		btns.append(btn)
	return btns

# ── 點擊邏輯 ──────────────────────────────────────────────────────────────────
func _on_art_clicked(pid: int, art_id: String) -> void:
	var sel: Array = _p1_sel if pid == 1 else _p2_sel
	if art_id in sel:
		sel.erase(art_id)
	elif sel.size() < 3:
		sel.append(art_id)
	_refresh(pid)

func _on_slot_clicked(pid: int, slot_idx: int) -> void:
	var sel: Array = _p1_sel if pid == 1 else _p2_sel
	if slot_idx < sel.size():
		sel.remove_at(slot_idx)
	_refresh(pid)

func _on_start() -> void:
	# 將選擇補滿 3 格（空字串 = 空槽）
	VsGameManager.p1_arts = _pad_slots(_p1_sel)
	VsGameManager.p2_arts = _pad_slots(_p2_sel)
	VsGameManager.selection_confirmed = true
	get_tree().change_scene_to_file("res://VsMods/vs_world.tscn")

func _pad_slots(sel: Array) -> Array:
	var out := sel.duplicate()
	while out.size() < 3:
		out.append("")
	return out

# ── 刷新顯示 ──────────────────────────────────────────────────────────────────
func _refresh_all() -> void:
	_refresh(1)
	_refresh(2)

func _refresh(pid: int) -> void:
	var sel:       Array = _p1_sel       if pid == 1 else _p2_sel
	var art_btns:  Array = _p1_art_btns  if pid == 1 else _p2_art_btns
	var slot_btns: Array = _p1_slot_btns if pid == 1 else _p2_slot_btns
	var arts := VsGameManager.CLOTTY_ARTS

	for i in 6:
		var equipped: bool = (arts[i] as String) in sel
		_set_btn_style(art_btns[i], equipped)

	for i in 3:
		if i < sel.size():
			slot_btns[i].text = VsGameManager.get_display_name(sel[i])
			_set_btn_style(slot_btns[i], true)
		else:
			slot_btns[i].text = "（空）"
			_set_btn_style(slot_btns[i], false)

func _set_btn_style(btn: Button, active: bool) -> void:
	var col := C_EQUIPPED if active else C_AVAILABLE
	var style := StyleBoxFlat.new()
	style.bg_color = col
	btn.add_theme_stylebox_override("normal",   style)
	btn.add_theme_stylebox_override("hover",    style)
	btn.add_theme_stylebox_override("pressed",  style)
	btn.add_theme_color_override("font_color",
		Color(0.08, 0.08, 0.08) if active else Color(0.8, 0.8, 0.8))

# ── 輔助 ──────────────────────────────────────────────────────────────────────
func _section_label(text: String, y: int) -> void:
	var lbl := Label.new()
	lbl.text     = text
	lbl.position = Vector2(GAP, y)
	lbl.add_theme_font_size_override("font_size", 9)
	add_child(lbl)

func _hint_label(text: String, y: int) -> void:
	var lbl := Label.new()
	lbl.text       = text
	lbl.position   = Vector2(0, y)
	lbl.size       = Vector2(VIEW_W, 12)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.modulate   = Color(0.6, 0.6, 0.6)
	add_child(lbl)

func _separator(y: int) -> void:
	var line := ColorRect.new()
	line.position = Vector2(0, y)
	line.size     = Vector2(VIEW_W, 1)
	line.color    = C_SEPARATOR
	add_child(line)
