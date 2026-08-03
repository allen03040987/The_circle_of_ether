class_name Art_Naihe_3
extends VsMartialArt
## 移植自奈何橋 Boss 的 attack_7——原版是「黃圈技」（1.44s 前搖＋彈反窗，
## 能被特定攻擊破解），使用者明確表示這次就是普通的招式，沒啥機制，不用
## 移植彈反窗。單發，`Graphics/HitboxArt3`（Naihe 場景複製自 Clotty 時留下、
## 本來沒被引用的節點）扛判定，動畫換成 `art_3`（attack_7 素材）。

const IMPULSE_FRICTION: float = 8750.0

func _init() -> void:
	art_name       = "武藝三"
	energy_cost    = 40.0
	can_use_in_air = false

var _anim_length: float = 0.0

func enter(_prev: StringName) -> void:
	super.enter(_prev)
	var vs := player as VsPlayer
	_reset_hitbox(vs)
	player.velocity.x = 0.0
	vs.anim_player.play("art_3")
	_anim_length = vs.anim_player.get_animation("art_3").length
	vs.mark_in_combat()

func physics_update(delta: float, input: InputState) -> StringName:
	elapsed += delta
	var vs := player as VsPlayer
	if input.dodge and vs.use_dash_energy(30.0):
		return &"vsdodge"
	player.velocity.x = move_toward(player.velocity.x, 0.0, IMPULSE_FRICTION * delta)

	if elapsed >= _anim_length:
		return _recovery_transition(input)
	return &""

func exit() -> void:
	var vs := player as VsPlayer
	var hb := vs.get_node_or_null("Graphics/HitboxArt3") as VsHitbox
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
