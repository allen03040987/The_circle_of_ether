class_name VsKnockdown
extends VsPlayerState
## 倒地（落地）狀態
## 進入路徑：(1) 落地屬性攻擊 y=0 → VsHurt 硬直結束後進入；
##           (2) 落地屬性攻擊 y<0 → VsLaunched 落地瞬間進入（保留水平動量）。
## 規則：期間無法操作；「真正到地上」→ 進入無敵直到起身 + 彈起一次；
## 二次落地 → 直接接起身動畫（VsGetup 會給精確的 2s 無敵）。
##
## ⚠ 2026-07-18：VsMods 沒有任何「打不到擊飛/倒地目標」的命中限制欄位——
## 曾經做過 `VsHitbox.can_hit_downed`/`can_hit_launched`（比照 MUGEN 的 S/C/A
## 攻擊分類），使用者測試後決定整個拿掉，倒地流程完全靠自己的無敵/彈起時序
## 保護，不受任何攻擊屬性影響（任何攻擊都能命中，只是通常會被無敵擋掉）。
##
## ⚠「真正到地上」判定不能只看 _grounded()：地面硬直（y=0 擊退）進來的角色從
## 沒離地過，enter() 第一個 tick 就已經 _grounded()==true，若拿它當「真正到地上」
## 的判定，等於進場那一刻立刻觸發無敵+彈起，前面應該有的「剛落地、還沒無敵」
## 窗口長度會變成 0（實測 bug：曾誤以為彈跳邏輯壞了，其實是這段窗口被吃掉，角色
## 一落地就已經是彈起後下墜+無敵的畫面）。改綁定 launched_start 過場動畫：播放
## 期間（_in_start_anim）才是規則講的「落地期間」——躺著、無法操作、沒有無敵；
## 播完（_in_start_anim 變 false）才算「真正到地上」，觸發無敵+彈起。這樣視窗
## 長度直接等於 launched_start 的動畫長度，在編輯器調整動畫即可調視窗，不用
## 另外生一個數字常數。此判定對兩條進入路徑（地面硬直/空中擊飛落地）都適用。
##
## 貼地摩擦隨貼地時間漸增：剛貼地幾乎不減速（保留滑行慣性），越貼越黏，不會瞬間黏住。

const START_ANIM: StringName = &"launched_start"
const LOOP_ANIM:  StringName = &"launched"

const BOUNCE_VELOCITY:    float = -160.0  # 彈起初速（px/s，向上）
const FRICTION_RAMP_TIME: float = 0.4     # 貼地摩擦從 0 漸增到全值所需秒數
# 「無敵直到起身」：用足夠罩住整段彈起的時長，進 VsGetup 時會被覆寫成精確的 2s
const INVINCIBLE_COVER:   float = 10.0

var elapsed:           float = 0.0
var bounced:           bool  = false   # 已彈起（true 後再次貼地即起身）
var _ground_time:      float = 0.0     # 累計貼地時間（摩擦漸增用）
var _in_start_anim:    bool  = true    # 是否還在播 launched_start 過場
var _start_anim_length: float = 0.0    # launched_start 總長（enter/restore 時讀取）

func enter(_prev: StringName) -> void:
	elapsed        = 0.0
	bounced        = false
	_ground_time   = 0.0
	_in_start_anim = true
	var vs := player as VsPlayer
	vs.anim_player.play(START_ANIM)
	_start_anim_length = vs.anim_player.get_animation(START_ANIM).length

func save_state() -> Dictionary:
	return {
		"elapsed": elapsed,
		"bnc":     bounced,
		"gt":      _ground_time,
		"ista":    _in_start_anim,
	}

func restore_state(d: Dictionary) -> void:
	elapsed        = d.get("elapsed", 0.0)
	bounced        = d.get("bnc",     false)
	_ground_time   = d.get("gt",      0.0)
	_in_start_anim = d.get("ista",    true)
	var vs := player as VsPlayer
	if is_instance_valid(vs):
		_start_anim_length = vs.anim_player.get_animation(START_ANIM).length

func sync_anim() -> void:
	var vs := player as VsPlayer
	if _in_start_anim:
		vs.anim_player.play(START_ANIM)
		vs.anim_player.seek(elapsed, true)
	else:
		vs.anim_player.play(LOOP_ANIM)

func physics_update(delta: float, _input: InputState) -> StringName:
	elapsed += delta
	var vs := player as VsPlayer

	if _in_start_anim and elapsed >= _start_anim_length:
		_in_start_anim = false
		vs.anim_player.play(LOOP_ANIM)

	if _grounded():
		_ground_time += delta
		# 摩擦漸增（貼地才吃；空中保留完整動量）
		var ramp := minf(_ground_time / FRICTION_RAMP_TIME, 1.0)
		player.velocity.x = move_toward(player.velocity.x, 0.0, vs.friction * 1.5 * ramp * delta)
		if bounced:
			player.velocity.y = 0.0
			return &"vsgetup"   # 二次落地：直接接起身
		elif not _in_start_anim:
			# launched_start 過場播完才算「真正到地上」：無敵直到起身 + 彈起一次
			# （水平動量保留，彈出去的弧線）。播放中（_in_start_anim 仍 true）維持
			# 躺地、無無敵、只有 OTG 打得到的窗口，這裡不做任何事。
			bounced = true
			vs.invincible_time_left = maxf(vs.invincible_time_left, INVINCIBLE_COVER)
			player.velocity.y = BOUNCE_VELOCITY
	else:
		_apply_gravity(delta)
	return &""
