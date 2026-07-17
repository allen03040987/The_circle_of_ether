class_name VsAttack
extends VsPlayerState
## 普攻連段狀態（地面5段）
## 每招的所有資料都住在 VsPlayer.tscn，程式碼只剩打斷/派生邏輯：
##   時間點 —— attack_N 動畫軌道：`.:can_combo`（連段窗口）、
##             `Graphics/HitboxAN:monitoring`（判定框開關）
##   判定框大小/位置/傷害/硬直/擊退 —— 每招一顆 HitboxAN 節點的 @export（編輯器直接調）
## AnimationPlayer 是 MANUAL 模式、由 VsPlayer.apply_input 以模擬 delta 推進，
## 軌道值是模擬時間的純函數 → rollback 安全。

# 攻擊輸入緩衝時長（秒）——沿用主遊戲 Player.ATTACK_BUFFER_DURATION 的設計。
# ⚠ 必須小於所有段的 can_combo 窗口開啟時間，否則「起手那一下按鍵」的緩衝會
#   撐到窗口開啟、自動多接一段（enter() 會清緩衝，所以段與段之間不會誤傳）。
const ATTACK_BUFFER: float = 0.2
const MAX_COMBO:     int   = 5
# 攻擊期間水平減速率——比照主遊戲 Katana.gd 的 FLOOR_ACCELERATION
# (RUN_SPEED/0.04 = 8750px/s²)，而不是一般移動用的 VsPlayerState.FRICTION（900）。
# strike_impulse 的前衝力道要靠這麼強的摩擦力才煞得住：用一般移動摩擦力的話，
# 同樣的衝力強度會滑出將近 20 倍遠（滑行距離 ∝ v²/摩擦力），主遊戲數值搬過來
# 測試會直接飛超遠就是這個落差。
const IMPULSE_FRICTION: float = 8750.0

# ── 狀態變數 ──────────────────────────────────────────────────────────────────
var combo_step:         int   = 1
var elapsed:            float = 0.0
var attack_buffer_left: float = 0.0   # 攻擊輸入緩衝倒計（>0 = 有緩衝中的輸入）
var _anim_length:       float = 0.0   # 當前段動畫總長（enter/restore 時從動畫資源讀取）

# ── 進場 ──────────────────────────────────────────────────────────────────────
func enter(_prev: StringName) -> void:
	elapsed            = 0.0
	attack_buffer_left = 0.0
	var vs        := player as VsPlayer
	var anim_name := "attack_%d" % combo_step

	vs.can_combo = false   # 由動畫軌道在窗口時間點重新拉起
	_reset_hitboxes(vs)    # 清掉上一段殘留的判定框，本段的由動畫軌道開啟
	# 攻擊起手清除殘留水平動量（跑步衝進攻擊不再滑行）；前衝/突刺感改由
	# strike_impulse 動畫呼叫方法軌道注入，主遊戲同款設計，見 VsPlayer.strike_impulse()
	player.velocity.x = 0.0
	vs.anim_player.play(anim_name)
	_anim_length = vs.anim_player.get_animation(anim_name).length

	vs.mark_in_combat()

# ── 每幀更新 ──────────────────────────────────────────────────────────────────
func physics_update(delta: float, input: InputState) -> StringName:
	elapsed += delta
	var vs := player as VsPlayer

	# 攻擊輸入緩衝：任何時點按下都記錄 0.2s，窗口開啟時才消耗
	# （主遊戲 combo_buffer_time 的做法——提前按不會漏拍）
	if input.attack:
		attack_buffer_left = ATTACK_BUFFER
	elif attack_buffer_left > 0.0:
		attack_buffer_left = maxf(attack_buffer_left - delta, 0.0)

	# ── 打斷優先級（沿用主遊戲 WeaponAttack 的順位）────────────────────────
	# 1. 衝刺取消：最高打斷權限，任何時點可施放（規則：衝刺可打斷任何非受擊動作）
	if input.dodge and vs.use_dash_energy(30.0):
		return &"vsdodge"   # exit() 會清 hitbox / can_combo 並重置 combo_step

	# 2. 防禦取消：地面限定（空中不可防禦）
	if input.guard and _grounded():
		return &"vsguard"

	# 3. 武藝取消：權限僅次衝刺/防禦、不受連段窗限制（規則：武藝可打斷普攻施放）
	var art_transition := _check_art_cast(input)
	if art_transition != &"":
		return art_transition   # exit() 會清 hitbox / can_combo 並重置 combo_step

	# 4. 連段派生：窗口（動畫軌道的 can_combo）開啟且有緩衝輸入
	#    → 立刻取消剩餘動畫接下一段（不等動畫播完）
	if vs.can_combo and attack_buffer_left > 0.0 and combo_step < MAX_COMBO:
		combo_step += 1
		enter(&"vsattack")   # 直接重啟，繞過防重入（exit() 不會被呼叫；enter() 會清窗口/緩衝/hitbox）
		return &""

	# 地面慣性衰減（攻擊期間不接受移動輸入）——用 IMPULSE_FRICTION 而非一般
	# 移動摩擦力，讓 strike_impulse 打出的前衝力道快速收回，不會飛太遠
	if _grounded():
		player.velocity.x = move_toward(player.velocity.x, 0.0, IMPULSE_FRICTION * delta)
	else:
		_apply_gravity(delta)

	# 動畫結束（末段或窗口內沒按 → 收招）
	if elapsed >= _anim_length:
		combo_step = 1
		return &"vsidle" if _grounded() else &"vsfall"

	return &""

# ── 離場 ──────────────────────────────────────────────────────────────────────
func exit() -> void:
	combo_step = 1
	var vs := player as VsPlayer
	vs.can_combo = false
	_reset_hitboxes(vs)

func _reset_hitboxes(vs: VsPlayer) -> void:
	for hb: VsHitbox in vs.hitboxes:
		hb.monitoring = false
		hb.reset_hits()

func save_state() -> Dictionary:
	# 判定框狀態（monitoring / has_hit）由 VsPlayer.save_state 統一保存
	return {
		"step":    combo_step,
		"elapsed": elapsed,
		"buf":     attack_buffer_left,
	}

func restore_state(d: Dictionary) -> void:
	combo_step         = d.get("step",    1)
	elapsed            = d.get("elapsed", 0.0)
	attack_buffer_left = d.get("buf",     0.0)
	var vs := player as VsPlayer
	if is_instance_valid(vs):
		_anim_length = vs.anim_player.get_animation("attack_%d" % combo_step).length

func sync_anim() -> void:
	var vs := player as VsPlayer
	vs.anim_player.play("attack_%d" % combo_step)
	vs.anim_player.seek(elapsed, true)
