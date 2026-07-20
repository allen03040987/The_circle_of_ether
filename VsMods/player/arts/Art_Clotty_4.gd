class_name Art_Clotty_4
extends VsMartialArt
## 普通攻擊，來源是主遊戲 Katana.gd 的重斬二段（DICT_HEAVY_ULT combo_step 22，
## "katana/heavy_2"），不是 Art_Katana_4.gd——同 Art_Clotty_6，這次直接抓武器
## 重攻擊的動畫/數值當武藝範本。沒有其他特點，8 段連擊、每段間隔 0.05s、
## sticky（主遊戲原本就是 sticky:true 的多次判定），數值原樣照搬。
##
## 使用者要求擴充：可在空中施放（can_use_in_air=true）——主遊戲 combo_step==22
## 完全沒有空戰版本，這是 VsMods 額外擴充的，不是移植。
##
## ⚠ 2026-07-18 手感調整史（最終定案：無視重力）：一開始無條件套用 0.1 倍重力
## →改成只在下墜階段套用滯空→改成跟第 1/2 段一樣的一般重力（配合加大起跳推力
## 補償）→使用者實測後都不滿意，最後直接要求**完全無視重力**：施放期間
## `velocity.y` 鎖定 0，全程原地懸空，不加、不減、不套用任何重力係數。因為
## 完全不會掉落，原本用來補償掉更快的起跳推力（`AIR_THRUST_FORCE`）已經沒有
## 意義，一併拿掉。

func _init() -> void:
	art_name       = "武藝四"
	energy_cost    = 30.0
	can_use_in_air = true

const IMPULSE_FRICTION: float = 8750.0

var _anim_length: float = 0.0

func enter(_prev: StringName) -> void:
	super.enter(_prev)
	var vs := player as VsPlayer
	_reset_hitbox(vs)
	player.velocity.x = 0.0
	if not _grounded():
		player.velocity.y = 0.0   # 無視重力：懸空施放，不用起跳推力
	vs.anim_player.play("art_4")
	_anim_length = vs.anim_player.get_animation("art_4").length
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
	var hb := vs.get_node_or_null("Graphics/HitboxArt4") as VsHitbox
	# sticky（連擊還沒打完）交給它自己跑完，不強制關閉——方向已經在第一下
	# 命中時鎖進 direction_override，見 VsHitbox.close_on_state_exit() 完整說明
	if is_instance_valid(hb):
		hb.close_on_state_exit()

func _reset_hitbox(vs: VsPlayer) -> void:
	var hb := vs.get_node_or_null("Graphics/HitboxArt4") as VsHitbox
	if is_instance_valid(hb):
		hb.monitoring = false
		hb.reset_hits()

func sync_anim() -> void:
	var vs := player as VsPlayer
	vs.anim_player.play("art_4")
	vs.anim_player.seek(elapsed, true)
