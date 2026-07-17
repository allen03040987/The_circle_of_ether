class_name VsAirAttack
extends VsPlayerState
## 空中普攻連段狀態（3 段，動畫時間軸/hitbox 數值移植自主遊戲 Katana air_light_1~3）
## 跟地面 VsAttack 同一套資料驅動模式：時間點在 air_attack_1~3 動畫軌道
## （`.:can_combo` 連段窗口、`Graphics/HitboxAirN:monitoring` 判定框開關），
## 判定框大小/位置/傷害/硬直/擊退在每招一顆的 HitboxAir1~3 節點（VsHitbox
## @export，編輯器直接調），跟地面 HitboxA1~5 是同一個 `VsPlayer.hitboxes`
## 陣列（`_ready()` 通用收集 Graphics 底下所有 VsHitbox），不用另外的集合。
##
## 全程受一般重力影響——沒有移植主遊戲第 3 段專屬的「近零重力浮空 + 延遲上勾
## 噴射」演出（那是主遊戲那招的專屬花招，不是「多段空中普攻」規則本身要求的，
## 之後想加再說）。落地當幀立刻收招：空中連段不能延續到地面。

const ATTACK_BUFFER:    float = 0.2
const MAX_COMBO:        int   = 3
# 攻擊期間水平減速率，跟地面 VsAttack 同一套理由：strike_impulse 的前衝力道
# 要靠這麼強的摩擦力才煞得住，一般移動摩擦力（900）會飛太遠。
const IMPULSE_FRICTION: float = 8750.0

# ── 狀態變數 ──────────────────────────────────────────────────────────────────
var combo_step:         int   = 1
var elapsed:            float = 0.0
var attack_buffer_left: float = 0.0
var _anim_length:       float = 0.0

# ── 進場 ──────────────────────────────────────────────────────────────────────
func enter(_prev: StringName) -> void:
	elapsed            = 0.0
	attack_buffer_left = 0.0
	var vs        := player as VsPlayer
	var anim_name := "air_attack_%d" % combo_step

	vs.can_combo = false
	_reset_hitboxes(vs)
	vs.anim_player.play(anim_name)
	_anim_length = vs.anim_player.get_animation(anim_name).length

	vs.mark_in_combat()

# ── 每幀更新 ──────────────────────────────────────────────────────────────────
func physics_update(delta: float, input: InputState) -> StringName:
	elapsed += delta
	var vs := player as VsPlayer

	# 攻擊輸入緩衝，跟地面 VsAttack 同一套做法
	if input.attack:
		attack_buffer_left = ATTACK_BUFFER
	elif attack_buffer_left > 0.0:
		attack_buffer_left = maxf(attack_buffer_left - delta, 0.0)

	# 落地立刻收招：空中連段不能延續到地面，直接走恢復狀態判斷
	if _grounded():
		combo_step = 1
		return _recovery_transition(input)

	# ── 打斷優先級 ──────────────────────────────────────────────────────────
	# 1. 衝刺取消：任何時點可施放（規則：衝刺可打斷任何非受擊動作），空中本來
	#    就可以衝刺，跟 VsJump/VsFall 的入口一致
	if input.dodge and vs.use_dash_energy(30.0):
		return &"vsdodge"

	# 2. 防禦：規則明講空中不能防禦，這裡不做地面 VsAttack 那樣的分支

	# 3. 武藝取消：權限僅次衝刺、不受連段窗限制——武藝系統實作時接在這裡

	# 4. 連段派生：窗口開啟且有緩衝輸入 → 立刻取消剩餘動畫接下一段
	if vs.can_combo and attack_buffer_left > 0.0 and combo_step < MAX_COMBO:
		combo_step += 1
		enter(&"vsairattack")   # 直接重啟，繞過防重入
		return &""

	player.velocity.x = move_toward(player.velocity.x, 0.0, IMPULSE_FRICTION * delta)
	_apply_gravity(delta)

	# 動畫結束（末段或窗口內沒按 → 收招，此時必定還在空中，落地判斷在上面已擋過）
	if elapsed >= _anim_length:
		combo_step = 1
		return &"vsfall"

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
		_anim_length = vs.anim_player.get_animation("air_attack_%d" % combo_step).length

func sync_anim() -> void:
	var vs := player as VsPlayer
	vs.anim_player.play("air_attack_%d" % combo_step)
	vs.anim_player.seek(elapsed, true)
