extends Control
## 選場地畫面：雙方各自用方向鍵在地圖清單移動游標、按確認鍵鎖定、取消鍵解鎖，
## 雙方鎖定同一張地圖後自動進入 vs_world。版面/雙人離線並排/線上單欄只顯示
## 本機的慣例跟 SelectScreen.gd 同一套（_panel_refs/_layout_panel/_build_ui），
## 地圖按鈕列的動態生成寫法照抄 SelectScreen._populate_character_row()。
##
## 確認/取消是純鍵盤（不走滑鼠點擊當主要操作方式，避免雙人共用同一顆滑鼠時
## 「這次點擊算誰的」的歧義）：離線模式 P1 方向鍵 A/D，確認 p1_attack（滑鼠
## 左鍵）、取消 p1_skill（滑鼠右鍵）；P2 方向鍵 ←/→，確認 p2_attack（數字鍵1）、
## 取消 p2_skill（數字鍵2）。這些動作名稱都已經存在於 InputMap（VsMods 既有
## 的 p1_*/p2_* 操作），沒有新增任何鍵位綁定。這個畫面不在 rollback 確定性
## 範圍內，直接用 Input.is_action_just_pressed() 輪詢，不經過 InputState。
##
## ⚠ 線上模式：本機不管佔線上哪個網路身分，操作永遠是 P1 那套配置（A/D+滑鼠
## 左右鍵），**不是**依 local_player_id 切換讀 p1_*/p2_*——這是 VsMods 貫穿全
## 專案的既有慣例（vs_world.gd 的 InputState.from_input(1) 就是同一條規則，
## 見 CLAUDE.md「P1 操作特殊」一節），本機是 CLIENT 也一樣用滑鼠+A/D，不會
## 真的去按數字鍵。第一版這裡誤以為「這個畫面沒有 rollback，所以可以自己重新
## 決定要不要套用這條規則」而讓 CLIENT 改讀 p2_*，導致連線模式雙方都卡住等
## 對方選地圖（本機根本沒在按 p2_* 綁定的數字鍵）——**這條規則要用哪個動作
## 名稱操作是全專案統一的裝置配置慣例，跟這個畫面在不在 rollback 範圍內無關，
## 之後任何新畫面都不要重新用「不在 rollback 範圍」這個理由自己另外決定。**
## 讀到的輸入結果仍然寫進 local_pid 對應的 _p1_*/_p2_* 狀態（哪一組狀態決定
## 畫面上顯示哪一欄），只有「用哪組動作名稱輪詢」這件事固定用 p1 前綴。

const VIEW_W := 384
const GAP    := 4
const COL_W  := (VIEW_W - GAP * 3) / 2

const C_AVAILABLE := Color(0.18, 0.18, 0.18)
const C_HOVER      := Color(0.35, 0.35, 0.35)
const C_CONFIRMED  := Color(0.85, 0.85, 0.85)

var _p1_refs: Dictionary = {}
var _p2_refs: Dictionary = {}

var _p1_btns: Array = []
var _p2_btns: Array = []

var _p1_cursor: int = 0
var _p2_cursor: int = 0
var _p1_confirmed_id: String = ""   # 空字串 = 未確認
var _p2_confirmed_id: String = ""

var _is_online: bool = false
var _local_pid: int = 1
var _remote_confirmed_id: String = ""
var _remote_has_data:     bool   = false   # 是否收過至少一次對方狀態（區分「對方還沒動作」跟「對方確認了空字串」）

var _status_label: Label
var _entered_match: bool = false   # 防止 _check_match() 條件成立後 change_scene 之前又被觸發第二次

func _ready() -> void:
	_is_online = VsNetworkManager.mode != VsNetworkManager.Mode.OFFLINE
	_local_pid = VsNetworkManager.local_player_id
	_status_label = $StatusLabel
	_p1_refs = _panel_refs($PanelA)
	_p2_refs = _panel_refs($PanelB)
	_build_ui()
	if _is_online:
		VsNetworkManager.remote_arena_received.connect(_on_remote_arena)

func _panel_refs(panel: Control) -> Dictionary:
	return {
		"section_label": panel.get_node("SectionLabel") as Label,
		"map_anchor":    panel.get_node("MapAnchor") as Control,
		"status_label":  panel.get_node("StatusLabel") as Label,
	}

# ── 建立 UI ───────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	if _is_online:
		var local_is_p1 := _local_pid == 1
		$VSeparator.visible = false
		$PanelA.visible = local_is_p1
		$PanelB.visible = not local_is_p1
		var panel: Control    = $PanelA if local_is_p1 else $PanelB
		var refs:  Dictionary = _p1_refs if local_is_p1 else _p2_refs
		_layout_panel(panel, refs, 0.0, VIEW_W)
		refs["section_label"].text = "P%d（你）" % _local_pid
		_populate_map_row(refs, _local_pid)
		# 連線模式操作永遠是 A/D+滑鼠那套（見 _handle_input 呼叫處說明），跟
		# 面板標籤顯示的 P1/P2 無關——固定顯示這個提示，不要照抄離線模式那句
		# 「P1：.../P2：...」的雙欄提示，避免玩家被自己的面板標籤（例如「P2
		# （你）」）誤導去按數字鍵。
		$ControlHint.text = "操作：A/D 選擇．滑鼠左鍵確認．滑鼠右鍵取消"
	else:
		$VSeparator.visible = true
		$PanelA.visible = true
		$PanelB.visible = true
		_layout_panel($PanelA, _p1_refs, 0.0, COL_W)
		_layout_panel($PanelB, _p2_refs, COL_W + GAP * 2, COL_W)
		_p1_refs["section_label"].text = "P1 PLAYER"
		_p2_refs["section_label"].text = "P2 PLAYER"
		_populate_map_row(_p1_refs, 1)
		_populate_map_row(_p2_refs, 2)
	_refresh_all()

## 面板本身跟底下會隨寬度變化的錨點一起重新定位——線上模式全寬單欄、離線
## 模式左右各半欄共用同一份排版邏輯，只有 x/width 不同（照抄 SelectScreen
## 的 _layout_panel() 寫法）。
func _layout_panel(panel: Control, refs: Dictionary, x: float, width: float) -> void:
	panel.position.x = x
	panel.size.x     = width
	(refs["map_anchor"]   as Control).size.x = width
	(refs["status_label"] as Label).size.x   = width
	(refs["section_label"] as Label).size.x  = width - GAP

# ── 地圖按鈕（動態，塞進 MapAnchor）───────────────────────────────────────────
const MAP_BTN_H := 16

func _populate_map_row(refs: Dictionary, pid: int) -> void:
	var anchor: Control = refs["map_anchor"]
	for c in anchor.get_children():
		c.queue_free()
	var ids   := VsArenaRegistry.all_ids()
	var width := anchor.size.x
	var bw    := (width - GAP * (ids.size() + 1)) / maxi(ids.size(), 1)
	var btns  := []
	for i in ids.size():
		var arena_id: String = ids[i]
		var idx := i
		var btn := Button.new()
		btn.text = VsArenaRegistry.get_display_name(arena_id)
		btn.add_theme_font_size_override("font_size", 9)   # 字體覆寫要先於 add_child()，理由同 SelectScreen
		btn.pressed.connect(func(): _on_map_clicked(pid, idx))
		anchor.add_child(btn)
		btn.position = Vector2(GAP + i * (bw + GAP), 0)
		btn.size     = Vector2(bw, MAP_BTN_H)
		btns.append(btn)
	if pid == 1: _p1_btns = btns
	else:        _p2_btns = btns

# ── 鍵盤輪詢（純鍵盤操作，見檔頭說明）───────────────────────────────────────────
func _process(_delta: float) -> void:
	if _entered_match:
		return
	if _is_online:
		# 本機不管佔線上哪個網路身分，動作名稱固定用 p1_ 前綴（A/D+滑鼠）——
		# 見檔頭說明，這是全專案既有慣例，不是這個畫面自己決定的。讀到的結果
		# 寫進 local_pid 對應的狀態，決定畫面顯示哪一欄。
		_handle_input(_local_pid, "p1_")
	else:
		_handle_input(1, "p1_")
		_handle_input(2, "p2_")

func _handle_input(pid: int, prefix: String) -> void:
	var confirmed: String = _p1_confirmed_id if pid == 1 else _p2_confirmed_id
	if confirmed == "":
		if Input.is_action_just_pressed(prefix + "left"):
			_move_cursor(pid, -1)
		elif Input.is_action_just_pressed(prefix + "right"):
			_move_cursor(pid, 1)
		if Input.is_action_just_pressed(prefix + "attack"):
			_confirm(pid)
	else:
		if Input.is_action_just_pressed(prefix + "skill"):
			_cancel(pid)

func _move_cursor(pid: int, delta: int) -> void:
	var ids := VsArenaRegistry.all_ids()
	if ids.is_empty():
		return
	var cursor: int = _p1_cursor if pid == 1 else _p2_cursor
	cursor = clampi(cursor + delta, 0, ids.size() - 1)
	if pid == 1: _p1_cursor = cursor
	else:        _p2_cursor = cursor
	_refresh(pid)

## 滑鼠點擊仍然保留，當鍵盤操作以外的便利選項——哪一欄的按鈕就對應哪一位
## 玩家（離線模式左右欄天生分開；線上模式只顯示本機那一欄），不會有「這次
## 點擊算誰的」的歧義。點擊 = 移動游標到這格，不直接確認，跟方向鍵選中同待遇。
func _on_map_clicked(pid: int, idx: int) -> void:
	var confirmed: String = _p1_confirmed_id if pid == 1 else _p2_confirmed_id
	if confirmed != "":
		return
	if pid == 1: _p1_cursor = idx
	else:        _p2_cursor = idx
	_refresh(pid)

func _confirm(pid: int) -> void:
	var ids := VsArenaRegistry.all_ids()
	var cursor: int = _p1_cursor if pid == 1 else _p2_cursor
	if cursor < 0 or cursor >= ids.size():
		return
	var arena_id: String = ids[cursor]
	if pid == 1: _p1_confirmed_id = arena_id
	else:        _p2_confirmed_id = arena_id
	if _is_online:
		VsNetworkManager.send_arena_choice(arena_id)
	_refresh(pid)
	_check_match()

func _cancel(pid: int) -> void:
	if pid == 1: _p1_confirmed_id = ""
	else:        _p2_confirmed_id = ""
	if _is_online:
		VsNetworkManager.send_arena_choice("")
	_refresh(pid)
	_check_match()

func _on_remote_arena(arena_id: String) -> void:
	_remote_confirmed_id = arena_id
	_remote_has_data     = true
	_refresh_status()
	_check_match()

## 兩邊都鎖定同一張地圖才進場——離線直接比對本機兩個欄位；線上比對「本機自己
## 那份確認值」跟「對方傳來的確認值」，兩者都非空且相等才算數（跟
## SelectScreen._try_enter_game() 等待 _local_confirmed && _remote_arts_ready
## 同一個等待模式）。
func _check_match() -> void:
	if _entered_match:
		return
	var agreed_id := ""
	if _is_online:
		var my_confirmed: String = _p1_confirmed_id if _local_pid == 1 else _p2_confirmed_id
		if my_confirmed == "" or not _remote_has_data or _remote_confirmed_id == "":
			return
		if my_confirmed != _remote_confirmed_id:
			return
		agreed_id = my_confirmed
	else:
		if _p1_confirmed_id == "" or _p2_confirmed_id == "" or _p1_confirmed_id != _p2_confirmed_id:
			return
		agreed_id = _p1_confirmed_id
	_entered_match = true
	VsGameManager.selected_arena_id = agreed_id
	get_tree().change_scene_to_file("res://VsMods/vs_world.tscn")

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://VsMods/ui/SelectScreen.tscn")

# ── 刷新顯示 ──────────────────────────────────────────────────────────────────
func _refresh_all() -> void:
	_refresh(1)
	_refresh(2)

func _refresh(pid: int) -> void:
	var btns:      Array      = _p1_btns if pid == 1 else _p2_btns
	var cursor:    int        = _p1_cursor if pid == 1 else _p2_cursor
	var confirmed: String     = _p1_confirmed_id if pid == 1 else _p2_confirmed_id
	var refs:      Dictionary = _p1_refs if pid == 1 else _p2_refs
	var ids := VsArenaRegistry.all_ids()
	for i in btns.size():
		var is_confirmed_here: bool = confirmed != "" and i < ids.size() and (ids[i] as String) == confirmed
		var is_cursor: bool = i == cursor and confirmed == ""
		_set_btn_style(btns[i], is_confirmed_here, is_cursor)
	var status_lbl: Label = refs["status_label"]
	status_lbl.text = ("已確認：%s" % VsArenaRegistry.get_display_name(confirmed)) if confirmed != "" else "尚未確認"
	_refresh_status()

## 畫面底部的共用狀態列——離線用來提示「雙方選擇不同」；線上額外要處理「對方
## 還沒回應」跟「對方已確認、換你了」這兩種本機看不到對方面板時才需要的提示。
func _refresh_status() -> void:
	if _is_online:
		var my_confirmed: String = _p1_confirmed_id if _local_pid == 1 else _p2_confirmed_id
		if my_confirmed == "":
			_status_label.text = "對方已確認" if (_remote_has_data and _remote_confirmed_id != "") else ""
		elif not _remote_has_data or _remote_confirmed_id == "":
			_status_label.text = "已確認，等待對方..."
		elif _remote_confirmed_id != my_confirmed:
			_status_label.text = "雙方選擇不同，請調整"
		else:
			_status_label.text = "即將開始..."
	else:
		if _p1_confirmed_id != "" and _p2_confirmed_id != "" and _p1_confirmed_id != _p2_confirmed_id:
			_status_label.text = "雙方選擇不同，請調整"
		else:
			_status_label.text = ""

func _set_btn_style(btn: Button, confirmed: bool, hover: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = C_CONFIRMED if confirmed else (C_HOVER if hover else C_AVAILABLE)
	if hover and not confirmed:
		style.border_width_left   = 2
		style.border_width_top    = 2
		style.border_width_right  = 2
		style.border_width_bottom = 2
		style.border_color = Color(1, 1, 1)
	btn.add_theme_stylebox_override("normal",  style)
	btn.add_theme_stylebox_override("hover",   style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_color_override("font_color", Color(0.08, 0.08, 0.08) if confirmed else Color(0.85, 0.85, 0.85))
