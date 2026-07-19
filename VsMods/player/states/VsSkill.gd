class_name VsSkill
extends VsPlayerState
## 技能狀態——規則：具有強破霸手段的招式。單發（不是連段），地面限定
## （規則沒說技能能在空中放，比照防禦的保守預設；之後要開放空中再說）。
## 資料驅動同一套模式：時間點在 `skill` 動畫軌道（`Graphics/HitboxSkill:monitoring`
## 判定框開關），判定框大小/位置/傷害/硬直/擊退在 `HitboxSkill` 節點的 @export，
## 「強破霸」這個技能定義特徵直接寫在該節點的 `break_level` 上（編輯器可調，
## 但技能存在的意義就是要能破強霸體，別把它調回 NONE）。
##
## ⚠ 骨架先行：`skill` 動畫目前只是借 idle 的圖頂一格佔位（見 VsPlayer.tscn
## 的 Anim_skill），使用者會自己換成 `Katana Skill.png` 對應的那段動畫——換圖
## 之後，`_anim_length`／hitbox 開關窗都是照動畫軌道自動抓，不用改這支程式碼。

const ATTACK_BUFFER: float = 0.2   # 技能輸入緩衝，跟普攻同一套設計
const IMPULSE_FRICTION: float = 8750.0

var elapsed:            float = 0.0
var attack_buffer_left: float = 0.0
var _anim_length:       float = 0.0

func enter(_prev: StringName) -> void:
	elapsed            = 0.0
	attack_buffer_left = 0.0
	var vs := player as VsPlayer

	_reset_hitbox(vs)
	player.velocity.x = 0.0   # 起手清殘留動量，前衝感交給 strike_impulse 動畫軌道
	vs.anim_player.play("skill")
	_anim_length = vs.anim_player.get_animation("skill").length

	vs.mark_in_combat()

func physics_update(delta: float, input: InputState) -> StringName:
	elapsed += delta
	var vs := player as VsPlayer

	if input.skill:
		attack_buffer_left = ATTACK_BUFFER
	elif attack_buffer_left > 0.0:
		attack_buffer_left = maxf(attack_buffer_left - delta, 0.0)

	# ── 打斷優先級（跟 VsAttack 同一套順位）────────────────────────────────
	# 1. 衝刺取消：任何時點可施放
	if input.dodge and vs.use_dash_energy(30.0):
		return &"vsdodge"

	# 2. 防禦取消：地面限定
	if input.guard and _grounded():
		return &"vsguard"

	# 3. 武藝取消：權限僅次衝刺/防禦（規則明講的是「可打斷普攻」，這裡比照同一
	#    順位一併開放打斷技能——武藝是主要攻擊手段，跟普攻同類的可打斷邏輯）
	var art_transition := _check_art_cast(input)
	if art_transition != &"":
		return art_transition

	if _grounded():
		player.velocity.x = move_toward(player.velocity.x, 0.0, IMPULSE_FRICTION * delta)
	else:
		_apply_gravity(delta)

	if elapsed >= _anim_length:
		return _recovery_transition(input)

	return &""

func exit() -> void:
	var vs := player as VsPlayer
	# sticky（連擊還沒打完）交給它自己跑完，不強制關閉，見 VsHitbox.close_on_state_exit()
	if is_instance_valid(vs.skill_hitbox):
		vs.skill_hitbox.close_on_state_exit()

func _reset_hitbox(vs: VsPlayer) -> void:
	if is_instance_valid(vs.skill_hitbox):
		vs.skill_hitbox.monitoring = false
		vs.skill_hitbox.reset_hits()

func save_state() -> Dictionary:
	return {
		"elapsed": elapsed,
		"buf":     attack_buffer_left,
	}

func restore_state(d: Dictionary) -> void:
	elapsed            = d.get("elapsed", 0.0)
	attack_buffer_left = d.get("buf",     0.0)
	var vs := player as VsPlayer
	if is_instance_valid(vs):
		_anim_length = vs.anim_player.get_animation("skill").length

func sync_anim() -> void:
	var vs := player as VsPlayer
	vs.anim_player.play("skill")
	vs.anim_player.seek(elapsed, true)
