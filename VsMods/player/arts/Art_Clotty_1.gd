class_name Art_Clotty_1
extends VsMartialArt
## 逆鱗返——比照主遊戲 Art_Katana_1：原地格擋預備，`CHANNEL_DURATION` 秒內
## （START 前搖 + LOOP 循環都算判定區間）被攻擊命中就完全格擋、射出劍氣
## 反擊、獲得無敵；沒被打中則時間到自然收招（END）。
##
## ⚠ 唯一跟主遊戲不同的規則調整（使用者明確要求）：主遊戲原版完全格擋任何
## 攻擊，這裡改成只格擋「強破霸以下」的攻擊——銜接 VsMods 既有的 break_level
## 體質系統，STRONG_ARMOR_BREAK 等級的攻擊會直接穿透（見 try_parry()）。
## 格擋成功後的效果（劍氣反擊 + 無敵）跟主遊戲原版一樣，數值原樣照搬。

enum Stage { START, LOOP, COUNTER, END }

const CHANNEL_DURATION:            float = 2.0
const COUNTER_INVINCIBLE_DURATION: float = 1.0
const WAVE_FIRE_TIME:              float = 0.35
const COUNTER_DAMAGE:              float = 700.0
# 反擊動畫的 strike_impulse(-1200) 跟地面普攻同一套理由，要用這麼強的摩擦力
# 才煞得住——用一般移動摩擦力（VsPlayer.friction，預設 900）的話，同樣衝力會飛遠將近 10 倍。
const IMPULSE_FRICTION: float = 8750.0

var current_stage:  Stage = Stage.START
var channel_timer:  float = 0.0
var _anim_length:   float = 0.0

func _init() -> void:
	art_name    = "武藝一"
	energy_cost = 30.0

func enter(_prev: StringName) -> void:
	super.enter(_prev)
	var vs := player as VsPlayer
	current_stage = Stage.START
	channel_timer = CHANNEL_DURATION
	player.velocity.x = 0.0
	vs.anim_player.play("art_1_start")
	_anim_length = vs.anim_player.get_animation("art_1_start").length
	vs.mark_in_combat()

func physics_update(delta: float, input: InputState) -> StringName:
	elapsed += delta
	var vs := player as VsPlayer

	# 衝刺取消：最高打斷權限，任何時點（包含格擋中/反擊中）都可以打斷——
	# 之前漏加這個檢查，導致這招期間衝刺完全打不出來，違反「衝刺可打斷任何
	# 非受擊動作」的全域規則（見 CLAUDE.md 的 is_input_locked 說明，dodge 的
	# 例外要在每個輸入處理點手動接上，不會自動繼承）。
	if input.dodge and vs.use_dash_energy(30.0):
		return &"vsdodge"

	player.velocity.x = move_toward(player.velocity.x, 0.0, IMPULSE_FRICTION * delta)
	if not _grounded():
		_apply_gravity(delta)

	match current_stage:
		Stage.START:
			if elapsed >= _anim_length:
				_enter_loop(vs)
		Stage.LOOP:
			# 格擋窗口倒數：START 的前搖時間也算在 CHANNEL_DURATION 內（比照主遊戲，
			# channel_timer 從 enter() 就開始扣，這裡只是 LOOP 階段才檢查歸零）
			channel_timer -= delta
			if channel_timer <= 0.0:
				_enter_end(vs)
		Stage.COUNTER, Stage.END:
			if elapsed >= _anim_length:
				return _recovery_transition(input)

	return &""

func _enter_loop(vs: VsPlayer) -> void:
	current_stage = Stage.LOOP
	elapsed = 0.0
	vs.anim_player.play("art_1_loop")
	_anim_length = vs.anim_player.get_animation("art_1_loop").length

func _enter_end(vs: VsPlayer) -> void:
	current_stage = Stage.END
	elapsed = 0.0
	vs.anim_player.play("art_1_end")
	_anim_length = vs.anim_player.get_animation("art_1_end").length

## 供 VsPlayer._on_hurtbox_hurt() 呼叫（duck-typed，見該處註解）：格擋窗口
## （START/LOOP）內、且攻擊破霸等級低於 STRONG_ARMOR_BREAK → 完全格擋、
## 觸發反擊，回傳 true 代表這下攻擊已經被吃掉，呼叫端不用再處理傷害/硬直。
func try_parry(hitbox: VsHitbox) -> bool:
	if current_stage != Stage.START and current_stage != Stage.LOOP:
		return false
	if hitbox.break_level >= VsHitbox.BreakLevel.STRONG_ARMOR_BREAK:
		return false

	var vs := player as VsPlayer
	current_stage = Stage.COUNTER
	elapsed = 0.0
	vs.invincible_time_left = COUNTER_INVINCIBLE_DURATION
	vs.anim_player.play("art_1_counter")
	_anim_length = vs.anim_player.get_animation("art_1_counter").length
	vs.vfx_action_sfx("Counterattack_successful", -2.0)
	return true

func save_state() -> Dictionary:
	var d := super.save_state()
	d["stage"] = current_stage
	d["ct"]    = channel_timer
	return d

func restore_state(d: Dictionary) -> void:
	super.restore_state(d)
	current_stage = d.get("stage", Stage.START)
	channel_timer = d.get("ct", 0.0)
	var vs := player as VsPlayer
	if is_instance_valid(vs):
		_anim_length = vs.anim_player.get_animation(_anim_name_for_stage()).length

func sync_anim() -> void:
	var vs := player as VsPlayer
	vs.anim_player.play(_anim_name_for_stage())
	vs.anim_player.seek(elapsed, true)

func _anim_name_for_stage() -> String:
	match current_stage:
		Stage.START:   return "art_1_start"
		Stage.LOOP:    return "art_1_loop"
		Stage.COUNTER: return "art_1_counter"
		Stage.END:     return "art_1_end"
	return "art_1_start"
