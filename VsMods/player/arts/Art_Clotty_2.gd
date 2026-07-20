class_name Art_Clotty_2
extends VsMartialArt
## 升龍——比照主遊戲 Art_Katana_2：起手 LAUNCH_START_TIME 秒後，短暫
## LAUNCH_DURATION 秒窗口把自身往前上方頂出去（時間/速度數值原樣照搬主遊戲
## launch_start_time/launch_duration/vertical_launch_speed/forward_launch_speed），
## 窗口結束後正常煞停+受重力。單發判定——主遊戲原版是 4 連段 sticky 多次判定，
## 但使用者說這招「也是普通的攻擊」，簡化成 VsHitbox 既有的單發 has_hit 判定即可。
## HitboxArt2 的 knockback.y < 0 + causes_knockdown=true 會讓中招對手直接進
## VsLaunched（擊飛/juggle），跟這招的「升龍」定位天然吻合，不用額外寫邏輯。
##
## ⚠ 在空中施放時打的是完全不同的另一招「降龍」——比照主遊戲同一個 combo_step
## 系統裡的「三段式下墜戰技」（combo_step 25 下墜前準備 → 26 下墜循環 → 27
## 落地），是主遊戲原版 air_heavy 的招式，不是升龍的空戰版本，只是共用同一個
## 武藝槽位施放。`enter()` 當下依 `_grounded()` 決定走地面（升龍）還是空中
## （降龍）分支，兩套物理/動畫/判定框完全獨立，只共用 elapsed/energy_cost 等
## 基底欄位。

const LAUNCH_START_TIME:     float = 0.1
const LAUNCH_DURATION:       float = 0.1
const VERTICAL_LAUNCH_SPEED: float = -650.0
const FORWARD_LAUNCH_SPEED:  float = 380.0

const IMPULSE_FRICTION: float = 8750.0
# 降龍起手瞬間的上升推力，比照主遊戲 air_thrust_force(-150) * 2.0
const AIR_ENTRY_THRUST: float = -300.0
# 下墜循環階段的固定下墜速度，原樣照搬主遊戲 combo_step==26 的 `new_y = 800.0`
const AIR_DIVE_SPEED:   float = 800.0
# 落地瞬間的震動強度，原樣照搬主遊戲落地時的 apply_camera_shake(25.0)
const LAND_SHAKE:        float = 25.0

enum AirStage { START, LOOP, LAND }

var _anim_length:      float = 0.0
var _launch_triggered: bool  = false
var _launch_timer:     float = 0.0

var is_air_mode: bool     = false
var air_stage:   AirStage = AirStage.START

func _init() -> void:
	art_name       = "武藝二"
	energy_cost    = 30.0
	can_use_in_air = true

func enter(_prev: StringName) -> void:
	super.enter(_prev)
	var vs := player as VsPlayer
	is_air_mode = not _grounded()
	if is_air_mode:
		_enter_air_start(vs)
	else:
		_reset_hitbox(vs)
		_launch_triggered = false
		_launch_timer     = 0.0
		vs.anim_player.play("art_2")
		_anim_length = vs.anim_player.get_animation("art_2").length
	vs.mark_in_combat()

func physics_update(delta: float, input: InputState) -> StringName:
	elapsed += delta
	var vs := player as VsPlayer

	# 衝刺取消：任何時點、地面/空中兩個分支都適用（全域規則：衝刺可打斷任何
	# 非受擊動作）——之前漏加，這招（跟其他幾支武藝）按了衝刺鍵完全沒反應
	if input.dodge and vs.use_dash_energy(30.0):
		return &"vsdodge"

	if is_air_mode:
		return _physics_air(delta, input, vs)

	if elapsed >= LAUNCH_START_TIME and not _launch_triggered:
		_launch_triggered = true
		_launch_timer     = LAUNCH_DURATION

	if _launch_triggered and _launch_timer > 0.0:
		_launch_timer -= delta
		player.velocity.y = VERTICAL_LAUNCH_SPEED
		player.velocity.x = vs.facing_dir * FORWARD_LAUNCH_SPEED
	elif player.velocity.y < 0.0:
		# 還在上升尾段：比照主遊戲用 2 倍重力快速煞停垂直速度
		player.velocity.x = move_toward(player.velocity.x, 0.0, vs.friction * 0.5 * delta)
		player.velocity.y = move_toward(player.velocity.y, 0.0, vs.gravity * 2.0 * delta)
	else:
		player.velocity.x = move_toward(player.velocity.x, 0.0, vs.friction * 0.5 * delta)
		player.velocity.y += vs.gravity * delta

	if elapsed >= _anim_length:
		return _recovery_transition(input)
	return &""

# ── 降龍（空中版）：下墜前準備 → 下墜循環 → 落地 ────────────────────────────
func _enter_air_start(vs: VsPlayer) -> void:
	air_stage = AirStage.START
	elapsed   = 0.0
	_reset_air_hitbox(vs)
	player.velocity.y = AIR_ENTRY_THRUST
	vs.anim_player.play("art_2_air_start")
	_anim_length = vs.anim_player.get_animation("art_2_air_start").length

func _enter_air_loop(vs: VsPlayer) -> void:
	air_stage = AirStage.LOOP
	elapsed   = 0.0
	var hb := vs.get_node_or_null("Graphics/HitboxArt2Air") as VsHitbox
	if is_instance_valid(hb):
		hb.monitoring = true   # 下墜循環判定：沒有動畫關閉 key，靠落地轉場/連擊用完關閉
	vs.anim_player.play("art_2_air_loop")
	_anim_length = vs.anim_player.get_animation("art_2_air_loop").length

func _enter_air_land(vs: VsPlayer) -> void:
	air_stage = AirStage.LAND
	elapsed   = 0.0
	# ⚠ 不能用 _reset_air_hitbox()（硬重置）——落地只是連段的第三個階段轉場，
	# sticky 連擊如果還沒打完（例如 5 下只中了 2 下）應該讓它照原節奏繼續跑
	# 完，不該一落地就被強制砍斷。用 close_on_state_exit()（尊重 sticky，只有
	# 沒開 sticky 或已經打完才關）——方向已經在第一下命中時鎖進
	# direction_override（見 VsPlayer._on_hurtbox_hurt()），落地後角色即使
	# 恢復自由操作，剩餘連擊的擊退方向也不會跟著亂跑。
	var hb := vs.get_node_or_null("Graphics/HitboxArt2Air") as VsHitbox
	if is_instance_valid(hb):
		hb.close_on_state_exit()
	vs.anim_player.play("art_2_air_land")
	_anim_length = vs.anim_player.get_animation("art_2_air_land").length
	vs.vfx_shake(LAND_SHAKE)

func _physics_air(delta: float, input: InputState, vs: VsPlayer) -> StringName:
	match air_stage:
		AirStage.START:
			player.velocity.x = move_toward(player.velocity.x, 0.0, IMPULSE_FRICTION * 0.2 * delta)
			player.velocity.y += vs.gravity * 0.5 * delta
			if elapsed >= _anim_length:
				_enter_air_loop(vs)
		AirStage.LOOP:
			player.velocity.x = move_toward(player.velocity.x, 0.0, IMPULSE_FRICTION * 0.5 * delta)
			player.velocity.y = AIR_DIVE_SPEED   # 固定下墜速度，不是加速度
			if _grounded():
				_enter_air_land(vs)
		AirStage.LAND:
			player.velocity.x = move_toward(player.velocity.x, 0.0, IMPULSE_FRICTION * delta)
			player.velocity.y = 0.0
			if elapsed >= _anim_length:
				return _recovery_transition(input)
	return &""

func exit() -> void:
	var vs := player as VsPlayer
	# sticky（連擊還沒打完）交給它自己跑完，不強制關閉——方向已經在第一下
	# 命中時鎖進 direction_override（見 VsPlayer._on_hurtbox_hurt()「多段連擊
	# 方向鎖定」），角色離開這招後即使自由移動，剩餘連擊的擊退方向也不會亂跑，
	# 見 VsHitbox.close_on_state_exit() 完整說明。
	var hb := vs.get_node_or_null("Graphics/HitboxArt2") as VsHitbox
	if is_instance_valid(hb):
		hb.close_on_state_exit()
	var hb_air := vs.get_node_or_null("Graphics/HitboxArt2Air") as VsHitbox
	if is_instance_valid(hb_air):
		hb_air.close_on_state_exit()

## enter() 用的硬重置——不管 sticky，一律清乾淨（新的一次施放不該繼承上一次
## 殘留的連擊進度），跟 exit() 的 close_on_state_exit() 是分開的兩種語意。
func _reset_hitbox(vs: VsPlayer) -> void:
	var hb := vs.get_node_or_null("Graphics/HitboxArt2") as VsHitbox
	if is_instance_valid(hb):
		hb.monitoring = false
		hb.reset_hits()

func _reset_air_hitbox(vs: VsPlayer) -> void:
	var hb := vs.get_node_or_null("Graphics/HitboxArt2Air") as VsHitbox
	if is_instance_valid(hb):
		hb.monitoring = false
		hb.reset_hits()

func save_state() -> Dictionary:
	var d := super.save_state()
	d["lt"]   = _launch_triggered
	d["ltm"]  = _launch_timer
	d["air"]  = is_air_mode
	d["astg"] = air_stage
	return d

func restore_state(d: Dictionary) -> void:
	super.restore_state(d)
	_launch_triggered = d.get("lt", false)
	_launch_timer     = d.get("ltm", 0.0)
	is_air_mode       = d.get("air", false)
	air_stage         = d.get("astg", AirStage.START)
	var vs := player as VsPlayer
	if is_instance_valid(vs):
		_anim_length = vs.anim_player.get_animation(_current_anim_name()).length

func sync_anim() -> void:
	var vs := player as VsPlayer
	vs.anim_player.play(_current_anim_name())
	vs.anim_player.seek(elapsed, true)

func _current_anim_name() -> String:
	if not is_air_mode:
		return "art_2"
	match air_stage:
		AirStage.START: return "art_2_air_start"
		AirStage.LOOP:  return "art_2_air_loop"
		AirStage.LAND:  return "art_2_air_land"
	return "art_2_air_start"
