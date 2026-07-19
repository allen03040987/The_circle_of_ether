class_name BattleHud
extends CanvasLayer
## 對戰 HUD：血條、能量條、回合勝場點、回合結果文字
## 全程式碼建立節點，不依賴 .tscn。

# ── 尺寸常數（對應 384×216 基底解析度）──────────────────────────────────────
const BAR_W   := 150
const HP_H    := 8
const EN_H    := 4   # 武藝能量條高度
const DASH_H  := 3   # 衝刺能量條高度
const BAR_GAP := 2
const MARGIN  := 5
const VIEW_W  := 384
const VIEW_H  := 216

const DOT_SIZE := 7    # 勝場指示點大小
const DOT_GAP  := 3    # 點之間間距

const UKEMI_DOT_SIZE := 4   # 受身次數指示點——刻意比勝場點小很多，只是個小提示
const UKEMI_DOT_GAP  := 2

# ── 顏色 ──────────────────────────────────────────────────────────────────────
const C_BG     := Color(0.08, 0.08, 0.08, 0.88)
const C_BORDER := Color(0.35, 0.35, 0.35, 1.0)
const C_HP     := Color(0.95, 0.95, 0.95, 1.0)
const C_HP_LOW := Color(0.95, 0.25, 0.25, 1.0)
const C_ENERGY := Color(1.0,  0.85, 0.1,  1.0)   # 武藝能量（金色）
const C_DASH   := Color(0.3,  0.85, 1.0,  1.0)   # 衝刺能量（青色）
const C_DOT_ON := Color(1.0,  1.0,  1.0,  1.0)
const C_DOT_OFF:= Color(0.25, 0.25, 0.25, 1.0)
const C_UKEMI_ON  := Color(1.0,  0.85, 0.1,  1.0)   # 金色，跟武藝能量條同色
const C_UKEMI_OFF := Color(0.3,  0.27, 0.1,  1.0)   # 暗金＝用掉了

# ── 玩家參照 ──────────────────────────────────────────────────────────────────
var _p1: VsPlayer
var _p2: VsPlayer

# ── 血條 / 能量條 ─────────────────────────────────────────────────────────────
var _p1_hp:   ColorRect
var _p1_en:   ColorRect   # 武藝能量（金色）
var _p1_dash: ColorRect   # 衝刺能量（青色）
var _p2_hp:   ColorRect
var _p2_en:   ColorRect
var _p2_dash: ColorRect

# ── 勝場點 ────────────────────────────────────────────────────────────────────
var _p1_dots: Array = []   # Array[ColorRect]
var _p2_dots: Array = []

# ── 受身次數點（金色，貼在能量條下方跟 P1/P2 標籤同一列）───────────────────────
var _p1_ukemi_dots: Array = []
var _p2_ukemi_dots: Array = []

# ── 文字 ──────────────────────────────────────────────────────────────────────
var _result_label: Label   # 回合結果（平時隱藏）
var _ping_label:   Label   # 網路延遲顯示（離線時隱藏）

# ── 初始化 ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	layer = 10
	_build_ui()

func init(player1: VsPlayer, player2: VsPlayer) -> void:
	_p1 = player1
	_p2 = player2

# ── 每幀更新血條 ──────────────────────────────────────────────────────────────
func _process(_delta: float) -> void:
	if not _p1 or not _p2:
		return
	_set_bar(_p1_hp,   _p1.hp,          _p1.max_hp,          true)
	_set_bar(_p1_en,   _p1.arts_energy, _p1.max_arts_energy, true)
	_set_bar(_p1_dash, _p1.dash_energy, _p1.max_dash_energy, true)
	_set_bar(_p2_hp,   _p2.hp,          _p2.max_hp,          false)
	_set_bar(_p2_en,   _p2.arts_energy, _p2.max_arts_energy, false)
	_set_bar(_p2_dash, _p2.dash_energy, _p2.max_dash_energy, false)

	var r1 := _p1.hp / _p1.max_hp if _p1.max_hp > 0.0 else 0.0
	var r2 := _p2.hp / _p2.max_hp if _p2.max_hp > 0.0 else 0.0
	_p1_hp.color = C_HP_LOW if r1 < 0.25 else C_HP
	_p2_hp.color = C_HP_LOW if r2 < 0.25 else C_HP

	for i in _p1_ukemi_dots.size():
		_p1_ukemi_dots[i].color = C_UKEMI_ON if i < _p1.ukemi_uses_left else C_UKEMI_OFF
	for i in _p2_ukemi_dots.size():
		_p2_ukemi_dots[i].color = C_UKEMI_ON if i < _p2.ukemi_uses_left else C_UKEMI_OFF

	# 延遲顯示：讀取預測深度，換算為 ms（60fps → 每幀 ≈ 16.67ms）
	if _ping_label.visible:
		var depth := VsNetworkManager.get_prediction_depth()
		_ping_label.text = "延遲 ~%dms" % int(depth * 1000.0 / 60.0) if depth > 0 else "延遲 <17ms"

func _set_bar(fill: ColorRect, cur: float, max_val: float, ltr: bool) -> void:
	var w := int(BAR_W * clampf(cur / max_val, 0.0, 1.0)) if max_val > 0.0 else 0
	fill.size.x = w
	if not ltr:
		fill.position.x = BAR_W - w

# ── 外部 API ──────────────────────────────────────────────────────────────────
func update_wins(p1w: int, p2w: int) -> void:
	for i in VsRoundManager.ROUNDS_TO_WIN:
		_p1_dots[i].color = C_DOT_ON if i < p1w else C_DOT_OFF
		_p2_dots[i].color = C_DOT_ON if i < p2w else C_DOT_OFF

func show_round_result(winner_id: int) -> void:
	match winner_id:
		1: _result_label.text = "P1 WINS!"
		2: _result_label.text = "P2 WINS!"
		_: _result_label.text = "DRAW!"
	_result_label.visible = true

func show_round_num(round_num: int) -> void:
	_result_label.text    = "ROUND %d" % round_num
	_result_label.visible = true
	# 短暫顯示後隱藏（用 SceneTree Timer 避免引入 Node 計時器）
	get_tree().create_timer(1.0).timeout.connect(func(): _result_label.visible = false)

func show_game_over(winner_id: int) -> void:
	_result_label.text    = "P%d WINS THE MATCH!\n按任意鍵返回" % winner_id
	_result_label.visible = true

func show_message(text: String) -> void:
	_result_label.text    = text
	_result_label.visible = true

# ── 建立 UI ───────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var lx := MARGIN
	var rx := VIEW_W - MARGIN - BAR_W
	var y0 := MARGIN
	var y1 := y0 + HP_H + BAR_GAP         # 武藝能量條 y
	var y2 := y1 + EN_H + BAR_GAP         # 衝刺能量條 y

	# 血條 / 武藝能量條 / 衝刺能量條
	_p1_hp   = _make_bar(root, lx, y0, BAR_W, HP_H,  C_HP)
	_p1_en   = _make_bar(root, lx, y1, BAR_W, EN_H,  C_ENERGY)
	_p1_dash = _make_bar(root, lx, y2, BAR_W, DASH_H, C_DASH)
	_p2_hp   = _make_bar(root, rx, y0, BAR_W, HP_H,  C_HP)
	_p2_en   = _make_bar(root, rx, y1, BAR_W, EN_H,  C_ENERGY)
	_p2_dash = _make_bar(root, rx, y2, BAR_W, DASH_H, C_DASH)

	# 玩家標籤
	var label_y := y2 + DASH_H + 2
	_make_label(root, "P1", lx,              label_y, 8)
	_make_label(root, "P2", rx + BAR_W - 14, label_y, 8)

	# 受身次數點（跟 P1/P2 標籤同一列，貼在該側能量條的另一端，避免跟文字重疊）
	var ukemi_w := VsPlayer.UKEMI_MAX_USES * UKEMI_DOT_SIZE + (VsPlayer.UKEMI_MAX_USES - 1) * UKEMI_DOT_GAP
	var ukemi_y := label_y + 2
	for i in VsPlayer.UKEMI_MAX_USES:
		_p1_ukemi_dots.append(_make_ukemi_dot(root, lx + BAR_W - ukemi_w + i * (UKEMI_DOT_SIZE + UKEMI_DOT_GAP), ukemi_y))
	for i in VsPlayer.UKEMI_MAX_USES:
		_p2_ukemi_dots.append(_make_ukemi_dot(root, rx + i * (UKEMI_DOT_SIZE + UKEMI_DOT_GAP), ukemi_y))

	# 勝場指示點（中央上方）
	var cx     := VIEW_W / 2
	var dot_y  := y0 + 1
	var n      := VsRoundManager.ROUNDS_TO_WIN
	var blk_w  := n * DOT_SIZE + (n - 1) * DOT_GAP

	# P1 點（靠中心左側）
	for i in n:
		var dx := cx - 4 - blk_w + i * (DOT_SIZE + DOT_GAP)
		var dot := _make_dot(root, dx, dot_y)
		_p1_dots.append(dot)

	# P2 點（靠中心右側）
	for i in n:
		var dx := cx + 4 + i * (DOT_SIZE + DOT_GAP)
		var dot := _make_dot(root, dx, dot_y)
		_p2_dots.append(dot)

	# 回合結果 / GAME OVER 大字（螢幕中央）
	_result_label          = Label.new()
	_result_label.visible  = false
	_result_label.position = Vector2(0, VIEW_H / 2 - 10)
	_result_label.size     = Vector2(VIEW_W, 20)
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 14)
	root.add_child(_result_label)

	# 網路延遲標籤（螢幕底部中央，離線模式自動隱藏）
	_ping_label          = Label.new()
	_ping_label.position = Vector2(0, VIEW_H - 11)
	_ping_label.size     = Vector2(VIEW_W, 10)
	_ping_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ping_label.add_theme_font_size_override("font_size", 7)
	_ping_label.modulate = Color(1, 1, 1, 0.55)
	_ping_label.visible  = (VsNetworkManager.mode != VsNetworkManager.Mode.OFFLINE)
	root.add_child(_ping_label)

# ── 私有輔助 ──────────────────────────────────────────────────────────────────
func _make_bar(parent: Control, x: int, y: int, w: int, h: int, color: Color) -> ColorRect:
	var border := ColorRect.new()
	border.position = Vector2(x - 1, y - 1)
	border.size     = Vector2(w + 2, h + 2)
	border.color    = C_BORDER
	parent.add_child(border)

	var bg := ColorRect.new()
	bg.position      = Vector2(1, 1)
	bg.size          = Vector2(w, h)
	bg.color         = C_BG
	bg.clip_contents = true
	border.add_child(bg)

	var fill := ColorRect.new()
	fill.size  = Vector2(w, h)
	fill.color = color
	bg.add_child(fill)
	return fill

func _make_dot(parent: Control, x: int, y: int) -> ColorRect:
	var dot := ColorRect.new()
	dot.position = Vector2(x, y)
	dot.size     = Vector2(DOT_SIZE, DOT_SIZE)
	dot.color    = C_DOT_OFF
	parent.add_child(dot)
	return dot

func _make_ukemi_dot(parent: Control, x: int, y: int) -> ColorRect:
	var dot := ColorRect.new()
	dot.position = Vector2(x, y)
	dot.size     = Vector2(UKEMI_DOT_SIZE, UKEMI_DOT_SIZE)
	dot.color    = C_UKEMI_ON
	parent.add_child(dot)
	return dot

func _make_label(parent: Control, text: String, x: int, y: int, size: int) -> Label:
	var lbl := Label.new()
	lbl.text     = text
	lbl.position = Vector2(x, y)
	lbl.add_theme_font_size_override("font_size", size)
	parent.add_child(lbl)
	return lbl
