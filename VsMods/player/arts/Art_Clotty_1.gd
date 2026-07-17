class_name Art_Clotty_1
extends VsMartialArt
## 武藝範例（驗證框架跑得通用）：單發突刺，全程強霸體。
## 對應 VsGameManager.CLOTTY_ARTS 的 "Art_Clotty_1"，素材用
## `player/Katana/Art_Katana_1.png`（8 格突刺動作）。
##
## 這只是「證明框架管線通了」的範例，不是最終設計——energy_cost/傷害/
## armor_tier_override_strong 這些數值都只是合理預設，之後可以直接調整或
## 整支重寫，不用受這份範例的具體效果限制。

func _init() -> void:
	art_name    = "武藝一"
	energy_cost = 20.0
	armor_tier_override_strong = true   # 範例特意選強霸體，展示這個機制怎麼用

var _anim_length: float = 0.0

func enter(_prev: StringName) -> void:
	super.enter()
	var vs := player as VsPlayer
	_reset_hitbox(vs)
	player.velocity.x = 0.0
	vs.anim_player.play("art_1")
	_anim_length = vs.anim_player.get_animation("art_1").length
	vs.mark_in_combat()

func physics_update(delta: float, input: InputState) -> StringName:
	elapsed += delta
	if _grounded():
		player.velocity.x = move_toward(player.velocity.x, 0.0, FRICTION * delta)
	else:
		_apply_gravity(delta)

	if elapsed >= _anim_length:
		return _recovery_transition(input)
	return &""

func exit() -> void:
	_reset_hitbox(player as VsPlayer)

func _reset_hitbox(vs: VsPlayer) -> void:
	var hb := vs.get_node_or_null("Graphics/HitboxArt1") as VsHitbox
	if is_instance_valid(hb):
		hb.monitoring = false
		hb.reset_hits()

func sync_anim() -> void:
	var vs := player as VsPlayer
	vs.anim_player.play("art_1")
	vs.anim_player.seek(elapsed, true)
