class_name Art_Clotty_3
extends VsMartialArt
## 普通攻擊，比照主遊戲 Art_Katana_3：單發、可在空中施放，沒有其他特點——
## 主遊戲原版還有「破防+世界時緩」演出，但 VsMods 明確禁用 time_scale 時停
## （見 CLAUDE.md 確定性規則），使用者也說這招「沒有其他特點，只要動畫過來
## 就好」，這裡直接跳過，單純當一般攻擊處理。
## ⚠ 2026-07-19 空中重力手感統一：原本套用 0.25 倍重力（近零滯空，照搬主遊戲
## air_skill_gravity_rate），改成跟 4 號同一套「完全無視重力」（比照
## Art_Clotty_4.gd 的最終定案）——使用者要求 3、5 號也比照 4 號的做法。
## `art_3` 動畫軌道上有多顆 strike_impulse（-1000~600 不等，比照主遊戲原始數值），
## 跟地面 VsAttack 同一套理由：要用 IMPULSE_FRICTION（比一般移動摩擦力強上
## 近 10 倍）才煞得住，不然這招的衝力會飛超遠。

const IMPULSE_FRICTION: float = 8750.0

func _init() -> void:
	art_name       = "武藝三"
	energy_cost    = 50.0
	can_use_in_air = true

var _anim_length: float = 0.0

func enter(_prev: StringName) -> void:
	super.enter(_prev)
	var vs := player as VsPlayer
	_reset_hitbox(vs)
	player.velocity.x = 0.0
	if not _grounded():
		player.velocity.y = 0.0   # 無視重力：懸空施放，不用起跳推力
	vs.anim_player.play("art_3")
	_anim_length = vs.anim_player.get_animation("art_3").length
	vs.mark_in_combat()

func physics_update(delta: float, input: InputState) -> StringName:
	elapsed += delta
	var vs := player as VsPlayer
	# 衝刺取消：任何時點都適用（全域規則：衝刺可打斷任何非受擊動作）——之前
	# 漏加，這招（跟其他幾支武藝）按了衝刺鍵完全沒反應
	if input.dodge and vs.use_dash_energy(30.0):
		return &"vsdodge"
	player.velocity.x = move_toward(player.velocity.x, 0.0, IMPULSE_FRICTION * delta)
	if not _grounded():
		player.velocity.y = 0.0   # 無視重力：全程原地懸空，不套用任何重力係數

	if elapsed >= _anim_length:
		return _recovery_transition(input)
	return &""

func exit() -> void:
	var vs := player as VsPlayer
	var hb := vs.get_node_or_null("Graphics/HitboxArt3") as VsHitbox
	# sticky（連擊還沒打完）交給它自己跑完，不強制關閉，見 VsHitbox.close_on_state_exit()
	if is_instance_valid(hb):
		hb.close_on_state_exit()

func _reset_hitbox(vs: VsPlayer) -> void:
	var hb := vs.get_node_or_null("Graphics/HitboxArt3") as VsHitbox
	if is_instance_valid(hb):
		hb.monitoring = false
		hb.reset_hits()

func sync_anim() -> void:
	var vs := player as VsPlayer
	vs.anim_player.play("art_3")
	vs.anim_player.seek(elapsed, true)
