extends Control
## 選角色畫面（2026-08-03，從 SelectScreen 拆出來）——仿格鬥遊戲選角：
## 單一大張角色顯示 + 左右箭頭切換，取代原本擠在 SelectScreen 裡的那排小按鈕。
## 流程順序：LobbyScreen → CharacterSelectScreen（這裡）→ SelectScreen（純武藝）
## → MapSelectScreen → vs_world。
##
## 離線模式：P1（PanelA）左半、P2（PanelB）右半，各自獨立切換，跟 SelectScreen
## 原本的左右對半版面同一套邏輯，只是現在整個面板都只用來放角色，高度寬裕很多。
## 連線模式：只顯示本機那半（看 local_player_id 是 P1 還是 P2），拉滿全寬。
##
## ⚠ 角色選擇不需要跟對手比對是否相同（跟 MapSelectScreen 的地圖選擇不同，
## 雙方各選各的即可）——連線模式這裡不用「等待對方確認」流程，本機選好按
## 確認鍵就直接前往 SelectScreen；對方選了誰，沿用既有機制在 SelectScreen
## 最終確認時透過 VsNetworkManager.send_arts(arts, character_id) 一併送出
## （這個函式本來就已經在送 character_id 了，不用新增 WS 訊息型別，也就不用
## 動 signaling_server.py 的白名單／不用重新部署）。
##
## PortraitAnchor 目前是空的 ColorRect 佔位——立繪/角色預覽圖之後由使用者自己
## 準備、自己在編輯器塞進去，這裡先留好放大圖的錨點位置與大小。

const VIEW_W := 384
const GAP    := 4
const COL_W  := (VIEW_W - GAP * 3) / 2

var _p1_idx: int = 0
var _p2_idx: int = 0

var _is_online: bool = false
var _local_pid: int  = 1

var _p1_refs: Dictionary = {}
var _p2_refs: Dictionary = {}

func _ready() -> void:
	_is_online = VsNetworkManager.mode != VsNetworkManager.Mode.OFFLINE
	_local_pid = VsNetworkManager.local_player_id
	_p1_refs = _panel_refs($PanelA)
	_p2_refs = _panel_refs($PanelB)
	_connect_panel(_p1_refs, 1)
	_connect_panel(_p2_refs, 2)
	$BackButton.pressed.connect(_on_back_pressed)
	$ConfirmButton.pressed.connect(_on_confirm_pressed)
	_build_ui()

func _panel_refs(panel: Control) -> Dictionary:
	return {
		"section_label":  panel.get_node("SectionLabel") as Label,
		"portrait_anchor": panel.get_node("PortraitAnchor") as Control,
		"name_label":     panel.get_node("NameLabel") as Label,
		"index_label":    panel.get_node("IndexLabel") as Label,
		"left_btn":       panel.get_node("LeftButton") as TextureButton,
		"right_btn":      panel.get_node("RightButton") as TextureButton,
	}

func _connect_panel(refs: Dictionary, pid: int) -> void:
	(refs["left_btn"] as TextureButton).pressed.connect(func(): _cycle(pid, -1))
	(refs["right_btn"] as TextureButton).pressed.connect(func(): _cycle(pid, 1))

func _build_ui() -> void:
	if _is_online:
		var local_is_p1 := _local_pid == 1
		$VSeparator.visible = false
		$PanelA.visible = local_is_p1
		$PanelB.visible = not local_is_p1
		var refs: Dictionary = _p1_refs if local_is_p1 else _p2_refs
		refs["section_label"].text = "P%d（你）" % _local_pid
		$ConfirmButton.text = "確認角色"
	else:
		$VSeparator.visible = true
		$PanelA.visible = true
		$PanelB.visible = true
		_p1_refs["section_label"].text = "P1 PLAYER"
		_p2_refs["section_label"].text = "P2 PLAYER"
		$ConfirmButton.text = "下一步"
	_refresh_all()

## 左右切換角色——純本機瀏覽，不廣播（角色不用跟對方比對，見檔頭說明）。
func _cycle(pid: int, dir: int) -> void:
	var ids := VsCharacterRegistry.all_ids()
	if ids.is_empty():
		return
	if pid == 1:
		_p1_idx = (_p1_idx + dir + ids.size()) % ids.size()
	else:
		_p2_idx = (_p2_idx + dir + ids.size()) % ids.size()
	_refresh(pid)

func _refresh_all() -> void:
	_refresh(1)
	_refresh(2)

func _refresh(pid: int) -> void:
	var refs: Dictionary = _p1_refs if pid == 1 else _p2_refs
	var idx: int = _p1_idx if pid == 1 else _p2_idx
	var ids := VsCharacterRegistry.all_ids()
	if ids.is_empty():
		return
	var char_id: String = ids[idx]
	(refs["name_label"] as Label).text  = VsCharacterRegistry.get_display_name(char_id)
	(refs["index_label"] as Label).text = "%d / %d" % [idx + 1, ids.size()]

func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://VsMods/ui/LobbyScreen.tscn")

func _on_confirm_pressed() -> void:
	var ids := VsCharacterRegistry.all_ids()
	if ids.is_empty():
		return
	if _is_online:
		var char_id: String = ids[_p1_idx if _local_pid == 1 else _p2_idx]
		if _local_pid == 1:
			VsGameManager.p1_character = char_id
		else:
			VsGameManager.p2_character = char_id
	else:
		VsGameManager.p1_character = ids[_p1_idx]
		VsGameManager.p2_character = ids[_p2_idx]
	get_tree().change_scene_to_file("res://VsMods/ui/SelectScreen.tscn")
