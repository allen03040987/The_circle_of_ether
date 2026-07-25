class_name BattleHud
extends CanvasLayer
## 對戰 HUD：血條、能量條、回合勝場點、回合結果文字
## 大部分節點由程式碼建立、不依賴 .tscn；例外是頭頂身份標籤（VsNameTag.tscn），
## 外觀需要頻繁微調，改用可視化編輯，見 NAME_TAG_SCENE。

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
const C_DENIED_WHITE := Color(1.0, 1.0, 1.0, 1.0)   # 武藝能量不足被拒——閃爍色 1
const C_DENIED_RED   := Color(1.0, 0.15, 0.15, 1.0) # 武藝能量不足被拒——閃爍色 2
const DENIED_FLASH_HZ := 20.0   # 閃爍頻率（次/秒），數值越大閃越快

## 武藝能量顯示縮放常數搬到 VsGameManager.ARTS_ENERGY_DISPLAY_SCALE 了——
## VsArtInfoPopup 的說明文字也要用同一個比例，放單一自治的地方共用，不要
## 這裡跟彈窗各自維護一份。

const ENERGY_FULL_RAINBOW_SPEED       := 0.35   # 能量滿時色相變化速度（每秒繞色相環的比例）
const ENERGY_FULL_RAINBOW_SATURATION  := 0.55
const ENERGY_FULL_RAINBOW_VALUE       := 1.3    # >1.0 微 HDR 提亮，跟其他高亮效果同一套手法

# ── 裝備武藝徽章（單字，黑底白框，見 VsGameManager.get_art_badge_char() 註解）──
const BADGE_SIZE   := 18
const BADGE_GAP    := 4
const BADGE_BORDER := 2   # 白框粗細
const C_BADGE_BG            := Color(0.0, 0.0, 0.0, 1.0)     # 徽章底色：統一純黑
const C_BADGE_BORDER_ON     := Color(1.0, 1.0, 1.0, 1.0)     # 有裝備：白框
const C_BADGE_BORDER_EMPTY  := Color(0.3, 0.3, 0.3, 1.0)     # 空槽位：暗灰框
const C_BADGE_HIGHLIGHT     := Color(1.3, 1.3, 1.3, 1.0)     # 修飾鍵按著時的高亮（比 1.0 亮，HDR 提亮）
const C_BADGE_CAST_PULSE    := Color(1.4, 1.4, 1.4, 0.85)    # 施放成功脈衝殘影色：淡白（比 1.0 亮一點，HDR 微微發光）

# ── 玩家頭頂身份標籤 ──────────────────────────────────────────────────────────
# 外觀（文字/圖標的相對位置、大小、字型、顏色、浮動速度/振幅）全部在
# VsNameTag.tscn 裡用編輯器調，這裡不重複放任何數值常數——參照
# VsArtButton/VsArtInfoPopup 同一套「可視化編輯」慣例（見 CLAUDE.md）。
const NAME_TAG_SCENE := preload("res://VsMods/ui/VsNameTag.tscn")

# ── 角色腳下 buff 狀態小字（哪個屬性生效中、還剩幾秒）───────────────────────
const BUFF_LABEL_W        := 60
const BUFF_LABEL_Y_OFFSET := 6   # 螢幕像素，貼在角色腳底（position，非 sprite 錨點）下方
const C_BUFF_LABEL        := Color(1.0, 0.95, 0.5, 1.0)   # 統一淡黃色，跟殘影的個別屬性色分開管

## 徽章單字字體——預設沿用專案全域字體（PixelTheme 的 pixel.ttf），如果這個
## 路徑有檔案就改用它（使用者要換書法字體：把字體檔放到這個路徑，不用再改
## 程式碼，下次執行就自動套用）。找不到檔案時 ResourceLoader.exists() 會是
## false，直接跳過，不會報錯。
const BADGE_FONT_PATH := "res://VsMods/ui/badge_font.ttf"
var _badge_font: Font = load(BADGE_FONT_PATH) if ResourceLoader.exists(BADGE_FONT_PATH) else null

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

# ── 血條/武藝能量條數字（疊在條上；血條只顯示目前血量單一數字，武藝能量條
# 維持"目前/上限"）─────────────────────────────────────────────────────────
var _p1_hp_label: Label
var _p2_hp_label: Label
var _p1_en_label: Label
var _p2_en_label: Label

# ── 玩家頭頂身份標籤（P1/P2，VsNameTag.tscn 實例，跟隨世界座標但不隨鏡頭
# 縮放，見 _update_name_tags()）─────────────────────────────────────────────
var _p1_name_tag: VsNameTag
var _p2_name_tag: VsNameTag

# ── 角色腳下 buff 狀態小字（跟隨世界座標，見 _update_buff_labels()）──────────
var _p1_buff_label: Label
var _p2_buff_label: Label

# ── 裝備武藝徽章（各 3 格：root 縮放容器 / 白框 / 單字 / 耗能數字）───────────
# root 是 border+char 的共同父節點，修飾鍵高亮縮放整組一起動；cost 是獨立
# 節點（只淡入淡出，不用跟著放大縮小）。border 是「有沒有裝備」的視覺區分
# （白框/暗灰框），黑底色固定不變（見 C_BADGE_BG）。
var _p1_badge_root:   Array = []   # Array[Control]
var _p1_badge_border: Array = []   # Array[ColorRect]
var _p1_badge_char:   Array = []   # Array[Label]
var _p1_badge_cost:   Array = []   # Array[Label]
var _p2_badge_root:   Array = []
var _p2_badge_border: Array = []
var _p2_badge_char:   Array = []
var _p2_badge_cost:   Array = []
## 本機武藝修飾鍵（E）目前是否按著——用來比照主遊戲 CombatUI 的做法，按著時
## 本機實際操作的那個玩家（見 _process() 的 local_is_p1 判斷）徽章放大高亮、
## 耗能數字淡入。不是「P1 專屬」：連線模式本機不管佔線上哪個網路身分都用同一
## 套滑鼠+E 操作（vs_world.gd 的 local_input 永遠走 InputState.from_input(1)
## 收集），本機是 CLIENT（P2）時高亮的是 _p2 徽章，不是 _p1。
var _local_modifier_held: bool = false
var _local_badge_tween: Tween

# ── 文字 ──────────────────────────────────────────────────────────────────────
var _result_label: Label   # 回合結果（平時隱藏）
var _ping_label:   Label   # 網路延遲 + FPS 顯示（永遠顯示；離線模式只顯示 FPS）

# ── 初始化 ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	layer = 10
	_build_ui()

func init(player1: VsPlayer, player2: VsPlayer) -> void:
	_p1 = player1
	_p2 = player2
	_p1.art_cast.connect(func(slot: int): _spawn_badge_cast_pulse(_p1_badge_root, slot))
	_p2.art_cast.connect(func(slot: int): _spawn_badge_cast_pulse(_p2_badge_root, slot))

	# 耗能數字初始顯示狀態：本機實際操作的那個玩家（離線固定 P1；連線模式
	# 不管本機佔線上哪個網路身分，實際操作永遠是滑鼠+E 配置，見
	# _local_modifier_held 宣告處的說明）預設隱藏、等按 E 才淡入（_make_art_badge()
	# 建立時 cost_label 預設 alpha 就是 0，不用額外處理）；對面（離線 P2 沒有
	# 修飾鍵概念，或連線模式的遠端玩家）耗能數字永遠常駐顯示。這裡才第一次
	# 用得上 VsNetworkManager 的角色資訊——_build_ui() 執行時（_ready()）角色
	# 還沒連線完成、不能在那邊寫死「P2 永遠常駐」。
	var local_is_p1 := VsNetworkManager.mode == VsNetworkManager.Mode.OFFLINE \
		or VsNetworkManager.local_player_id == 1
	var other_cost: Array = _p2_badge_cost if local_is_p1 else _p1_badge_cost
	for lbl: Label in other_cost:
		lbl.modulate.a = 1.0

# ── 每幀更新血條 ──────────────────────────────────────────────────────────────
func _process(_delta: float) -> void:
	if not _p1 or not _p2:
		return
	_update_name_tags()
	_update_buff_labels()
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

	# 武藝能量條顏色，三選一（互斥，能量不足被拒跟能量滿不會同時發生）：
	# 1. 被拒：閃白/紅提示（VsPlayer.arts_denied_flash_left 由 use_arts_energy()
	#    在能量不足時觸發，這裡純粹讀值決定顏色，不碰邏輯）
	# 2. 能量滿：動態彩色色相（純視覺、跟模擬時間無關，見 _rainbow_color()）
	# 3. 平時：正常金色
	var rainbow := _rainbow_color()
	_p1_en.color = _denied_flash_color(_p1.arts_denied_flash_left) if _p1.arts_denied_flash_left > 0.0 \
		else (rainbow if _p1.arts_energy >= _p1.max_arts_energy else C_ENERGY)
	_p2_en.color = _denied_flash_color(_p2.arts_denied_flash_left) if _p2.arts_denied_flash_left > 0.0 \
		else (rainbow if _p2.arts_energy >= _p2.max_arts_energy else C_ENERGY)

	# 血條/武藝能量條數字：血量顯示原始整數；武藝能量刻意 ×0.1 顯示（實際數值
	# 沒變,只是玩家看到的數字縮小一位——比照下面 _update_art_badges() 的耗能
	# 數字用同一個縮放比例,兩邊要對得上,不然玩家會覺得「顯示的能量」跟「這招
	# 要花多少」是兩套不同單位）
	_p1_hp_label.text = "%d" % int(_p1.hp)
	_p2_hp_label.text = "%d" % int(_p2.hp)
	_p1_en_label.text = "%d" % roundi(_p1.arts_energy * VsGameManager.ARTS_ENERGY_DISPLAY_SCALE)
	_p2_en_label.text = "%d" % roundi(_p2.arts_energy * VsGameManager.ARTS_ENERGY_DISPLAY_SCALE)

	for i in _p1_ukemi_dots.size():
		_p1_ukemi_dots[i].color = C_UKEMI_ON if i < _p1.ukemi_uses_left else C_UKEMI_OFF
	for i in _p2_ukemi_dots.size():
		_p2_ukemi_dots[i].color = C_UKEMI_ON if i < _p2.ukemi_uses_left else C_UKEMI_OFF

	# 裝備武藝徽章：框色/單字每幀同步（換裝武藝、回合重選都會反映），耗能
	# 數字文字每幀更新（讀 loaded_arts 的實際 energy_cost，不是靜態表）
	_update_art_badges(_p1, _p1_badge_border, _p1_badge_char, _p1_badge_cost)
	_update_art_badges(_p2, _p2_badge_border, _p2_badge_char, _p2_badge_cost)

	# 本機修飾鍵高亮：離線模式本機固定操作 P1（P2 是同機第二玩家、純鍵盤沒有
	# 修飾鍵概念）；連線模式不管本機佔線上哪個網路身分，本機實際操作永遠是
	# 滑鼠+E 那套配置（見 _local_modifier_held 宣告處的說明）——本機是 HOST
	# 就高亮 _p1，是 CLIENT 就高亮 _p2。對面（連線模式的遠端玩家）沒辦法觀察
	# 本機鍵盤狀態，耗能數字乾脆常駐顯示，不強行做一個「假裝知道對方按鍵」的
	# 高亮動畫。
	var local_is_p1 := VsNetworkManager.mode == VsNetworkManager.Mode.OFFLINE \
		or VsNetworkManager.local_player_id == 1
	var local_badge_root: Array = _p1_badge_root if local_is_p1 else _p2_badge_root
	var local_badge_cost: Array = _p1_badge_cost if local_is_p1 else _p2_badge_cost
	var remote_badge_cost: Array = _p2_badge_cost if local_is_p1 else _p1_badge_cost

	if VsNetworkManager.mode != VsNetworkManager.Mode.OFFLINE:
		for lbl: Label in remote_badge_cost:
			lbl.modulate.a = 1.0

	var modifier_held := Input.is_action_pressed("martial_modifier")
	if modifier_held != _local_modifier_held:
		_local_modifier_held = modifier_held
		_animate_badge_highlight(local_badge_root, local_badge_cost, modifier_held)

	# 延遲 + FPS 顯示：FPS 永遠顯示（Engine.get_frames_per_second() 是引擎
	# 自己平滑過的即時值），延遲只在連線模式才有意義、離線就只顯示 FPS
	var fps_text := "%d FPS" % Engine.get_frames_per_second()
	if VsNetworkManager.mode != VsNetworkManager.Mode.OFFLINE:
		var depth := VsNetworkManager.get_prediction_depth()
		var ping_text := "延遲 ~%dms" % int(depth * 1000.0 / 60.0) if depth > 0 else "延遲 <17ms"
		_ping_label.text = "%s　%s" % [ping_text, fps_text]
	else:
		_ping_label.text = fps_text

## 依剩餘閃爍時間算出當下該顯示白還紅——用整數化的時間切格子交替，不用 Tween
## （純視覺、每幀重算，不用額外狀態）
func _denied_flash_color(flash_left: float) -> Color:
	var elapsed := VsPlayer.ARTS_DENIED_FLASH_DURATION - flash_left
	return C_DENIED_WHITE if int(elapsed * DENIED_FLASH_HZ) % 2 == 0 else C_DENIED_RED

## 武藝能量滿時的動態彩色色相——用 Time.get_ticks_msec() 連續變化，不用額外的
## 累計計時器（純視覺、跟 P1/P2 共用同一個色相，本來就沒有需要跟模擬時間或
## rollback 同步的理由：這裡不是 VsPlayer/VsState 呼叫鏈內的東西，是 BattleHud
## 自己的 _process()，不受確定性規則約束）。
func _rainbow_color() -> Color:
	var hue := fmod(Time.get_ticks_msec() / 1000.0 * ENERGY_FULL_RAINBOW_SPEED, 1.0)
	return Color.from_hsv(hue, ENERGY_FULL_RAINBOW_SATURATION, ENERGY_FULL_RAINBOW_VALUE)

func _set_bar(fill: ColorRect, cur: float, max_val: float, ltr: bool) -> void:
	var w := int(BAR_W * clampf(cur / max_val, 0.0, 1.0)) if max_val > 0.0 else 0
	fill.size.x = w
	if not ltr:
		fill.position.x = BAR_W - w

## 框色/單字每幀同步成當下裝備的武藝（換裝、回合重選都會即時反映）：有裝備
## 白框、空槽位暗灰框，底色統一黑，靠框色+文字辨識「這格有沒有裝備」，不靠
## 顏色分辨是哪一招（使用者要求統一黑白）。耗能數字讀 loaded_arts 實際持有
## 的 VsMartialArt 實例（跟主遊戲 CombatUI 讀 m_slots[i].energy_cost 同一套
## 做法，不是另外維護一份靜態對照表）。這裡不碰任何透明度——是否顯示耗能
## 數字由 _process() 的修飾鍵邏輯/P2 常駐邏輯各自決定，職責分開。耗能數字套
## 跟能量條數字同一個 VsGameManager.ARTS_ENERGY_DISPLAY_SCALE 縮放，兩邊單位要對得上。
func _update_art_badges(vs: VsPlayer, borders: Array, chars: Array, costs: Array) -> void:
	for i in 3:
		var art_id: String = vs.art_slots[i] if i < vs.art_slots.size() else ""
		borders[i].color = C_BADGE_BORDER_ON if art_id != "" else C_BADGE_BORDER_EMPTY
		chars[i].text     = VsGameManager.get_art_badge_char(art_id)
		var art := vs.get_art_in_slot(i + 1)
		costs[i].text = str(roundi(art.energy_cost * VsGameManager.ARTS_ENERGY_DISPLAY_SCALE)) if is_instance_valid(art) else ""

## 比照主遊戲 player/UI/CombatUI.gd::_on_player_martial_mode_changed()：
## 修飾鍵按下時 3 個徽章（背景+單字一起，見 _make_art_badge() 的 root 容器）
## 放大高亮，耗能數字淡入；放開時淡出還原。roots/costs 是本機實際操作的那個
## 玩家的徽章陣列（_p1_* 或 _p2_*，見 _process() 的 local_is_p1 判斷）——不寫
## 死 _p1，因為連線模式本機可能操作的是 _p2。
func _animate_badge_highlight(roots: Array, costs: Array, is_active: bool) -> void:
	if is_instance_valid(_local_badge_tween):
		_local_badge_tween.kill()
	_local_badge_tween = create_tween().set_parallel(true)
	for i in 3:
		var root: Control = roots[i]
		var cost: Label    = costs[i]
		if is_active:
			_local_badge_tween.tween_property(root, "scale", Vector2(1.15, 1.15), 0.12)
			_local_badge_tween.tween_property(root, "modulate", C_BADGE_HIGHLIGHT, 0.12)
			_local_badge_tween.tween_property(cost, "modulate:a", 1.0, 0.12)
		else:
			_local_badge_tween.tween_property(root, "scale", Vector2(1.0, 1.0), 0.15)
			_local_badge_tween.tween_property(root, "modulate", Color.WHITE, 0.15)
			_local_badge_tween.tween_property(cost, "modulate:a", 0.0, 0.15)

## 武藝成功施放時的脈衝殘影，比照主遊戲 player/UI/CombatUI.gd::_spawn_cast_afterimage()：
## 疊一塊跟徽章同尺寸的色塊、放大到 1.5 倍同時淡出、結束後自動 free。徽章本身
## 是純色塊+文字（沒有圖標貼圖可複製），所以殘影用同一組 HDR 綠色塊代替原版的
## 貼圖殘影，視覺同款（放大淡出的「炸開」感）。由 VsPlayer.art_cast signal 觸發
## （見 init()），slot 是 1/2/3。
func _spawn_badge_cast_pulse(roots: Array, slot: int) -> void:
	var idx := slot - 1
	if idx < 0 or idx >= roots.size(): return
	var root: Control = roots[idx]
	if not is_instance_valid(root): return

	var pulse := ColorRect.new()
	pulse.size         = Vector2(BADGE_SIZE, BADGE_SIZE)
	pulse.position      = Vector2.ZERO
	pulse.pivot_offset = Vector2(BADGE_SIZE / 2.0, BADGE_SIZE / 2.0)
	pulse.color         = C_BADGE_CAST_PULSE
	pulse.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	root.add_child(pulse)

	var tween := create_tween().set_parallel(true)
	tween.tween_property(pulse, "scale", Vector2(1.5, 1.5), 0.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(pulse, "modulate:a", 0.0, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(pulse.queue_free)

## 頭頂身份標籤：每幀把玩家的世界座標（vfx_anchor_position()，跟殘影/火花同一套
## 「看起來的身體位置」基準）透過 get_viewport().get_canvas_transform() 換算成
## 螢幕像素座標——這個 transform 已經把 VsCamera 當下的 position/zoom 都算進去，
## 換算完的結果直接是 BattleHud 這個 CanvasLayer 慣用的 384×216 像素座標系，餵給
## VsNameTag（純資料，不管外觀）。標籤節點本身在 CanvasLayer 底下，不受鏡頭
## zoom 影響；文字/圖標的相對位置、大小、浮動速度/振幅都是 VsNameTag.tscn 裡
## 可視化調的，這裡不重複管。
func _update_name_tags() -> void:
	var canvas_xform := get_viewport().get_canvas_transform()
	_p1_name_tag.set_anchor_screen_position(canvas_xform * _p1.vfx_anchor_position())
	_p2_name_tag.set_anchor_screen_position(canvas_xform * _p2.vfx_anchor_position())

## 角色腳下 buff 狀態小字：跟頭頂標籤同一套「世界座標→螢幕座標」換算手法，
## 但錨點用 position（腳底，模擬座標，見 CLAUDE.md 確定性規則表——這裡純顯示
## 用不影響模擬，直接讀沒關係）而不是 vfx_anchor_position()（那個是身體中心，
## 給殘影/火花用），因為「腳下」的視覺意義就是貼著角色站立的地面位置，不是
## 貼著身體。文字內容讀 hazard_buff_time_left（哪些屬性生效中）+
## HAZARD_BUFF_DISPLAY_NAMES（顯示名稱），沒有生效中的 buff 就顯示空字串。
func _update_buff_labels() -> void:
	var canvas_xform := get_viewport().get_canvas_transform()
	_position_buff_label(_p1_buff_label, canvas_xform * _p1.position)
	_position_buff_label(_p2_buff_label, canvas_xform * _p2.position)
	_set_buff_label_text(_p1_buff_label, _p1)
	_set_buff_label_text(_p2_buff_label, _p2)

func _position_buff_label(lbl: Label, screen_pos: Vector2) -> void:
	lbl.position = screen_pos + Vector2(-BUFF_LABEL_W / 2.0, BUFF_LABEL_Y_OFFSET)

func _set_buff_label_text(lbl: Label, vs: VsPlayer) -> void:
	if vs.hazard_buff_time_left.is_empty():
		lbl.text = ""
		return
	var lines: Array[String] = []
	for stat: String in vs.hazard_buff_time_left:
		var display_name: String = VsPlayer.HAZARD_BUFF_DISPLAY_NAMES.get(stat, stat)
		lines.append("%s %ds" % [display_name, ceili(vs.hazard_buff_time_left[stat])])
	lbl.text = "\n".join(lines)

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

	# 血條/武藝能量條數字（疊在條上置中——條本身很薄，數字故意比條高，
	# 上下溢出一點點，不會被 bg 的 clip_contents 裁掉，因為是獨立疊上去的
	# 節點，不是塞進 bar 內部結構）
	_p1_hp_label = _make_bar_label(root, lx, y0, BAR_W, HP_H, true)
	_p2_hp_label = _make_bar_label(root, rx, y0, BAR_W, HP_H, false)
	_p1_en_label = _make_bar_label(root, lx, y1, BAR_W, EN_H, true)
	_p2_en_label = _make_bar_label(root, rx, y1, BAR_W, EN_H, false)

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

	# 裝備武藝徽章（3 格，貼在螢幕底部、貼近 ping/FPS 標籤上方；耗能數字疊在
	# 徽章下面，預設淡出，見 _process() 的修飾鍵高亮邏輯）。徽章區塊高度＝
	# BADGE_SIZE（本體）+1（間距）+9（耗能數字行高），預留在 ping_label（貼
	# 底部、10px 高）之上，避免兩者重疊。
	var badge_block_h := BADGE_SIZE + 1 + 9
	var badge_y := VIEW_H - 11 - 5 - badge_block_h
	# P1 貼左邊界往右排（跟血條/能量條同一側對齊），P2 鏡像：貼右邊界往左排
	# （整排右邊緣對齊 rx+BAR_W，跟 P1 整排左邊緣對齊 lx 互為鏡像），比照
	# HP/EN 數字標籤 P1 靠左/P2 靠右的對稱慣例，不要兩排都往同一方向長
	var badge_row_w := 3 * BADGE_SIZE + 2 * BADGE_GAP
	for i in 3:
		var b1 := _make_art_badge(root, lx + i * (BADGE_SIZE + BADGE_GAP), badge_y)
		_p1_badge_root.append(b1["root"]); _p1_badge_border.append(b1["border"])
		_p1_badge_char.append(b1["char"]); _p1_badge_cost.append(b1["cost"])
	for i in 3:
		var b2 := _make_art_badge(root, rx + BAR_W - badge_row_w + i * (BADGE_SIZE + BADGE_GAP), badge_y)
		_p2_badge_root.append(b2["root"]); _p2_badge_border.append(b2["border"])
		_p2_badge_char.append(b2["char"]); _p2_badge_cost.append(b2["cost"])
	# 耗能數字常駐/淡入淡出的初始狀態要看本機實際操作哪個玩家（離線固定 P1，
	# 連線模式看 local_player_id），這裡（_ready()）連線角色還沒確定，交給
	# init() 處理，見該處說明。

	# 玩家頭頂身份標籤（P1/P2 文字 + 三角指標）。初始位置無所謂，_process() 每幀
	# 由 _update_name_tags() 依世界座標覆寫（見該函式說明）。
	_p1_name_tag = NAME_TAG_SCENE.instantiate()
	root.add_child(_p1_name_tag)
	_p1_name_tag.set_text("P1")

	_p2_name_tag = NAME_TAG_SCENE.instantiate()
	root.add_child(_p2_name_tag)
	_p2_name_tag.phase = PI   # 跟 P1（相位 0）錯開，兩個標籤不會同步上下浮動
	_p2_name_tag.set_text("P2")

	# 角色腳下 buff 狀態小字。初始位置無所謂，_process() 每幀由
	# _update_buff_labels() 依世界座標覆寫（見該函式說明）。
	_p1_buff_label = _make_buff_label(root)
	_p2_buff_label = _make_buff_label(root)

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

	# 網路延遲 + FPS 標籤（螢幕底部中央，永遠顯示——FPS 離線模式也有意義）
	_ping_label          = Label.new()
	_ping_label.position = Vector2(0, VIEW_H - 11)
	_ping_label.size     = Vector2(VIEW_W, 10)
	_ping_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ping_label.add_theme_font_size_override("font_size", 7)
	_ping_label.modulate = Color(1, 1, 1, 0.55)
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

## 疊在血條/能量條上、垂直置中的數字標籤——條本身只有 4~8px 高塞不下可讀的
## 字，這裡故意給比條高的字級（含外框描邊確保在深/淺底色上都看得清楚），
## 疊出來的上下溢出是預期效果，不是 bug。獨立節點（不是 bar 內部結構的子節點），
## 不會被 bar 的 bg.clip_contents 裁切。
## 貼在條的「前端」而不是置中——ltr 跟 _set_bar() 同一個參數：P1 的條由左往右
## 填，前端＝左邊；P2 的條由右往左填，前端＝右邊。置中會卡在填色邊界上，
## 深淺背景交界處看起來很怪，貼邊反而穩定好讀。
func _make_bar_label(parent: Control, x: int, y: int, w: int, h: int, ltr: bool) -> Label:
	var lbl := Label.new()
	lbl.position = Vector2(x + 2, y + h / 2.0 - 5.0)
	lbl.size     = Vector2(w - 4, 10)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if ltr else HORIZONTAL_ALIGNMENT_RIGHT
	lbl.add_theme_font_size_override("font_size", 7)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 2)
	parent.add_child(lbl)
	return lbl

## 角色腳下的 buff 狀態小字——純文字、無背景，多行（同時有多個屬性生效時）
## 置中對齊，字級跟血條數字同一套（含描邊確保各種底色都看得清楚）。
func _make_buff_label(parent: Control) -> Label:
	var lbl := Label.new()
	lbl.size = Vector2(BUFF_LABEL_W, 20)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", 7)
	lbl.add_theme_color_override("font_color", C_BUFF_LABEL)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 2)
	parent.add_child(lbl)
	return lbl

## 一格裝備武藝徽章：root（縮放容器，掛 border+bg+char，修飾鍵高亮時整組
## 一起放大）+ border（正方白框，套 C_BADGE_BORDER_ON/EMPTY 決定有無裝備）
## + bg（統一黑底，套在 border 內縮 BADGE_BORDER px）+ char（單字，套
## _badge_font 如果有的話）+ cost（耗能數字，獨立節點、不隨 root 縮放，只做
## 淡入淡出）。cost 預設透明（本機操作那個玩家的預設狀態，等修飾鍵按下才淡入；
## 對面玩家由 init() 事後強制設回不透明——那時才確定本機實際操作哪一邊，見
## init() 說明）。
func _make_art_badge(parent: Control, x: int, y: int) -> Dictionary:
	var root := Control.new()
	root.position     = Vector2(x, y)
	root.size         = Vector2(BADGE_SIZE, BADGE_SIZE)
	root.pivot_offset = Vector2(BADGE_SIZE / 2.0, BADGE_SIZE / 2.0)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(root)

	var border := ColorRect.new()
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.color = C_BADGE_BORDER_EMPTY
	root.add_child(border)

	var bg := ColorRect.new()
	bg.position = Vector2(BADGE_BORDER, BADGE_BORDER)
	bg.size     = Vector2(BADGE_SIZE - BADGE_BORDER * 2, BADGE_SIZE - BADGE_BORDER * 2)
	bg.color    = C_BADGE_BG
	root.add_child(bg)

	var char_label := Label.new()
	char_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	char_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	char_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	char_label.add_theme_font_size_override("font_size", 13)
	char_label.add_theme_color_override("font_color", Color.WHITE)
	if _badge_font:
		char_label.add_theme_font_override("font", _badge_font)
	root.add_child(char_label)

	var cost_label := Label.new()
	cost_label.position = Vector2(x - 4, y + BADGE_SIZE + 1)
	cost_label.size     = Vector2(BADGE_SIZE + 8, 9)
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.add_theme_font_size_override("font_size", 7)
	cost_label.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	cost_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	cost_label.add_theme_constant_override("outline_size", 2)
	cost_label.modulate.a = 0.0
	parent.add_child(cost_label)

	return {"root": root, "border": border, "char": char_label, "cost": cost_label}

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

