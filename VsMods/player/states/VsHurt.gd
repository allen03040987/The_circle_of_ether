class_name VsHurt
extends VsPlayerState
## 受擊硬直狀態
## 硬直結束後：落地屬性攻擊（y=0 擊退）→ VsKnockdown（倒地）；
## 否則仍在空中→ VsFall；落地→ VsIdle

var elapsed: float          = 0.0
var hitstun_time: float     = 0.4
var knockdown_after: bool   = false   # 落地屬性（y=0）：硬直結束後進倒地

func enter(_prev: StringName) -> void:
	elapsed      = 0.0
	var vs       := player as VsPlayer
	hitstun_time = vs.queued_hitstun
	knockdown_after = vs.queued_knockdown
	vs.queued_knockdown = false
	vs.anim_player.play("hurt")
	# 不給任何無敵：硬直期間本來就該被連段打中；同一攻擊窗的重複命中由
	# hitbox.has_hit 防（快照安全），不靠無敵

func physics_update(delta: float, input: InputState) -> StringName:
	elapsed += delta
	# 摩擦只在貼地時吃（擦地滑行）；空中保留水平動量，擊退才會走出弧線
	if _grounded():
		player.velocity.x = move_toward(player.velocity.x, 0.0, FRICTION * 1.5 * delta)
	_apply_gravity(delta)
	if elapsed >= hitstun_time:
		if knockdown_after:
			return &"vsknockdown"
		return _recovery_transition(input)   # 支援跑步預輸入
	return &""

func save_state() -> Dictionary:
	return {"elapsed": elapsed, "hitstun": hitstun_time, "kd": knockdown_after}

func restore_state(d: Dictionary) -> void:
	elapsed         = d.get("elapsed", 0.0)
	hitstun_time    = d.get("hitstun",  0.4)
	knockdown_after = d.get("kd", false)

func sync_anim() -> void:
	var vs := player as VsPlayer
	vs.anim_player.play("hurt")
	vs.anim_player.seek(elapsed, true)
