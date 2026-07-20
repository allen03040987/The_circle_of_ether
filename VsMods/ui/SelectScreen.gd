extends Control
## 武藝裝備選擇畫面。
## 固定元素（標題/分隔線/裝備欄標籤/3 個裝備槽按鈕/返回開始按鈕）都是
## SelectScreen.tscn 裡真正的節點，可以直接在編輯器裡拖動排版；角色列跟武藝格
## 數量會隨角色/武藝池變動，維持程式碼在執行期動態生成，塞進場景裡對應的
## CharacterAnchor/ArtAnchor 這兩個「定位錨點」節點（錨點本身的 position/size
## 在編輯器可調，決定動態按鈕要生成在哪個範圍）。
##
## 離線模式：P1（PanelA）左半、P2（PanelB）右半，左右並排同時選。
## 線上模式：只顯示本機玩家那一半（PanelA 或 PanelB，看本機是 P1 還是 P2），
## 該半版面重新排版成全寬單欄。
##
## 裝備互動（2026-07-19 改版）：點選一個裝備槽（白色線框標示）→ 再點武藝池
## 中任一招即可裝備上去；或直接把武藝池按鈕拖曳放到裝備槽上（不用先選取）。
## 點空白處取消槽位選取。武藝跟槽位不是靠精準像素位置互動（原本「點武藝直接
## 塞進第一個空槽」的設計，使用者反映跟編輯器排版微調搭配時容易分不清楚點在
## 哪裡才有效），槽位選取狀態明確可見，比對齊像素更不容易出錯。

const VIEW_W := 384
const BTN_H  := 15
const GAP    := 4
## 離線模式左右欄寬度（兩欄之間留一道 GAP 寬的分隔溝）
const COL_W  := (VIEW_W - GAP * 3) / 2

const C_AVAILABLE     := Color(0.18, 0.18, 0.18)
const C_EQUIPPED      := Color(0.85, 0.85, 0.85)
const C_SELECTED_BORDER := Color(1.0, 1.0, 1.0)

var _p1_sel: Array = ["", "", ""]   # 固定 3 格，直接對應槽位索引（不是不定長清單）
var _p2_sel: Array = ["", "", ""]

var _p1_character: String = VsCharacterRegistry.DEFAULT_CHARACTER
var _p2_character: String = VsCharacterRegistry.DEFAULT_CHARACTER

var _p1_selected_slot: int = -1   # -1 = 沒有選取任何槽位
var _p2_selected_slot: int = -1

var _p1_art_btns:  Array = []
var _p2_art_btns:  Array = []
var _p1_char_btns: Array = []
var _p2_char_btns: Array = []

## 每個面板底下固定子節點的參照，_panel_refs() 在 _ready() 蒐集一次
var _p1_refs: Dictionary = {}
var _p2_refs: Dictionary = {}

var _status_label:      Label
var _is_online:         bool = false
var _local_pid:         int  = 1
var _local_confirmed:   bool = false   # 本機已按確認
var _remote_arts_ready: bool = false   # 已收到對方武藝
var _received_arts:     Array  = []
var _received_character: String = VsCharacterRegistry.DEFAULT_CHARACTER

func _ready() -> void:
	_is_online   = VsNetworkManager.mode != VsNetworkManager.Mode.OFFLINE
	_local_pid   = VsNetworkManager.local_player_id
	_status_label = $StatusLabel
	_p1_refs = _panel_refs($PanelA)
	_p2_refs = _panel_refs($PanelB)
	_connect_slots(_p1_refs, 1)
	_connect_slots(_p2_refs, 2)
	_build_ui()
	if _is_online:
		VsNetworkManager.remote_arts_received.connect(_on_remote_arts)

## 蒐集面板底下的固定子節點，供排版/填色/文字更新統一存取
func _panel_refs(panel: Control) -> Dictionary:
	return {
		"section_label":    panel.get_node("SectionLabel") as Label,
		"character_anchor": panel.get_node("CharacterAnchor") as Control,
		"art_anchor":       panel.get_node("ArtAnchor") as Control,
		"slot_row":         panel.get_node("SlotRow") as Control,
		"slots": [
			panel.get_node("SlotRow/Slot0") as ArtSlotButton,
			panel.get_node("SlotRow/Slot1") as ArtSlotButton,
			panel.get_node("SlotRow/Slot2") as ArtSlotButton,
		],
		"hint": panel.get_node("Hint") as Label,
	}

## 裝備槽是場景裡的固定節點（不像武藝池按鈕是動態生成的），點擊/拖放的訊號
## 只需要接一次，不用每次重建。
func _connect_slots(refs: Dictionary, pid: int) -> void:
	var slots: Array = refs["slots"]
	for i in 3:
		var slot_idx := i
		var btn: ArtSlotButton = slots[i]
		btn.pressed.connect(func(): _on_slot_clicked(pid, slot_idx))
		btn.art_dropped.connect(func(art_id: String): _equip(pid, slot_idx, art_id))

# ── 建立 UI ───────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	if _is_online:
		# 線上模式：只顯示本機玩家那一半，該半改成全寬單欄
		var local_is_p1 := _local_pid == 1
		$VSeparator.visible = false
		$PanelA.visible = local_is_p1
		$PanelB.visible = not local_is_p1
		var panel: Control = $PanelA if local_is_p1 else $PanelB
		var refs:  Dictionary = _p1_refs if local_is_p1 else _p2_refs
		_layout_panel(panel, refs, 0.0, VIEW_W)
		refs["section_label"].text = "P%d（你）" % _local_pid
		refs["hint"].text = "（空槽位：生命/衝刺回復/移速 +%.0f%%）" % (VsGameManager.EMPTY_SLOT_STAT_BONUS_PCT * 100.0)
		var character := VsGameManager.p1_character if local_is_p1 else VsGameManager.p2_character
		_populate_character_row(refs, _local_pid)
		_populate_art_grid(refs, _local_pid, VsCharacterRegistry.get_arts(character))
		$StartButton.text = "確認選擇"
	else:
		# 離線模式：P1 左欄、P2 右欄，並排同時選
		$VSeparator.visible = true
		$PanelA.visible = true
		$PanelB.visible = true
		_layout_panel($PanelA, _p1_refs, 0.0, COL_W)
		_layout_panel($PanelB, _p2_refs, COL_W + GAP * 2, COL_W)
		_p1_refs["section_label"].text = "P1 PLAYER"
		_p2_refs["section_label"].text = "P2 PLAYER"
		var hint_text := "（空槽位：生命/衝刺回復/移速 +%.0f%%）" % (VsGameManager.EMPTY_SLOT_STAT_BONUS_PCT * 100.0)
		_p1_refs["hint"].text = hint_text
		_p2_refs["hint"].text = hint_text
		_populate_character_row(_p1_refs, 1)
		_populate_character_row(_p2_refs, 2)
		_populate_art_grid(_p1_refs, 1, VsCharacterRegistry.get_arts(_p1_character))
		_populate_art_grid(_p2_refs, 2, VsCharacterRegistry.get_arts(_p2_character))
		$StartButton.text = "開始對戰"

	_refresh_all()

## 把面板本身跟底下會隨寬度變化的錨點/欄位一起重新定位——線上模式全寬單欄、
## 離線模式左右各半欄共用同一份排版邏輯，只有 x/width 不同。
func _layout_panel(panel: Control, refs: Dictionary, x: float, width: float) -> void:
	panel.position.x = x
	panel.size.x     = width
	(refs["character_anchor"] as Control).size.x = width
	(refs["art_anchor"] as Control).size.x       = width
	(refs["slot_row"] as Control).size.x         = width
	(refs["hint"] as Label).size.x               = width
	(refs["section_label"] as Label).size.x      = width - GAP

	var bw := (width - GAP * 4) / 3
	var slots: Array = refs["slots"]
	for i in 3:
		var btn: Button = slots[i]
		btn.position.x = GAP + i * (bw + GAP)
		btn.size.x     = bw

# ── 武藝按鈕（動態，塞進 ArtAnchor）─────────────────────────────────────────────
func _populate_art_grid(refs: Dictionary, pid: int, arts: Array) -> void:
	var anchor: Control = refs["art_anchor"]
	for c in anchor.get_children():
		c.queue_free()
	var width := anchor.size.x
	var bw    := (width - GAP * 4) / 3
	var btns  := []
	for i in arts.size():
		var col := i % 3
		var row := i / 3
		var btn := DraggableArtButton.new()
		btn.text   = VsGameManager.get_display_name(arts[i])
		btn.art_id = arts[i]
		btn.add_theme_font_size_override("font_size", 9)
		var art_id: String = arts[i]
		btn.pressed.connect(func(): _on_art_clicked(pid, art_id))
		# ⚠ 字體覆寫必須在 add_child()（真正進場景樹）之前設定、且晚於 .size
		# 賦值前生效——字體覆寫決定 Button 的最小尺寸計算，如果先設 .size 才設
		# 字體，Button 進場景樹當下還在用專案全域主題的預設字級（PixelTheme.tres
		# 的 Button/font_sizes/font_size=14，比這裡要的 9 大上不少）算出一個較大
		# 的最小尺寸，把我剛設定的小 size 蓋掉；且事後字體覆寫生效也不會回頭
		# 縮小已經定案的尺寸。實測抓到：兩排按鈕實際渲染大小一致（58×25），
		# 但因為原本用 15px 排版間距算兩排位置，25px 高的按鈕會讓第二排往上
		# 疊到第一排，看起來像「上排矮、下排高」。改成字體覆寫→進場景樹→最後
		# 才設 position/size，讓小字體先定案，size 賦值才不會被蓋掉。
		anchor.add_child(btn)
		btn.position = Vector2(GAP + col * (bw + GAP), row * (BTN_H + GAP))
		btn.size     = Vector2(bw, BTN_H)
		btns.append(btn)
	if pid == 1: _p1_art_btns = btns
	else:        _p2_art_btns = btns

## 換角色時整列砍掉重建——按鈕的 closure 在建立當下就把 art_id 捕捉死，
## 換角色後武藝池整個不同，不能只改文字，必須整列重來。
func _rebuild_art_row(pid: int) -> void:
	var refs: Dictionary = _p1_refs if pid == 1 else _p2_refs
	var character: String = _p1_character if pid == 1 else _p2_character
	_populate_art_grid(refs, pid, VsCharacterRegistry.get_arts(character))

# ── 選角色按鈕列（動態，塞進 CharacterAnchor）───────────────────────────────────
func _populate_character_row(refs: Dictionary, pid: int) -> void:
	var anchor: Control = refs["character_anchor"]
	for c in anchor.get_children():
		c.queue_free()
	var ids   := VsCharacterRegistry.all_ids()
	var width := anchor.size.x
	var bw    := (width - GAP * (ids.size() + 1)) / maxi(ids.size(), 1)
	var btns  := []
	for i in ids.size():
		var char_id: String = ids[i]
		var btn := Button.new()
		btn.text = VsCharacterRegistry.get_display_name(char_id)
		btn.add_theme_font_size_override("font_size", 8)
		btn.pressed.connect(func(): _on_character_clicked(pid, char_id))
		anchor.add_child(btn)   # 字體覆寫要先於 add_child()，理由見 _populate_art_grid()
		btn.position = Vector2(GAP + i * (bw + GAP), 0)
		btn.size     = Vector2(bw, 12)
		btns.append(btn)
	if pid == 1: _p1_char_btns = btns
	else:        _p2_char_btns = btns

func _on_character_clicked(pid: int, char_id: String) -> void:
	if pid == 1:
		if _p1_character == char_id:
			return
		_p1_character = char_id
		_p1_sel = ["", "", ""]   # 換角色後原本裝備的武藝對新角色沒意義
		_p1_selected_slot = -1
	else:
		if _p2_character == char_id:
			return
		_p2_character = char_id
		_p2_sel = ["", "", ""]
		_p2_selected_slot = -1
	_rebuild_art_row(pid)
	_refresh(pid)

# ── 點擊/拖放邏輯 ─────────────────────────────────────────────────────────────
## 點選裝備槽：再點一次同一格取消選取；點別格則切換選取到那格。
func _on_slot_clicked(pid: int, slot_idx: int) -> void:
	var cur := _p1_selected_slot if pid == 1 else _p2_selected_slot
	var next := -1 if cur == slot_idx else slot_idx
	if pid == 1: _p1_selected_slot = next
	else:        _p2_selected_slot = next
	_refresh(pid)

## 點武藝池按鈕：
## - 這招已經裝備中 → 直接卸下（不管有沒有選取槽位）
## - 這招還沒裝備 → 只有在「已經選取某個裝備槽」時才有作用，裝進那一格；
##   沒選槽位時點擊不做事，讓使用者建立「選槽位→選武藝」的兩步驟心智模型
func _on_art_clicked(pid: int, art_id: String) -> void:
	var sel: Array = _p1_sel if pid == 1 else _p2_sel
	if art_id in sel:
		_unequip(pid, sel.find(art_id))
		return
	var slot_idx := _p1_selected_slot if pid == 1 else _p2_selected_slot
	if slot_idx == -1:
		return
	_equip(pid, slot_idx, art_id)

## 裝備武藝到指定槽位（點擊或拖放都會走到這裡）。同一招若已經裝在別的槽位，
## 先移除避免同時裝備兩份相同武藝。
func _equip(pid: int, slot_idx: int, art_id: String) -> void:
	var sel: Array = _p1_sel if pid == 1 else _p2_sel
	for i in 3:
		if sel[i] == art_id:
			sel[i] = ""
	sel[slot_idx] = art_id
	_refresh(pid)

func _unequip(pid: int, slot_idx: int) -> void:
	var sel: Array = _p1_sel if pid == 1 else _p2_sel
	sel[slot_idx] = ""
	_refresh(pid)

## 點擊背景（沒點中任何按鈕）取消槽位選取——Button 會自己吃掉點擊事件，
## 沒被任何按鈕吃掉的點擊才會落到這裡。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _p1_selected_slot != -1 or _p2_selected_slot != -1:
			_p1_selected_slot = -1
			_p2_selected_slot = -1
			_refresh_all()

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://VsMods/ui/LobbyScreen.tscn")

func _on_start() -> void:
	if _is_online:
		var my_arts: Array      = (_p1_sel if _local_pid == 1 else _p2_sel).duplicate()
		var my_character: String = _p1_character if _local_pid == 1 else _p2_character
		if _local_pid == 1:
			VsGameManager.p1_arts      = my_arts
			VsGameManager.p1_character = my_character
		else:
			VsGameManager.p2_arts      = my_arts
			VsGameManager.p2_character = my_character
		VsNetworkManager.send_arts(my_arts, my_character)
		_local_confirmed = true
		_status_label.text = "等待對方確認..."
		_try_enter_game()
	else:
		VsGameManager.p1_arts      = _p1_sel.duplicate()
		VsGameManager.p2_arts      = _p2_sel.duplicate()
		VsGameManager.p1_character = _p1_character
		VsGameManager.p2_character = _p2_character
		VsGameManager.selection_confirmed = true
		get_tree().change_scene_to_file("res://VsMods/vs_world.tscn")

func _on_remote_arts(arts: Array, character_id: String) -> void:
	_received_arts      = arts
	_received_character = character_id
	_remote_arts_ready   = true
	_try_enter_game()

func _try_enter_game() -> void:
	if not (_local_confirmed and _remote_arts_ready):
		return
	# 雙方都確認了，把對方武藝＋角色存好並進遊戲
	if _local_pid == 1:
		VsGameManager.p2_arts      = _received_arts
		VsGameManager.p2_character = _received_character
	else:
		VsGameManager.p1_arts      = _received_arts
		VsGameManager.p1_character = _received_character
	VsGameManager.selection_confirmed = true
	get_tree().change_scene_to_file("res://VsMods/vs_world.tscn")

# ── 刷新顯示 ──────────────────────────────────────────────────────────────────
func _refresh_all() -> void:
	_refresh(1)
	_refresh(2)

func _refresh(pid: int) -> void:
	var sel:          Array = _p1_sel       if pid == 1 else _p2_sel
	var art_btns:     Array = _p1_art_btns  if pid == 1 else _p2_art_btns
	var char_btns:    Array = _p1_char_btns if pid == 1 else _p2_char_btns
	var refs:         Dictionary = _p1_refs if pid == 1 else _p2_refs
	var selected_slot: int = _p1_selected_slot if pid == 1 else _p2_selected_slot
	var character: String = _p1_character if pid == 1 else _p2_character
	var ids := VsCharacterRegistry.all_ids()
	for i in char_btns.size():
		_set_btn_style(char_btns[i], (ids[i] as String) == character, false)
	if not art_btns.is_empty():
		var arts := VsCharacterRegistry.get_arts(character)
		for i in art_btns.size():
			var equipped: bool = (arts[i] as String) in sel
			_set_btn_style(art_btns[i], equipped, false)
	var slots: Array = refs["slots"]
	for i in 3:
		slots[i].text = VsGameManager.get_display_name(sel[i]) if sel[i] != "" else "（空）"
		_set_btn_style(slots[i], sel[i] != "", i == selected_slot)

func _set_btn_style(btn: Button, active: bool, selected: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = C_EQUIPPED if active else C_AVAILABLE
	if selected:
		style.border_width_left   = 2
		style.border_width_top    = 2
		style.border_width_right  = 2
		style.border_width_bottom = 2
		style.border_color = C_SELECTED_BORDER
	btn.add_theme_stylebox_override("normal",  style)
	btn.add_theme_stylebox_override("hover",   style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_color_override("font_color",
		Color(0.08, 0.08, 0.08) if active else Color(0.8, 0.8, 0.8))
