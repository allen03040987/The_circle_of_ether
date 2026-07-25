extends Control
## 選場地畫面：單一共用地圖清單，滑鼠點選 + 確認/取消兩顆按鈕。
##
## 離線模式（本地雙人）**不分 P1/P2 面板**——雙方就在同一台電腦前，選哪張
## 地圖用嘴巴講好就行，不需要重複一套「雙方各自確認再比對是否相同」的流程；
## 選好直接按確認就進場，沒有「等待對方」的狀態，也不需要取消鍵（選錯了
## 直接點別張地圖換選項就好）。
##
## 連線模式才需要完整的「確認→等待對方→比對是否相同」流程（兩端各自只看
## 得到自己的畫面，只有一份本機的 _confirmed_id，透過 remote_arena_received
## 收對方的狀態）。取消鍵只在連線模式顯示（已確認、想改選才用得到）。
##
## 第一版做過鍵盤方向鍵選+action鍵確認取消（比照戰鬥操作鍵位），使用者反映
## 這樣不直覺，改成單純的滑鼠點擊選圖 + 確認/取消按鈕，離線模式合併成一個
## 選單即可，不用維護 P1/P2 兩套獨立游標/確認狀態。
##
## 連線模式即時預覽對方選圖進度（2026-07-22）：本機**每次點選**（不是只有
## 確認才送）都呼叫 send_arena_choice(arena_id, confirmed)，讓對方不用乾等
## 到你按確認才知道你在看哪張——RemoteMarker 這顆 Label 跟著對方目前選到的
## 按鈕移動，文字依 confirmed 狀態顯示「對方選擇中」/「對方已確認」。

const MAP_BTN_W := 70
const MAP_BTN_H := 40
const MAP_GAP   := 6

const C_AVAILABLE := Color(0.18, 0.18, 0.18)
const C_SELECTED  := Color(0.35, 0.35, 0.35)
const C_CONFIRMED := Color(0.85, 0.85, 0.85)

var _map_btns: Array = []
var _selected_id:  String = ""   # 目前點選但還沒鎖定
var _confirmed_id: String = ""   # 空字串 = 未確認

var _is_online: bool = false
var _remote_selected_id:  String = ""   # 對方目前點選（不管有沒有確認）的地圖，空字串＝對方還沒點過
var _remote_confirmed_id: String = ""   # 對方已經確認鎖定的地圖，空字串＝對方還沒確認
var _remote_has_data:     bool   = false   # 是否收過至少一次對方狀態

var _status_label:   Label
var _confirm_button: Button
var _cancel_button:  Button
var _remote_marker:  Label
var _entered_match:  bool = false   # 防止 _check_match() 條件成立後 change_scene 之前又被觸發第二次

func _ready() -> void:
	_is_online = VsNetworkManager.mode != VsNetworkManager.Mode.OFFLINE
	_status_label   = $StatusLabel
	_confirm_button = $ConfirmButton
	_cancel_button  = $CancelButton
	_remote_marker  = $RemoteMarker
	_confirm_button.pressed.connect(_on_confirm_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	_cancel_button.visible = _is_online
	_populate_map_row()
	if _is_online:
		VsNetworkManager.remote_arena_received.connect(_on_remote_arena)
	_refresh()

# ── 地圖按鈕（動態，塞進 MapAnchor，置中排列）───────────────────────────────────
func _populate_map_row() -> void:
	var anchor := $MapAnchor as Control
	for c in anchor.get_children():
		c.queue_free()
	_map_btns.clear()
	var ids     := VsArenaRegistry.all_ids()
	var total_w := ids.size() * MAP_BTN_W + maxi(ids.size() - 1, 0) * MAP_GAP
	var start_x: float = (anchor.size.x - total_w) / 2.0
	for i in ids.size():
		var arena_id: String = ids[i]
		var btn := Button.new()
		btn.text = VsArenaRegistry.get_display_name(arena_id)
		btn.add_theme_font_size_override("font_size", 10)   # 字體覆寫要先於 add_child()，理由同 SelectScreen
		btn.pressed.connect(func(): _on_map_clicked(arena_id))
		anchor.add_child(btn)
		btn.position = Vector2(start_x + i * (MAP_BTN_W + MAP_GAP), 0)
		btn.size     = Vector2(MAP_BTN_W, MAP_BTN_H)
		_map_btns.append(btn)

func _on_map_clicked(arena_id: String) -> void:
	if _confirmed_id != "":
		return
	_selected_id = arena_id
	if _is_online:
		VsNetworkManager.send_arena_choice(arena_id, false)
	_refresh()

func _on_confirm_pressed() -> void:
	if _selected_id == "" or _confirmed_id != "":
		return
	_confirmed_id = _selected_id
	if _is_online:
		VsNetworkManager.send_arena_choice(_confirmed_id, true)
	_refresh()
	_check_match()

func _on_cancel_pressed() -> void:
	if _confirmed_id == "":
		return
	_confirmed_id = ""
	# 取消只解鎖，_selected_id 還是原本那張（_refresh() 會照舊顯示成「選取中」），
	# 廣播的也是同一張、只是 confirmed 改回 false，不是清空成沒有選擇。
	if _is_online:
		VsNetworkManager.send_arena_choice(_selected_id, false)
	_refresh()

func _on_remote_arena(arena_id: String, confirmed: bool) -> void:
	_remote_selected_id  = arena_id
	_remote_confirmed_id = arena_id if confirmed else ""
	_remote_has_data     = true
	_refresh()
	_check_match()

## 離線：確認當下就直接進場，沒有「雙方比對」這回事（單一共用選擇，見檔頭
## 說明）。連線：本機確認 + 收到對方確認 + 兩者相同才進場（跟
## SelectScreen._try_enter_game() 等待 _local_confirmed && _remote_arts_ready
## 同一個等待模式）。
func _check_match() -> void:
	if _entered_match:
		return
	var agreed_id := ""
	if _is_online:
		if _confirmed_id == "" or not _remote_has_data or _remote_confirmed_id == "":
			return
		if _confirmed_id != _remote_confirmed_id:
			return
		agreed_id = _confirmed_id
	else:
		if _confirmed_id == "":
			return
		agreed_id = _confirmed_id
	_entered_match = true
	VsGameManager.selected_arena_id = agreed_id
	get_tree().change_scene_to_file("res://VsMods/vs_world.tscn")

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://VsMods/ui/SelectScreen.tscn")

# ── 刷新顯示 ──────────────────────────────────────────────────────────────────
func _refresh() -> void:
	var ids := VsArenaRegistry.all_ids()
	for i in _map_btns.size():
		var arena_id: String = ids[i]
		var is_confirmed_here := _confirmed_id != "" and arena_id == _confirmed_id
		var is_selected := arena_id == _selected_id and _confirmed_id == ""
		_set_btn_style(_map_btns[i], is_confirmed_here, is_selected)
	_confirm_button.disabled = _confirmed_id != "" or _selected_id == ""
	_cancel_button.disabled  = _confirmed_id == ""
	_update_remote_marker()
	_refresh_status()

## 讓對方目前選到的地圖有個跟著跑的小標籤，不用等對方按確認才知道他在看哪張。
## RemoteMarker 是根層級節點（不是 MapAnchor 底下的子節點）——_populate_map_row()
## 每次都會把 MapAnchor 的子節點全部 queue_free() 重建，塞在裡面的話這個固定
## 標籤節點會被一起清掉。要換算成跟 btn.position 同一個座標系，得手動加回
## MapAnchor 自己的 position 偏移。
func _update_remote_marker() -> void:
	if not _is_online or not _remote_has_data or _remote_selected_id == "":
		_remote_marker.visible = false
		return
	var ids := VsArenaRegistry.all_ids()
	var idx := ids.find(_remote_selected_id)
	if idx == -1 or idx >= _map_btns.size():
		_remote_marker.visible = false
		return
	var btn: Button    = _map_btns[idx]
	var anchor_pos: Vector2 = ($MapAnchor as Control).position
	_remote_marker.visible  = true
	_remote_marker.text     = "對方已確認" if _remote_confirmed_id == _remote_selected_id else "對方選擇中"
	_remote_marker.position = anchor_pos + Vector2(btn.position.x, btn.position.y + btn.size.y + 2)
	_remote_marker.size     = Vector2(btn.size.x, 10)

func _refresh_status() -> void:
	if _confirmed_id == "":
		_status_label.text = ""
		return
	if not _is_online:
		_status_label.text = "即將開始..."
		return
	if not _remote_has_data or _remote_confirmed_id == "":
		_status_label.text = "已確認：%s，等待對方..." % VsArenaRegistry.get_display_name(_confirmed_id)
	elif _remote_confirmed_id != _confirmed_id:
		_status_label.text = "雙方選擇不同，請取消重選"
	else:
		_status_label.text = "即將開始..."

func _set_btn_style(btn: Button, confirmed: bool, selected: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = C_CONFIRMED if confirmed else (C_SELECTED if selected else C_AVAILABLE)
	if selected and not confirmed:
		style.border_width_left   = 2
		style.border_width_top    = 2
		style.border_width_right  = 2
		style.border_width_bottom = 2
		style.border_color = Color(1, 1, 1)
	btn.add_theme_stylebox_override("normal",  style)
	btn.add_theme_stylebox_override("hover",   style)
	btn.add_theme_stylebox_override("pressed", style)
	btn.add_theme_color_override("font_color", Color(0.08, 0.08, 0.08) if confirmed else Color(0.85, 0.85, 0.85))
