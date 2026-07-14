class_name PixelOptionButton
extends Button
## 自訂下拉選單：不透過引擎原生 PopupMenu/Window 彈出清單，改成一般 Control（Button）疊出清單。
## 原因：Godot 的 Popup 本質上是獨立 Window，在這個專案「384x216 低解析度 + canvas_items 拉伸」的
## 設定下，字型算圖不會跟主畫面共用同一套清晰度，展開清單的文字會糊掉，且沒有簡單的 Theme/API 能修好。
## 全部走一般 Control 疊圖就不會有這個問題——跟其他一般 Button/Label 一樣清晰。
##
## API 刻意對齊 OptionButton 的慣用寫法（clear/add_item/set_item_metadata/get_item_metadata/
## selected/select/item_count/disabled/item_selected 訊號），讓既有呼叫端幾乎不用改。

signal item_selected(index: int)

const ARROW_ICON = preload("res://ui/icons/dropdown_arrow.png")

var _items: Array[Dictionary] = [] # [{ "text": String, "metadata": Variant }]
var _selected: int = -1
var _is_open: bool = false

var item_count: int:
	get: return _items.size()

var selected: int:
	get: return _selected
	set(value):
		if value < 0 or value >= _items.size(): return
		_selected = value
		text = _items[_selected]["text"]

const MAX_LIST_HEIGHT: float = 150.0 ## 清單本身的高度上限，避免離螢幕邊緣還很遠時也硬撐出超長的框

@onready var _backdrop: Control = $ListLayer/Backdrop
@onready var _list_panel: PanelContainer = $ListLayer/Backdrop/ListPanel
@onready var _list_scroll: ScrollContainer = $ListLayer/Backdrop/ListPanel/ListScroll
@onready var _item_list: VBoxContainer = $ListLayer/Backdrop/ListPanel/ListScroll/ItemList

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	icon = ARROW_ICON
	icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if not pressed.is_connected(_toggle_open):
		pressed.connect(_toggle_open)
	if not _backdrop.gui_input.is_connected(_on_backdrop_input):
		_backdrop.gui_input.connect(_on_backdrop_input)
	_backdrop.visible = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if _is_open and not is_visible_in_tree():
			_close_list()

## 清空所有選項（不會清掉目前顯示的文字，等第一次 add_item 才會刷新）
func clear() -> void:
	_items.clear()
	_selected = -1
	text = ""
	_clear_item_buttons()

func add_item(item_text: String) -> void:
	_items.append({"text": item_text, "metadata": null})
	if _selected == -1:
		self.selected = 0

func set_item_metadata(idx: int, value) -> void:
	if idx >= 0 and idx < _items.size():
		_items[idx]["metadata"] = value

func get_item_metadata(idx: int) -> Variant:
	if idx >= 0 and idx < _items.size():
		return _items[idx]["metadata"]
	return null

## 對齊 OptionButton.select()：只改顯示選取狀態，不觸發 item_selected 訊號
func select(idx: int) -> void:
	self.selected = idx

func _toggle_open() -> void:
	if disabled: return
	if _is_open:
		_close_list()
	else:
		_open_list()

func _open_list() -> void:
	_rebuild_item_buttons()
	_backdrop.visible = true
	_backdrop.size = get_viewport_rect().size
	_backdrop.position = Vector2.ZERO
	_list_panel.custom_minimum_size.x = size.x
	_list_panel.global_position = global_position + Vector2(0, size.y)
	_is_open = true

	# 🌟 項目數量算好高度需要等一幀讓 Container 重新計算子節點的最小尺寸，
	# 不然這裡量到的還是舊的（甚至是 0）
	await get_tree().process_frame
	if not _is_open: return # 這一幀等待期間使用者又把清單關掉了，不要再動已經隱藏的節點

	var available_height = get_viewport_rect().size.y - _list_panel.global_position.y - 4.0
	var content_height = _item_list.get_combined_minimum_size().y
	_list_scroll.custom_minimum_size.y = minf(content_height, minf(available_height, MAX_LIST_HEIGHT))

func _close_list() -> void:
	_backdrop.visible = false
	_is_open = false

## 點在清單外面（Backdrop 本體，不是某個項目按鈕）就收合——項目按鈕會自己吃掉點擊事件，不會傳到這裡
func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_close_list()

func _clear_item_buttons() -> void:
	for child in _item_list.get_children():
		child.queue_free()

func _rebuild_item_buttons() -> void:
	_clear_item_buttons()
	for i in range(_items.size()):
		var btn := Button.new()
		btn.text = _items[i]["text"]
		btn.focus_mode = Control.FOCUS_NONE
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		# 🌟 平常不畫框，只有滑鼠移過去才用主題的白底反轉高亮——清單本身已經有 ListPanel 的外框，
		# 每個項目不需要再各自畫一層框，不然會變成一格一格的箱子
		var flat_normal := StyleBoxEmpty.new()
		flat_normal.content_margin_left = 6.0
		flat_normal.content_margin_top = 4.0
		flat_normal.content_margin_right = 6.0
		flat_normal.content_margin_bottom = 4.0
		btn.add_theme_stylebox_override("normal", flat_normal)
		btn.pressed.connect(_on_item_pressed.bind(i))
		_item_list.add_child(btn)

func _on_item_pressed(idx: int) -> void:
	self.selected = idx
	_close_list()
	item_selected.emit(idx)
