class_name VsKnockdown
extends VsPlayerState
## 倒地（落地）狀態
## 進入路徑：(1) 落地屬性攻擊 y=0 → VsHurt 硬直結束後進入；
##           (2) 落地屬性攻擊 y<0 → VsLaunched 落地瞬間進入（保留水平動量）。
## 規則：期間無法操作；只有 can_hit_downed（OTG）的攻擊打得到（vs_world 偵測層擋）；
## 真正貼地那一刻 → 進入無敵直到起身 + 彈起一次；
## 二次落地 → 直接接起身動畫（VsGetup 會給精確的 2s 無敵）。
## 貼地摩擦隨貼地時間漸增：剛貼地幾乎不減速（保留滑行慣性），越貼越黏，不會瞬間黏住。

const BOUNCE_VELOCITY:    float = -160.0  # 彈起初速（px/s，向上）
const FRICTION_RAMP_TIME: float = 0.4     # 貼地摩擦從 0 漸增到全值所需秒數
# 「無敵直到起身」：用足夠罩住整段彈起的時長，進 VsGetup 時會被覆寫成精確的 2s
const INVINCIBLE_COVER:   float = 10.0

var elapsed:      float = 0.0
var bounced:      bool  = false   # 已彈起（true 後再次貼地即起身）
var _ground_time: float = 0.0     # 累計貼地時間（摩擦漸增用）

func enter(_prev: StringName) -> void:
	elapsed      = 0.0
	bounced      = false
	_ground_time = 0.0
	(player as VsPlayer).anim_player.play("launched")   # 躺地循環動畫

func save_state() -> Dictionary:
	return {"elapsed": elapsed, "bnc": bounced, "gt": _ground_time}

func restore_state(d: Dictionary) -> void:
	elapsed      = d.get("elapsed", 0.0)
	bounced      = d.get("bnc", false)
	_ground_time = d.get("gt", 0.0)

func sync_anim() -> void:
	(player as VsPlayer).anim_player.play("launched")

func physics_update(delta: float, _input: InputState) -> StringName:
	elapsed += delta
	var vs := player as VsPlayer
	if _grounded():
		_ground_time += delta
		# 摩擦漸增（貼地才吃；空中保留完整動量）
		var ramp := minf(_ground_time / FRICTION_RAMP_TIME, 1.0)
		player.velocity.x = move_toward(player.velocity.x, 0.0, FRICTION * 1.5 * ramp * delta)
		if not bounced:
			# 真正到地上：無敵直到起身 + 彈起一次（水平動量保留，彈出去的弧線）
			bounced = true
			vs.invincible_time_left = maxf(vs.invincible_time_left, INVINCIBLE_COVER)
			player.velocity.y = BOUNCE_VELOCITY
		else:
			player.velocity.y = 0.0
			return &"vsgetup"   # 二次落地：直接接起身
	else:
		_apply_gravity(delta)
	return &""
