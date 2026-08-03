class_name VsArtInfoPopup
extends Control
## 武藝詳情彈窗——點武藝格右上角的「!」按鈕開啟，顯示該招的效果說明。
## 排版是 VsArtInfoPopup.tscn 裡的真實節點（背景/標題/說明框/關閉鍵位置大小
## 都可以直接在編輯器裡拖動調整），這裡只負責填內容跟開關邏輯，不建節點。
## 說明文字資料在 VsGameManager.ART_DESCRIPTIONS/ART_NAMES。

signal closed

const SCENE := preload("res://VsMods/ui/VsArtInfoPopup.tscn")

@onready var _dim:   ColorRect = $Dim
@onready var _title: Label    = $Panel/Title
@onready var _desc:  Label    = $Panel/Desc

var art_id: String = ""

## 共用開啟入口，跟 VsSettingsPanel.open_over() 同一套樣板（獨立 CanvasLayer，
## 關閉時整層 queue_free）。layer 22——比 VsSettingsPanel 的 21 高一層，因為
## 這個彈窗預期是從已經開著的選角/重選畫面上呼叫，不會跟設定選單同時開。
static func open_over(parent: Node, art_id: String, layer: int = 22) -> CanvasLayer:
	var canvas := CanvasLayer.new()
	canvas.layer = layer
	parent.add_child(canvas)
	var popup := SCENE.instantiate() as VsArtInfoPopup
	popup.art_id = art_id
	popup.closed.connect(func(): canvas.queue_free())
	canvas.add_child(popup)
	return canvas

func _ready() -> void:
	# get_display_name() 現在直接回傳正式招式名稱（2026-07-27 改版，取代原本
	# 的「武藝N」佔位編號），跟 get_art_name() 是同一份資料，不用再兩個並列
	# 顯示（以前是「武藝一：逆鱗返」，兩者統一後會變成重複的「逆鱗返：逆鱗返」）。
	_title.text = VsGameManager.get_display_name(art_id)
	var desc: String = VsGameManager.ART_DESCRIPTIONS.get(art_id, "（尚無說明）")
	# 消耗能量數字套跟 BattleHud 能量條/徽章同一個顯示縮放（VsGameManager.
	# ARTS_ENERGY_DISPLAY_SCALE），玩家在選角畫面看到的數字要跟局內看到的
	# 對得上。VsArtRegistry.get_energy_cost() 臨時建一個武藝實例讀 energy_cost
	# ——這個畫面此時還沒有真正裝在玩家身上的 VsMartialArt 可以問。
	var cost := roundi(VsArtRegistry.get_energy_cost(art_id) * VsGameManager.ARTS_ENERGY_DISPLAY_SCALE)
	_desc.text = "%s\n\n消耗能量：%d" % [desc, cost]
	# ⚠ 用 ARBITRARY 不是 WORD——WORD 模式要靠文字系統找到「單字」邊界才會
	# 換行，中文沒有空白分詞，實測完全不換行、整段文字直接超出框外。ARBITRARY
	# 不管詞語邊界、單純依框寬換行，中日韓文字要保證能換行一定要用這個。用
	# 程式碼設定而不是在 .tscn 填數字——AutowrapMode 是 enum，直接在文字格式
	# 裡填數字容易填錯，用具名常數比較保險。
	_desc.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_dim.gui_input.connect(_on_dim_input)

func _on_dim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		closed.emit()

func _on_close_pressed() -> void:
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		closed.emit()
