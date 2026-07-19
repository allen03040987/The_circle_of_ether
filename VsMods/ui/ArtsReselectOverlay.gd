extends CanvasLayer
class_name ArtsReselectOverlay
## 回合間重選武藝浮層（規則：每回合開打前雙方都能替換最多 2 種已裝備的武藝）。
## 固定元素（標題/說明/倒數/裝備槽/狀態列/確認鍵）都是 ArtsReselectOverlay.tscn
## 裡真正的節點；武藝格數量隨角色武藝池變動，維持程式碼動態生成，塞進 ArtAnchor
## 這個定位錨點——同一套模式比照 SelectScreen.gd。
##
## 裝備互動（2026-07-19 改版，跟 SelectScreen.gd 同一套）：點選一個裝備槽（白色
## 線框標示）→ 再點武藝池中任一招即可換上；或直接把武藝池按鈕拖曳放到裝備槽上
## （不用先選取）。點空白處取消槽位選取。
##
## 由 vs_world.gd 在進入 VsRoundManager.Phase.ARTS_RESELECT 時 instantiate、
## 呼叫 init() 注入 p1/p2/round_manager 參照，離開時交給 vs_world free 掉。

const GAP    := 4
const BTN_H  := 15
const COL_W  := (384 - GAP * 3) / 2

const C_AVAILABLE       := Color(0.18, 0.18, 0.18)
const C_EQUIPPED        := Color(0.85, 0.85, 0.85)
const C_SELECTED_BORDER := Color(1.0, 1.0, 1.0)

var p1: VsPlayer
var p2: VsPlayer
var round_manager: VsRoundManager

var _p1_original: Array = []   # 本回合開始前的原始裝備（3 格，超過 2 種變動時擋下）
var _p2_original: Array = []
var _p1_sel: Array = ["", "", ""]   # 固定 3 格，直接對應槽位索引
var _p2_sel: Array = ["", "", ""]
var _p1_art_btns: Array = []
var _p2_art_btns: Array = []

var _p1_selected_slot: int = -1   # -1 = 沒有選取任何槽位
var _p2_selected_slot: int = -1

var _p1_refs: Dictionary = {}
var _p2_refs: Dictionary = {}

@onready var _timer_label: Label = $TimerLabel

func _panel_refs(panel: Control) -> Dictionary:
	return {
		"pid_label":  panel.get_node("PidLabel") as Label,
		"art_anchor": panel.get_node("ArtAnchor") as Control,
		"slot_row":   panel.get_node("SlotRow") as Control,
		"slots": [
			panel.get_node("SlotRow/Slot0") as ArtSlotButton,
			panel.get_node("SlotRow/Slot1") as ArtSlotButton,
			panel.get_node("SlotRow/Slot2") as ArtSlotButton,
		],
		"status":      panel.get_node("StatusLabel") as Label,
		"confirm_btn": panel.get_node("ConfirmButton") as Button,
	}

func _connect_slots(refs: Dictionary, pid: int) -> void:
	var slots: Array = refs["slots"]
	for i in 3:
		var slot_idx := i
		var btn: ArtSlotButton = slots[i]
		btn.pressed.connect(func(): _on_slot_clicked(pid, slot_idx))
		btn.art_dropped.connect(func(art_id: String): _equip(pid, slot_idx, art_id))

## 由 vs_world 在 instantiate() 之後立刻呼叫
func init(_p1: VsPlayer, _p2: VsPlayer, rm: VsRoundManager) -> void:
	p1 = _p1
	p2 = _p2
	round_manager = rm
	_p1_refs = _panel_refs($PanelA)
	_p2_refs = _panel_refs($PanelB)
	_connect_slots(_p1_refs, 1)
	_connect_slots(_p2_refs, 2)
	_build_ui()

func _process(_delta: float) -> void:
	if not round_manager:
		return
	_timer_label.text = "%d 秒後自動進入下一回合" % ceili(round_manager.arts_reselect_time_left())
	# 確認鍵的顯示狀態直接反映 round_manager.p{1,2}_confirmed（走輸入延遲＋
	# rollback 管線的確定性值，見 VsRoundManager._tick_arts_reselect() 註解），
	# 不是點擊當下就樂觀更新——點擊到這裡顯示變化之間會有約一個輸入延遲的
	# 些微落差（~67ms），但保證兩端最終顯示一致，不會有本機以為已確認、
	# 實際模擬還沒跟上的誤導畫面。
	if $PanelA.visible:
		_update_confirm_button(_p1_refs, round_manager.p1_confirmed)
	if $PanelB.visible:
		_update_confirm_button(_p2_refs, round_manager.p2_confirmed)

func _update_confirm_button(refs: Dictionary, confirmed: bool) -> void:
	var btn: Button = refs["confirm_btn"]
	btn.disabled = confirmed
	btn.text = "已確認，等待對方..." if confirmed else "確認"

# ── 建立 UI ───────────────────────────────────────────────────────────────────
## 「原始裝備」讀 VsPlayer.art_slots（活的、隨 reload_arts() 更新的當下裝備），
## 不能讀 VsGameManager.p1_arts/p2_arts——那份只在賽前 SelectScreen 寫一次，
## 中途重選不會更新它，拿來當「這回合開始前的裝備」基準會是舊資料。
func _build_ui() -> void:
	_p1_original = p1.art_slots.duplicate()
	_p2_original = p2.art_slots.duplicate()
	_p1_sel = _p1_original.duplicate()
	_p2_sel = _p2_original.duplicate()

	var is_online := VsNetworkManager.mode != VsNetworkManager.Mode.OFFLINE
	if is_online:
		# 線上模式：只顯示本機玩家那一半，該半改成全寬單欄
		var local_is_p1 := VsNetworkManager.local_player_id == 1
		$PanelA.visible = local_is_p1
		$PanelB.visible = not local_is_p1
		var panel: Control = $PanelA if local_is_p1 else $PanelB
		var refs:  Dictionary = _p1_refs if local_is_p1 else _p2_refs
		_layout_panel(panel, refs, 0.0, 384.0)
		refs["pid_label"].text = "P%d（你）" % VsNetworkManager.local_player_id
		var pid := 1 if local_is_p1 else 2
		var character := VsGameManager.p1_character if local_is_p1 else VsGameManager.p2_character
		_populate_art_grid(refs, pid, VsCharacterRegistry.get_arts(character))
	else:
		$PanelA.visible = true
		$PanelB.visible = true
		_layout_panel($PanelA, _p1_refs, 0.0, COL_W)
		_layout_panel($PanelB, _p2_refs, COL_W + GAP * 2, COL_W)
		_p1_refs["pid_label"].text = "P1"
		_p2_refs["pid_label"].text = "P2"
		_populate_art_grid(_p1_refs, 1, VsCharacterRegistry.get_arts(VsGameManager.p1_character))
		_populate_art_grid(_p2_refs, 2, VsCharacterRegistry.get_arts(VsGameManager.p2_character))

	_refresh_all()

func _layout_panel(panel: Control, refs: Dictionary, x: float, width: float) -> void:
	panel.position.x = x
	panel.size.x     = width
	(refs["art_anchor"] as Control).size.x  = width
	(refs["slot_row"] as Control).size.x    = width
	(refs["pid_label"] as Label).size.x     = width - GAP
	(refs["confirm_btn"] as Button).size.x  = width - GAP * 2

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
		anchor.add_child(btn)   # 字體覆寫要先於 add_child()，見 SelectScreen.gd 同款註解
		btn.position = Vector2(GAP + col * (bw + GAP), row * (BTN_H + GAP))
		btn.size     = Vector2(bw, BTN_H)
		btns.append(btn)
	if pid == 1: _p1_art_btns = btns
	else:        _p2_art_btns = btns

## 已替換數：跟原裝備逐格比對（槽位有明確身分，直接位置比對，不是集合比對）。
func _changed_count(pid: int) -> int:
	var sel:      Array = _p1_sel      if pid == 1 else _p2_sel
	var original: Array = _p1_original if pid == 1 else _p2_original
	var changed := 0
	for i in 3:
		if sel[i] != original[i]:
			changed += 1
	return changed

## 點選裝備槽：再點一次同一格取消選取；點別格則切換選取到那格。
func _on_slot_clicked(pid: int, slot_idx: int) -> void:
	var cur := _p1_selected_slot if pid == 1 else _p2_selected_slot
	var next := -1 if cur == slot_idx else slot_idx
	if pid == 1: _p1_selected_slot = next
	else:        _p2_selected_slot = next
	_refresh(pid)

## 點武藝池按鈕：
## - 這招已經裝備中 → 直接卸下（不管有沒有選取槽位）
## - 這招還沒裝備 → 只有在「已經選取某個裝備槽」時才有作用
func _on_art_clicked(pid: int, art_id: String) -> void:
	var sel: Array = _p1_sel if pid == 1 else _p2_sel
	if art_id in sel:
		_unequip(pid, sel.find(art_id))
		return
	var slot_idx := _p1_selected_slot if pid == 1 else _p2_selected_slot
	if slot_idx == -1:
		return
	_equip(pid, slot_idx, art_id)

## 裝備武藝到指定槽位（點擊或拖放都會走到這裡）。同一招不能同時裝備兩份——
## 若已經裝在別的槽位，直接擋下並提示，不做自動搬移（避免一次操作意外造成
## 兩格變動、悄悄吃掉替換上限）。
func _equip(pid: int, slot_idx: int, art_id: String) -> void:
	var sel:      Array = _p1_sel      if pid == 1 else _p2_sel
	var original: Array = _p1_original if pid == 1 else _p2_original
	if art_id == sel[slot_idx]:
		return
	if art_id in sel:
		_show_hint(pid, "這招已經裝備在別的槽位")
		return
	if sel[slot_idx] == original[slot_idx] and _changed_count(pid) >= 2:
		_show_hint(pid, "最多只能替換 2 種，已達上限")
		return
	sel[slot_idx] = art_id
	_commit(pid)

## 卸下指定槽位（清成空）。跟 _equip() 同一套上限檢查——這一格如果目前還沒被
## 算進「已變動」（跟原裝備一樣），卸下會讓它變動，一樣要先檢查上限。
func _unequip(pid: int, slot_idx: int) -> void:
	var sel:      Array = _p1_sel      if pid == 1 else _p2_sel
	var original: Array = _p1_original if pid == 1 else _p2_original
	if sel[slot_idx] == original[slot_idx] and _changed_count(pid) >= 2:
		_show_hint(pid, "最多只能替換 2 種，已達上限")
		return
	sel[slot_idx] = ""
	_commit(pid)

## 提交目前的 3 格裝備（每次變動都即時提交，沒有另外的「確認裝備」按鈕——
## 確認鍵管的是「進下一回合」，不是「鎖定這次的選擇」，兩者是分開的兩個概念）。
func _commit(pid: int) -> void:
	var sel: Array = _p1_sel if pid == 1 else _p2_sel
	var final_arts := sel.duplicate()

	if pid == 1: round_manager.p1_new_arts = final_arts
	else:        round_manager.p2_new_arts = final_arts

	var is_online := VsNetworkManager.mode != VsNetworkManager.Mode.OFFLINE
	if is_online and pid == VsNetworkManager.local_player_id:
		var character := VsGameManager.p1_character if pid == 1 else VsGameManager.p2_character
		VsNetworkManager.send_arts(final_arts, character)

	_refresh(pid)

## 短暫顯示警告訊息在該玩家的狀態列，下一次成功的操作會在 _refresh() 裡
## 蓋回正常的「已替換 X/2 種」文字。
func _show_hint(pid: int, text: String) -> void:
	var refs: Dictionary = _p1_refs if pid == 1 else _p2_refs
	var label: Label = refs["status"]
	label.text = text
	label.modulate = Color(1.0, 0.5, 0.4)

## 點擊背景（沒點中任何按鈕）取消槽位選取。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _p1_selected_slot != -1 or _p2_selected_slot != -1:
			_p1_selected_slot = -1
			_p2_selected_slot = -1
			_refresh_all()

func _refresh_all() -> void:
	_refresh(1)
	_refresh(2)

func _refresh(pid: int) -> void:
	var sel:      Array = _p1_sel      if pid == 1 else _p2_sel
	var refs:     Dictionary = _p1_refs if pid == 1 else _p2_refs
	var art_btns: Array = _p1_art_btns if pid == 1 else _p2_art_btns
	var slots:    Array = refs["slots"]
	var status:   Label = refs["status"]
	var selected_slot: int = _p1_selected_slot if pid == 1 else _p2_selected_slot
	var character := VsGameManager.p1_character if pid == 1 else VsGameManager.p2_character
	var arts := VsCharacterRegistry.get_arts(character)
	for i in art_btns.size():
		var equipped: bool = (arts[i] as String) in sel
		_set_btn_style(art_btns[i], equipped, false)
	for i in 3:
		slots[i].text = VsGameManager.get_display_name(sel[i]) if sel[i] != "" else "（空）"
		_set_btn_style(slots[i], sel[i] != "", i == selected_slot)
	status.modulate = Color(0.6, 0.6, 0.6)
	status.text = "已替換 %d/2 種" % _changed_count(pid)

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

func _on_confirm_a_pressed() -> void:
	VsGameManager.pending_confirm_1 = true

## PanelA 一律對應 InputState.from_input(1) 那個 slot（離線模式的本機 P1
## 玩家，或線上模式唯一顯示的本機玩家）；PanelB 只有離線模式才會顯示/可點擊，
## 對應 from_input(2)。線上模式時 PanelB 顯示的是本機玩家（網路身分剛好是
## P2），但本機輸入收集永遠只走 from_input(1)，這裡要跟著切，否則設的旗標
## 永遠不會被消費（實測抓到：線上模式本機是 P2 時確認鍵點了沒反應）。
func _on_confirm_b_pressed() -> void:
	if VsNetworkManager.mode == VsNetworkManager.Mode.OFFLINE:
		VsGameManager.pending_confirm_2 = true
	else:
		VsGameManager.pending_confirm_1 = true
