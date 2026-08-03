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
## 播完（_in_start_anim 變 false）才算「真正到地上」，觸發無敵。此判定對兩條
## 進入路徑（地面硬直/空中擊飛落地）都適用。
##
## ⚠ 2026-07-27：新增 launched_3（躺平動畫），插在「真正到地上」跟「彈起」
## 之間——原本 launched_start 播完的同一幀就立刻彈起（幾乎沒有停留時間），
## 使用者要求改成：launched_start（下墜→倒地過場）→ launched_3（躺平，停留
## launched_3 自己的動畫長度）→ launched（彈起後的循環動畫，離地那一刻換回）
## → 二次落地 → VsGetup 播 launched_2。無敵一樣在 launched_start 播完的那一刻
## 觸發（不延後到彈起才給），只是彈起本身現在會晚一點才發生。**使用者要記得
## 在角色的動畫庫（ClottyAnimLib.tres/NaiheAnimLib.tres）加一支叫 "launched_3"
## 的動畫，沒有這支動畫的話 get_animation() 會回傳 null 導致報錯**。
##
## 貼地摩擦隨貼地時間漸增：剛貼地幾乎不減速（保留滑行慣性），越貼越黏，不會瞬間黏住。
##
## ⚠ 2026-07-30：敗北演出——若這次倒地是致命一擊（VsPlayer.is_defeated，
## VsRoundManager._tick_fighting() 死亡當下設定），二次落地時不再接
## &"vsgetup"（起身），改成停在原地播 LYING_ANIM（launched_3）定格，見下面
## physics_update() 的 bounced 分支。非致命的一般倒地（回合還沒結束）行為
## 完全不變，照舊接起身。硬直中被打死（VsHurt，沒進過這個狀態）走的是另一條
## 路，見 VsDefeated.gd。

const START_ANIM: StringName = &"launched_start"
const LYING_ANIM: StringName = &"launched_3"
const LOOP_ANIM:  StringName = &"launched"

const BOUNCE_VELOCITY:    float = -160.0  # 彈起初速（px/s，向上）
const FRICTION_RAMP_TIME: float = 0.4     # 貼地摩擦從 0 漸增到全值所需秒數
# 「無敵直到起身」：用足夠罩住整段彈起的時長，進 VsGetup 時會被覆寫成精確的 2s
const INVINCIBLE_COVER:   float = 10.0

var elapsed:           float = 0.0
var bounced:           bool  = false   # 已彈起（true 後再次貼地即起身）
var _ground_time:      float = 0.0     # 累計貼地時間（摩擦漸增用）
var _in_start_anim:    bool  = true    # 是否還在播 launched_start 過場
var _in_lying_anim:    bool  = false   # 是否還在播 launched_3 躺平動畫
var _start_anim_length: float = 0.0    # launched_start 總長（enter/restore 時讀取）
var _lying_anim_length: float = 0.0    # launched_3 總長（enter/restore 時讀取）

func enter(_prev: StringName) -> void:
	elapsed        = 0.0
	bounced        = false
	_ground_time   = 0.0
	_in_start_anim = true
	_in_lying_anim = false
	var vs := player as VsPlayer
	vs.anim_player.play(START_ANIM)
	_start_anim_length = vs.anim_player.get_animation(START_ANIM).length
	_lying_anim_length = vs.anim_player.get_animation(LYING_ANIM).length

func save_state() -> Dictionary:
	return {
		"elapsed": elapsed,
		"bnc":     bounced,
		"gt":      _ground_time,
		"ista":    _in_start_anim,
		"ilying":  _in_lying_anim,
	}

func restore_state(d: Dictionary) -> void:
	elapsed        = d.get("elapsed", 0.0)
	bounced        = d.get("bnc",     false)
	_ground_time   = d.get("gt",      0.0)
	_in_start_anim = d.get("ista",    true)
	_in_lying_anim = d.get("ilying",  false)
	var vs := player as VsPlayer
	if is_instance_valid(vs):
		_start_anim_length = vs.anim_player.get_animation(START_ANIM).length
		_lying_anim_length = vs.anim_player.get_animation(LYING_ANIM).length

func sync_anim() -> void:
	var vs := player as VsPlayer
	if _in_start_anim:
		vs.anim_player.play(START_ANIM)
		vs.anim_player.seek(elapsed, true)
	elif _in_lying_anim:
		vs.anim_player.play(LYING_ANIM)
		vs.anim_player.seek(elapsed - _start_anim_length, true)
	else:
		vs.anim_player.play(LOOP_ANIM)

func physics_update(delta: float, _input: InputState) -> StringName:
	elapsed += delta
	var vs := player as VsPlayer

	if _in_start_anim and elapsed >= _start_anim_length:
		# launched_start 過場播完才算「真正到地上」：無敵直到起身從這一刻開始，
		# 换播 launched_3（躺平），彈起本身要等 launched_3 也播完才觸發
		# （見下面 _in_lying_anim 那個判斷）。
		_in_start_anim = false
		_in_lying_anim = true
		vs.anim_player.play(LYING_ANIM)
		vs.invincible_time_left = maxf(vs.invincible_time_left, INVINCIBLE_COVER)

	if _in_lying_anim and elapsed >= _start_anim_length + _lying_anim_length:
		_in_lying_anim = false
		vs.anim_player.play(LOOP_ANIM)

	if _grounded():
		_ground_time += delta
		# 摩擦漸增（貼地才吃；空中保留完整動量）
		var ramp := minf(_ground_time / FRICTION_RAMP_TIME, 1.0)
		player.velocity.x = move_toward(player.velocity.x, 0.0, vs.friction * 1.5 * ramp * delta)
		if bounced:
			player.velocity.y = 0.0
			if vs.is_defeated:
				# 敗北（這下擊飛是致命一擊）：不接起身，改停在原地播 launched_3
				# 躺平定格——使用者要求「最後的起身動畫 launched_2 改為
				# launched_3」，即整段落地行程照舊，只有終點從「站起來」換成
				# 「躺著不起來」。只在真正切換的那一刻播放一次，避免每幀重播。
				if vs.anim_player.current_animation != LYING_ANIM:
					vs.anim_player.play(LYING_ANIM)
				vs.defeat_settled = true
				return &""
			return &"vsgetup"   # 二次落地：直接接起身
		elif not _in_start_anim and not _in_lying_anim:
			# launched_3 躺平動畫也播完才真的彈起（水平動量保留，彈出去的弧線）。
			# launched_start／launched_3 播放中都維持躺地、不彈起，這裡不做任何事。
			bounced = true
			player.velocity.y = BOUNCE_VELOCITY
	else:
		_apply_gravity(delta)
	return &""
