class_name VsHurt
extends VsPlayerState
## 受擊硬直狀態
## 硬直結束後：落地屬性攻擊（y=0 擊退）→ VsKnockdown（倒地）；
## 否則仍在空中→ VsFall；落地→ VsIdle
##
## 受擊動畫在 "hurt"/"hurt_2" 間隨機挑一支播（全角色通用視覺變化）。這裡用
## 未共享種子的 randi() 是安全的：硬直時長固定讀 queued_hitstun（hitbox 決定，
## 跟播哪支動畫無關，見 physics_update 的 elapsed>=hitstun_time），選哪支純粹
## 是外觀，不影響任何會進 checksum 的模擬數值——跟 vfx_spark() 的隨機火花偏移
## 同一類「純視覺，兩端各自算不用同步」。選擇結果存進 _anim_name 並隨快照
## save/restore（跟 hitstun_time/knockdown_after 同待遇）：只在 enter() 骰一次、
## 之後 rollback 的 sync_anim() 一律沿用同一支，避免同一次硬直中途因為
## resync 重骰而在畫面上「跳」成另一個變體。角色還沒補 "hurt_2" 素材時自動
## 退回單一 "hurt"，不會因為缺動畫而報錯。

var elapsed: float          = 0.0
var hitstun_time: float     = 0.4
var knockdown_after: bool   = false   # 落地屬性（y=0）：硬直結束後進倒地
var _anim_name: String      = "hurt"

func enter(_prev: StringName) -> void:
	elapsed      = 0.0
	var vs       := player as VsPlayer
	hitstun_time = vs.queued_hitstun
	knockdown_after = vs.queued_knockdown
	vs.queued_knockdown = false
	_anim_name = "hurt_2" if (vs.anim_player.has_animation("hurt_2") and randi() % 2 == 0) else "hurt"
	vs.anim_player.play(_anim_name)
	# 不給任何無敵：硬直期間本來就該被連段打中；同一攻擊窗的重複命中由
	# hitbox.has_hit 防（快照安全），不靠無敵

func physics_update(delta: float, input: InputState) -> StringName:
	elapsed += delta
	# 受身：無法操作期間唯一能做的事，按技能鍵即可（次數用完 try_ukemi() 自己
	# 擋，這裡不用另外檢查）——見 VsPlayer.try_ukemi() 說明。成功觸發立刻打斷
	# 硬直、接回自由操作（不是單純疊霸體讓硬直照跑完，使用者明確要求跟
	# VsLaunched 一致的「立刻取消」）
	var vs := player as VsPlayer
	if input.skill and vs.try_ukemi():
		player.velocity.x = 0.0
		return _recovery_transition(input)
	# 摩擦只在貼地時吃（擦地滑行）；空中保留水平動量，擊退才會走出弧線
	if _grounded():
		player.velocity.x = move_toward(player.velocity.x, 0.0, vs.friction * 1.5 * delta)
	_apply_gravity(delta)
	if elapsed >= hitstun_time:
		if knockdown_after:
			return &"vsknockdown"
		return _recovery_transition(input)   # 支援跑步預輸入
	return &""

func save_state() -> Dictionary:
	return {"elapsed": elapsed, "hitstun": hitstun_time, "kd": knockdown_after, "anim": _anim_name}

func restore_state(d: Dictionary) -> void:
	elapsed         = d.get("elapsed", 0.0)
	hitstun_time    = d.get("hitstun",  0.4)
	knockdown_after = d.get("kd", false)
	_anim_name      = d.get("anim", "hurt")

func sync_anim() -> void:
	var vs := player as VsPlayer
	vs.anim_player.play(_anim_name)
	vs.anim_player.seek(elapsed, true)
