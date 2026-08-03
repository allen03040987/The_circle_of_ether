class_name Art_Naihe_1
extends VsMartialArt
## 移植自奈何橋 Boss 的 attack_6（蔓延地刺）——單發施放，沒有玩家身上的
## hitbox，傷害完全來自動畫軌道排程生成的 VsGroundSpike（見
## VsPlayer.spawn_ground_spike()/vs_world.spawn_ground_spike()）。
## `art_1` 動畫上會排 5 個 spawn_ground_spike() Call Method key（間隔 0.25s，
## offset_x 依序 0/140/280/420/560，比照 Boss 原版 NaiheSpikeSpawner 的
## spawn_interval/spacing），跟原版差別只在：原版用 await 迴圈依序生成
## （VsMods 禁用，見確定性規則），這裡改成動畫軌道排程，效果一致但是確定性
## 安全，之後想調間距/時機直接在動畫面板改 key，不用碰這支腳本。

const IMPULSE_FRICTION: float = 8750.0

func _init() -> void:
	art_name       = "武藝一"
	energy_cost    = 40.0
	can_use_in_air = false

var _anim_length: float = 0.0

func enter(_prev: StringName) -> void:
	super.enter(_prev)
	var vs := player as VsPlayer
	player.velocity.x = 0.0
	vs.anim_player.play("art_1")
	_anim_length = vs.anim_player.get_animation("art_1").length
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

func sync_anim() -> void:
	var vs := player as VsPlayer
	vs.anim_player.play("art_1")
	vs.anim_player.seek(elapsed, true)
