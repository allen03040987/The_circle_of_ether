class_name Art_Clotty_6
extends VsMartialArt
## 普通攻擊，來源是主遊戲 Katana.gd 的重斬一段（DICT_HEAVY_ULT combo_step 21，
## "katana/heavy_1"），不是 Art_Katana_6.gd——使用者這次指定直接抓武器重攻擊
## 的動畫/數值當武藝範本。沒有其他特點，單純的地面連擊招式，3 段連擊、每段
## 間隔 0.1s、sticky（鎖定後不再檢查幾何重疊，主遊戲原本就是 sticky:true 的
## 多次判定），數值原樣照搬自 DICT_HEAVY_ULT。
##
## ⚠ 摩擦力不是滿檔 IMPULSE_FRICTION：主遊戲 Katana.gd 的 get_current_velocity()
## 對 combo_step==21 這招特別用 `base_friction * skill_neutral_friction_rate`
## （skill_neutral_friction_rate 預設 0.2，即只有一般攻擊摩擦力的 20%），跟
## combo_step==22（Art_Clotty_4 那招，滿檔 base_friction）不一樣——21 號這招
## 本來就設計成「衝力打出去後會拖著滑一段距離」，不是打完立刻煞停，之前誤用
## 滿檔摩擦力導致位移軌跡跟主遊戲對不上，已修正比照 0.2 倍率原樣照搬。

func _init() -> void:
	art_name    = "武藝六"
	energy_cost = 30.0

const IMPULSE_FRICTION: float = 8750.0
const FRICTION_RATE:    float = 0.2   # 比照主遊戲 skill_neutral_friction_rate

var _anim_length: float = 0.0

func enter(_prev: StringName) -> void:
	super.enter(_prev)
	var vs := player as VsPlayer
	_reset_hitbox(vs)
	player.velocity.x = 0.0
	vs.anim_player.play("art_6")
	_anim_length = vs.anim_player.get_animation("art_6").length
	vs.mark_in_combat()

func physics_update(delta: float, input: InputState) -> StringName:
	elapsed += delta
	var vs := player as VsPlayer
	# 衝刺取消：任何時點都適用（全域規則：衝刺可打斷任何非受擊動作）——之前
	# 漏加，這招（跟其他幾支武藝）按了衝刺鍵完全沒反應
	if input.dodge and vs.use_dash_energy(30.0):
		return &"vsdodge"
	if _grounded():
		player.velocity.x = move_toward(player.velocity.x, 0.0, IMPULSE_FRICTION * FRICTION_RATE * delta)
	else:
		_apply_gravity(delta)

	if elapsed >= _anim_length:
		return _recovery_transition(input)
	return &""

func exit() -> void:
	var vs := player as VsPlayer
	var hb := vs.get_node_or_null("Graphics/HitboxArt6") as VsHitbox
	# sticky（連擊還沒打完）交給它自己跑完，不強制關閉——方向已經在第一下
	# 命中時鎖進 direction_override，見 VsHitbox.close_on_state_exit() 完整說明
	if is_instance_valid(hb):
		hb.close_on_state_exit()

func _reset_hitbox(vs: VsPlayer) -> void:
	var hb := vs.get_node_or_null("Graphics/HitboxArt6") as VsHitbox
	if is_instance_valid(hb):
		hb.monitoring = false
		hb.reset_hits()

func sync_anim() -> void:
	var vs := player as VsPlayer
	vs.anim_player.play("art_6")
	vs.anim_player.seek(elapsed, true)
