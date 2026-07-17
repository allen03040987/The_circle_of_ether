class_name VsAirAttack
extends VsPlayerState
## 空中普攻連段狀態（3 段，動畫時間軸/hitbox 數值移植自主遊戲 Katana air_light_1~3）
## 跟地面 VsAttack 同一套資料驅動模式：時間點在 air_attack_1~3 動畫軌道
## （`.:can_combo` 連段窗口、`Graphics/HitboxAirN:monitoring` 判定框開關），
## 判定框大小/位置/傷害/硬直/擊退在每招一顆的 HitboxAir1~3 節點（VsHitbox
## @export，編輯器直接調），跟地面 HitboxA1~5 是同一個 `VsPlayer.hitboxes`
## 陣列（`_ready()` 通用收集 Graphics 底下所有 VsHitbox），不用另外的集合。
##
## 重力完全比照主遊戲 Katana.gd：第 1/2 段吃一般重力，只有第 3 段（終結技，
## 對應主遊戲 combo_step==13）套用「近零重力滯空」（GRAVITY * 0.1 * delta，
## 原樣照搬 `new_y += player.default_gravity * 0.1 * delta`）。
## ⚠ 主遊戲同一招看似還有「延遲上勾噴射」，但那其實是另一招（combo_step==23，
## 地面戰技昇龍斬）的效果，跟 air_light_1~3 完全無關，不是漏移植。
## 落地當幀立刻收招：空中連段不能延續到地面。
## 每次跳躍只能觸發一輪空中普攻（`VsPlayer.air_attack_used`，落地時歸零，比照
## 主遊戲 `air_attack_locked`）——進場檢查在 VsJump/VsFall，這裡只負責在真正
## 開始新的一輪時把旗標設起來。
## 上升推力：主遊戲 `_play_air_step()` 在**每一段**觸發當下都直接
## `player.velocity.y = air_thrust_force`（= -150.0，往上），不是只有第一段——
## 這裡在 `enter()` 原樣照搬，讓連段每一下都會把角色往上頂一點，是空戰連段
## 手感的一部分，別誤植成只在第一段生效。

const ATTACK_BUFFER:    float = 0.2
const MAX_COMBO:        int   = 3
# 攻擊期間水平減速率，跟地面 VsAttack 同一套理由：strike_impulse 的前衝力道
# 要靠這麼強的摩擦力才煞得住，一般移動摩擦力（900）會飛太遠。
const IMPULSE_FRICTION: float = 8750.0
# 每段起手瞬間的上升推力，比照主遊戲 Katana.gd 的 air_thrust_force（-150.0）
const AIR_THRUST_FORCE: float = -150.0

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

	vs.air_attack_used = true
	vs.can_combo = false
	player.velocity.y = AIR_THRUST_FORCE
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

	# 3. 武藝取消：權限僅次衝刺、不受連段窗限制（是否能在空中放由該武藝自己的
	#    can_use_in_air 決定，_check_art_cast 內部已經檢查過）
	var art_transition := _check_art_cast(input)
	if art_transition != &"":
		return art_transition

	# 4. 連段派生：窗口開啟且有緩衝輸入 → 立刻取消剩餘動畫接下一段
	if vs.can_combo and attack_buffer_left > 0.0 and combo_step < MAX_COMBO:
		combo_step += 1
		enter(&"vsairattack")   # 直接重啟，繞過防重入
		return &""

	player.velocity.x = move_toward(player.velocity.x, 0.0, IMPULSE_FRICTION * delta)
	if combo_step == 3:
		player.velocity.y += GRAVITY * 0.1 * delta   # 第 3 段近零重力滯空
	else:
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
