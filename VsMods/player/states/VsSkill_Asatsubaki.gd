class_name VsSkill_Asatsubaki
extends VsPlayerState
## Asatsubaki 專屬技能——血影召喚／附身（見 CLAUDE.md「VsMods Asatsubaki
## 血影機制」）。不繼承 VsSkill.gd：行為跟一般技能（單發強破霸攻擊）完全
## 不同，硬繼承沒有意義。由 VsPlayer._load_skill() 動態換掉靜態的 VsSkill
## 節點，`transition_to(&"vsskill")` 的呼叫端完全不用跟著改。
##
## 按技能鍵的效果依 vs.shadow 是否存在分兩路：
## - 不存在：扣血召喚一顆血影（vs_world.spawn_blood_shadow()），播召喚動畫，
##   動畫播完照一般技能收尾（_recovery_transition()）。
## - 已存在：不播任何動畫，立刻把操控權轉移給血影（vs.is_possessing=true），
##   角色本體凍結在 vsidle——之後每幀的操控/長按銷毀/受擊強制收回都在
##   VsPlayer._apply_possession_input()/_recall_shadow() 處理，這支腳本
##   之後不會再被 tick（apply_input() 開頭就短路掉了，見 VsPlayer.gd）。
##
## ⚠ 骨架先行：召喚動畫目前借 idle 圖頂位（跟 VsSkill.gd 當初同一個慣例），
## 使用者之後自己換成正式動畫；換圖後 _anim_length 照動畫軌道自動抓，不用
## 改這支程式碼。

const SUMMON_COST: float = 150.0
const IMPULSE_FRICTION: float = 8750.0

var elapsed:      float = 0.0
var _anim_length: float = 0.0
var _is_transfer: bool  = false   # 這次施放是不是「轉移操控權」（不是召喚）

func enter(_prev: StringName) -> void:
	elapsed = 0.0
	var vs := player as VsPlayer

	if is_instance_valid(vs.shadow):
		# 已經有血影：立刻轉移操控權，不播動畫、不消耗任何東西。
		# 在 enter() 尾端呼叫 transition_to() 是巢狀轉場——VsAttack 的連段延續
		# 已經有「呼叫 enter() 繞過防重入鎖」的先例，這裡是同一類手法：讓
		# current_state_name 正確落在 vsidle（角色本體待機的視覺/邏輯狀態），
		# 不是卡在這個過場節點上。
		_is_transfer = true
		vs.is_possessing  = true
		vs._skill_hold_time = 0.0
		vs._skill_armed    = false   # 這次按壓要先放開過一次才開始認新的按壓，見 VsPlayer._apply_possession_input()
		vs.state_machine.transition_to(&"vsidle")
		return

	_is_transfer = false
	player.velocity.x = 0.0
	vs.take_damage(SUMMON_COST)
	var vw := vs.get_parent()
	if vw and vw.has_method("spawn_blood_shadow"):
		vs.shadow = vw.spawn_blood_shadow(vs)
	vs.anim_player.play("skill")
	_anim_length = vs.anim_player.get_animation("skill").length
	vs.mark_in_combat()

func physics_update(delta: float, input: InputState) -> StringName:
	if _is_transfer:
		return &""   # 轉移分支已經在 enter() 轉場走了，這裡不會真的被 tick 到
	elapsed += delta
	var vs := player as VsPlayer

	if input.dodge and vs.use_dash_energy(30.0):
		return &"vsdodge"

	if _grounded():
		player.velocity.x = move_toward(player.velocity.x, 0.0, IMPULSE_FRICTION * delta)
	else:
		_apply_gravity(delta)

	if elapsed >= _anim_length:
		return _recovery_transition(input)
	return &""

func save_state() -> Dictionary:
	return {"elapsed": elapsed, "xfer": _is_transfer}

func restore_state(d: Dictionary) -> void:
	elapsed     = d.get("elapsed", 0.0)
	_is_transfer = d.get("xfer", false)
	var vs := player as VsPlayer
	if is_instance_valid(vs) and vs.anim_player.has_animation("skill"):
		_anim_length = vs.anim_player.get_animation("skill").length

func sync_anim() -> void:
	if _is_transfer:
		return
	var vs := player as VsPlayer
	vs.anim_player.play("skill")
	vs.anim_player.seek(elapsed, true)
