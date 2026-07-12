class_name Spear
extends Weapon
## 武器腳本：長槍 (Spear) - 收槍強化技重製版

const WEAPON_ID: String = "spear"
@export var no_sheath_steps: Array[int] = [20 ,42]
const SPEAR_WAVE_SCENE = preload("res://player/Spear/ult_wave.tscn")
const ZOOM_LEVELS = { 0: Vector2(1.0, 1.0), 1: Vector2(1.05, 1.05), 2: Vector2(1.1, 1.1), 3: Vector2(1.15, 1.15) }

# 🎨 長槍專屬的火花預設外觀：招式資料裡沒寫 "spark" 對應欄位時，優先套用這裡（比 Hitbox.gd 的通用預設優先）
func get_weapon_default_spark() -> Dictionary:
	return {
		"type": Hitbox.SparkType.SLASH, "scale": 0.3, "color": Color(1.0, 0.4, 0.2, 1.0), "aura_color": Color(1.0, 0.6, 0.2, 1.0),
	}

# ==========================================
# 🥋 專屬武藝系統 (Martial Arts Loadout)
# ==========================================
@export var equipped_martial_arts: Array[String] = [
	"res://player/MartialArts/Spear/Art_Spear_4.tscn",
	"",
	""
]

func _ready() -> void:
	super._ready()
	call_deferred("_delayed_load_arts")

func _delayed_load_arts() -> void:
	load_martial_arts(equipped_martial_arts)

# ==========================================
# 📖 招式數據庫 (Data-Driven Combat Config)
# ==========================================

# 🗡️ [地面普攻字典] (代號: 1~4)
const DICT_LIGHT_GROUND = {
	1: {"anim": "spear/light_1", "hitbox_name": "light", "max_hits": 1, "interval": 0.0, "knockback": Vector2(50.0, 0.0), "base_dmg": 300, "energy": 500, "action_type": Weapon.ActionType.NORMAL,"hit_sfx_type": "hit"},
	2: {"anim": "spear/light_2", "hitbox_name": "light", "max_hits": 2, "interval": 0.1, "knockback": Vector2(50.0, 0.0), "base_dmg": 350, "energy": 5, "action_type": Weapon.ActionType.NORMAL,"hit_sfx_type": "hit"},
	3: {"anim": "spear/light_3", "hitbox_name": "light", "max_hits": 3, "interval": 0.1, "knockback": Vector2(20.0, 0.0), "base_dmg": 150, "energy": 5, "action_type": Weapon.ActionType.NORMAL,"hit_sfx_type": "hit"},
	4: {"anim": "spear/light_4", "hitbox_name": "light", "max_hits": 1, "interval": 0.0, "knockback": Vector2(600.0, 0.0), "shake": 20.0, "base_dmg": 600, "energy": 10, "action_type": Weapon.ActionType.NORMAL,"hit_sfx_type": "hit"}
}

# 💥 [戰技與大招字典] (代號: 20 丟槍, 80/81 大招前後段)
# 🌟 21 (AOE 拉扯) 不屬於這裡——那是武藝卡帶 Art_Spear_4.gd 自己的招式，設定資料就近放在它自己的檔案裡，
# 跟太刀的武藝 (Art_Katana_2/3) 一樣不佔用武器本體的字典，呼叫 weapon._play_martial_art_attack(CONFIG) 出招
const DICT_HEAVY_ULT = {
	20: {"anim": "spear/heavy", "hitbox_name": "None", "max_hits": 1, "interval": 0.0, "knockback": Vector2.ZERO, "base_dmg": 0, "energy": 0, "hit_sfx_type": "hit"},
	80: {"anim": "spear/attack_ult", "hitbox_name": "None", "max_hits": 1, "interval": 0.0, "knockback": Vector2.ZERO, "base_dmg": 0, "energy": 0},
	81: {"anim": "spear/attack_ult_end", "hitbox_name": "None", "max_hits": 1, "interval": 0.0, "knockback": Vector2.ZERO, "base_dmg": 0, "energy": 0}
}

# 🦅 [空中連段字典] (代號: 61~62)
const DICT_LIGHT_AIR = {
	61: { "anim": "spear/air_attack_1", "hitbox_name": "Air_J", "max_hits": 4, "interval": 0.15, "shake": 10.0, "type": Damage.Type.LIGHT, "knockback": Vector2(10.0, -150.0), "base_dmg": 50, "energy": 1, "action_type": Weapon.ActionType.NORMAL, "sticky": true,"hit_sfx_type": "hit"},
	62: { "anim": "spear/air_attack_2", "hitbox_name": "Air_J", "max_hits": 1, "interval": 0.0, "shake": 50.0, "type": Damage.Type.HEAVY, "knockback": Vector2(300.0, 600.0), "base_dmg": 300, "energy": 2, "action_type": Weapon.ActionType.NORMAL,"hit_sfx_type": "hit"},
}

# 🪃 [收槍強化技字典] (代號 40~43)
# 40 = 長按普攻：爆發三連刺 (末端傷害更高)
# 41 = 短按普攻：突進 (位移/音效沿用舊「強化普攻」，末端傷害更高)
# 42 = 短按戰技：擊飛 (移植自舊武藝 Art_Spear_22)
# 43 = 長按戰技：增傷 (12秒攻擊附加增傷 buff，動畫尚未提供)
const DICT_CATCH_SKILL = {
	40: {"anim": "spear/attack_enhanced_3", "hitbox_name": "attack_enhanced_3", "type": Damage.Type.LIGHT, "max_hits": 3, "interval": 0.2, "knockback": Vector2(20.0, 0.0), "shake": 30.0, "base_dmg": 1500, "sticky": true, "action_type": Weapon.ActionType.SKILL, "hit_sfx_type": "hit"},
	41: {"anim": "spear/attack_enhanced", "hitbox_name": "attack_enhanced", "type": Damage.Type.HEAVY, "max_hits": 4, "interval": 0.1, "knockback": Vector2(100.0, -100.0), "shake": 15.0, "base_dmg": 800, "sticky": true, "action_type": Weapon.ActionType.SKILL, "hit_sfx_type": "hit"},
	42: {"anim": "spear/attack_enhanced_2", "hitbox_name": "attack_enhanced_2", "type": Damage.Type.HEAVY, "max_hits": 1, "interval": 0.0, "knockback": Vector2(0.0, -600.0), "shake": 60.0, "base_dmg": 500, "action_type": Weapon.ActionType.SKILL, "hit_sfx_type": "hit_2"},
	43: {"anim": "spear/attack_enhanced_4", "hitbox_name": "None", "max_hits": 1, "interval": 0.0, "knockback": Vector2.ZERO, "base_dmg": 0, "action_type": Weapon.ActionType.SKILL},
}

# 🌟 收槍強化技 1/2/3 的「末端更痛」：獨立的第二個判定框 (HitboxTip / AttackEnhancedTip / AttackEnhanced2Tip)。
# 開關時機跟原本判定框完全同步——都是靠動畫裡的 enable_weapon_hitbox/disable_weapon_hitbox 呼叫觸發
# (見 enable_hitbox()/disable_hitbox())，純粹靠位置分：近處 = 普通傷害，站在末端 = Tip 判定框的傷害
const CATCH_SKILL_TIP_MULT := {40: 2.0, 41: 1.8, 42: 1.6}

# 🌟 收槍強化技 3 (擊飛) 的挑飛時機，直接沿用原本 Art_Spear_22 武藝的數值
const LAUNCH_START_TIME: float = 0.20
const LAUNCH_DURATION: float = 0.06
const LAUNCH_SPEED: float = -650.0

# ==========================================
# 🀄 破陣值 (Pozhen) —— 丟槍 (20) 的資源門檻
# 上限 120，每秒被動回 10；每一招命中固定 +10 (看招式給，不看連擊命中次數)；成功使出任意收槍強化技 (40~43) +50；
# 丟槍需要破陣值全滿才能發動，發動後立刻清空歸零
# ==========================================
const MAX_POZHEN: float = 120.0
const POZHEN_REGEN_PER_SECOND: float = 10.0
const POZHEN_GAIN_PER_HIT: float = 10.0
const POZHEN_GAIN_PER_ENHANCED_SKILL: float = 60.0
var current_pozhen: float = 0.0

# ==========================================
# 🎛️ 內部狀態變數
# ==========================================
@export_group("空戰設定 (Air Combat)")
@export var min_air_attack_height: float = 40.0
@export var air_thrust_force: float = -150.0
var air_attack_locked: bool = false

var is_spear_thrown: bool = false
const BOOMERANG_SCENE = preload("res://player/Spear/SpearBoomerang.tscn")

@export_group("收槍強化技設定")
@export var thrown_speed_mult: float = 1.2 ## 槍還沒收回來的這段時間，移速倍率
@export var catch_speed_boost_peak_speed: float = 600.0 ## 真的接槍瞬間的爆發移速峰值，會在 catch_speed_boost_duration 秒內線性衰減到 0
@export var catch_speed_boost_duration: float = 0.5 ## 跟轉身動畫等長；衰減完後如果還按著方向鍵，就自然交還給正常跑動加速
const CATCH_HOLD_THRESHOLD: float = 0.20 ## 短按/長按的判定門檻
const DAMAGE_BUFF_DURATION: float = 12.0
@export var damage_buff_mult: float = 1.25 ## 增傷 buff 期間的傷害倍率
const BLEED_DAMAGE_PER_TICK: int = 100 ## 佔位數值，之後再調
const BLEED_TICKS: int = 4
const BLEED_TICK_INTERVAL: float = 0.5

## 收槍強化技「真正出招」的 combo_step（跟前搖 44 分開算）——強化技執行中免打斷、減傷都靠這個判斷
const ENHANCED_SKILL_STEPS := [40, 41, 42, 43]

var spear_is_deployed: bool = false ## 槍丟出去、還沒收回來的這段時間，全程 true
var catch_speed_boost_time_left: float = 0.0
var catch_skill_43_timer: float = 0.0 ## 增傷技還沒畫動畫，先用固定時間頂著這個「出招」步驟
const CATCH_SKILL_43_DURATION: float = 0.4
var damage_buff_time_left: float = 0.0

## 強化技執行中（40~43）要進入強霸體——實際的減傷比例/免打斷規則統一交給 Player.gd 判斷
func get_armor_tier() -> int:
	return Player.ArmorTier.STRONG_HYPER_ARMOR if combo_step in ENHANCED_SKILL_STEPS else Player.ArmorTier.NONE

# ==========================================
# 🌀 「轉身收槍」前搖
# 真的接槍 → 一觸碰到玩家就自動播放，播放期間是輸入緩衝區，短按/長按普攻或戰技 → 播完自動出強化技
# 槍還沒飛回來就先誤按攻擊/戰技/武藝 → 強制把槍拉回來，一樣播這段前搖，但播完不出任何招
# ==========================================
var is_catch_recovery: bool = false
var catch_recovery_bonus_eligible: bool = false ## true=真接槍，前搖期間可以緩衝強化技；false=提早誤按，前搖播完不出招
var catch_recovery_input_captured: bool = false ## 前搖期間有沒有偵測到攻擊/戰技鍵按下
var catch_recovery_is_heavy: bool = false
var catch_recovery_is_hold: bool = false
var catch_recovery_hold_timer: float = 0.0
const CATCH_RECOVERY_ANIM: String = "spear/attack_enhanced_start" ## 真的接住槍：轉身收槍動畫
const CATCH_RECOVERY_INTERRUPT_ANIM: String = "spear/attack_enhanced_interrupt" ## 槍還沒回來就提早誤按打斷：另一段動畫，跟真的接住做出區分
const CATCH_RECOVERY_BLOCKED_STATES := ["hurt", "dying", "weaponattack", "swapweapon"]
## 閃避 (含魔女時間) 跟格擋都是短暫的「反射型」狀態，不硬打斷，改成記著等它們真正結束再補觸發轉身
const CATCH_RECOVERY_DEFERRED_STATES := ["slide", "guard"]
@export var catch_recovery_invincible: bool = true ## 真的接槍成功的轉身期間是否給無敵
var active_boomerang: SpearBoomerang = null ## 目前飛在外面的槍，誤按時需要強制把它拉回來
var pending_catch_recovery: bool = false ## 閃避/格擋期間槍飛回來了，先記著，等狀態真正結束再補觸發，避免虧損強化技

@onready var hitbox_tip: Hitbox = $HitboxTip
@onready var attack_enhanced_tip: Hitbox = $AttackEnhancedTip
@onready var attack_enhanced_2_tip: Hitbox = $AttackEnhanced2Tip

# 🌟 收槍強化技 3 (擊飛) 的挑飛狀態——沿用原本 Art_Spear_22 武藝「先短暫爆發衝力、再放手讓重力自然接管」的節奏
var is_launch_triggered: bool = false
var launch_timer: float = 0.0

var is_time_stop_triggered: bool = false
var _ult_zoom_phase: int = 0
var _camera_tween: Tween
var is_wave_fired: bool = false

var _current_energy_reward: float = 0.0
var _multi_hit_energy: bool = false
var _has_granted_resources_this_step: bool = false

const NORMAL_HIT_MARTIAL_ENERGY: float = 0.2 ## 非武藝招式每次命中給的武藝能量，跟太刀一樣的數值
## 🌟 這一步的 hitbox 是不是武藝出的——在 _apply_hitbox_config() 當下就把它「拍照」記下來，
## 之後判斷要不要發武藝能量一律看這個，不要看當下的 active_martial_art（sticky 連段可能拖到武藝已經 is_active=false/被清空之後才補完最後幾下命中）
var _current_step_is_martial_art: bool = false

@export var ult_energy_cost: float = 100.0
const ULT_DURATION: float = 30.0
const MAX_ULT_ATTACKS: int = 24

var is_ult_active: bool = false
var ult_buff_timer: float = 0.0
var ult_attack_count: int = 0



var combo_step: int = 0
var is_attacking: bool = false
var step_cooldown: float = 0.0

@export var combo_timeout: float = 0.3
var last_attack_time: float = 0.0

var current_active_hitbox: Hitbox = null
var _is_hitbox_locked: bool = false

func start_light_attack() -> void:
	if is_catch_recovery: return

	if spear_is_deployed:
		_begin_catch_recovery(false)
		return
	if step_cooldown > 0: return
	air_attack_locked = false

	if not player.is_on_floor():
		if air_attack_locked or _get_ground_distance() < min_air_attack_height:
			is_attacking = false
			return

		if combo_step == 61:
			combo_step = 62
			air_attack_locked = true
		else:
			combo_step = 61

		step_cooldown = 0.15
		is_attacking = true

		var input_dir = Input.get_axis("move_left", "move_right")
		if not is_zero_approx(input_dir) and player is Player:
			player.direction = 1 if input_dir > 0 else -1

		_play_air_step(combo_step)
		return

	step_cooldown = 0.15

	if not is_attacking:
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - last_attack_time > combo_timeout:
			combo_step = 0

	if is_ult_active:
		combo_step = 3
		ult_attack_count += 1

		if ult_attack_count >= MAX_ULT_ATTACKS:
			is_ult_active = false
			ult_buff_timer = 0.0
	else:
		combo_step += 1
		if not DICT_LIGHT_GROUND.has(combo_step):
			combo_step = 1

	is_attacking = true
	_play_light_step(combo_step)

func start_heavy_attack() -> void:
	if is_catch_recovery: return

	if spear_is_deployed:
		_begin_catch_recovery(false)
		return
	if step_cooldown > 0: return

	if not player.is_on_floor():
		is_attacking = false
		combo_step = 0
		# 🔧 同樣要補回 WeaponAttackState.enter() 提早觸發的 scabbard.fade_out()，理由見下方註解
		if player.get("scabbard"):
			player.scabbard.fade_in()
		return

	# 🌟 丟槍需要破陣值全滿才能發動——沒滿的話什麼事都不該發生，
	# combo_step 要一起歸零，不然 requires_sheath() 會被上一招留下來的舊 combo_step 誤導，
	# 害玩家在原地憑空播一次收槍動畫
	if current_pozhen < MAX_POZHEN:
		is_attacking = false
		combo_step = 0
		# 🔧 WeaponAttackState.enter() 一進場就無條件先呼叫 scabbard.fade_out()（賭這次一定會出招）；
		# 這裡直接被擋下、根本沒有真的出招，要自己把這個提早觸發的淡出補回來，
		# 不然刀鞘會卡在「淡出到一半沒淡回來」，玩家狂按丟槍鍵就會看到刀鞘一直閃爍抽搐
		if player.get("scabbard"):
			player.scabbard.fade_in()
		return

	step_cooldown = 0.15

	var input_dir = Input.get_axis("move_left", "move_right")
	if input_dir != 0 and player is Player:
		player.direction = 1 if input_dir > 0 else -1

	is_attacking = true
	is_spear_thrown = false
	spear_is_deployed = true
	current_pozhen = 0.0

	_play_heavy_ult_step(20)
	print("🪃 丟出迴旋鏢！")

func execute_martial_art(slot_index: int) -> void:
	if is_catch_recovery: return

	if spear_is_deployed:
		_begin_catch_recovery(false)
		return
	super.execute_martial_art(slot_index)

func start_ultimate() -> void:
	if player.has_method("consume_weapon_energy"):
		player.consume_weapon_energy(WEAPON_ID, ult_energy_cost)

	step_cooldown = 0.15
	is_attacking = true
	combo_step = 80
	air_attack_locked = false

	player.invincible_time_left = 3.0

	is_time_stop_triggered = false
	_ult_zoom_phase = 0
	is_wave_fired = false

	is_ult_active = true
	ult_buff_timer = ULT_DURATION
	ult_attack_count = 0

	_play_heavy_ult_step(80)
	player.is_input_locked = true

func can_use_ultimate() -> bool:
	if is_ult_active: return false
	if not player.is_on_floor(): return false
	if player.has_method("get_weapon_energy"):
		if player.get_weapon_energy(WEAPON_ID) < ult_energy_cost:
			return false
	return true

# ==========================================
# 💾 武器狀態保存與繼承
# ==========================================
func export_weapon_data() -> Dictionary:
	return {
		"is_ult_active": is_ult_active,
		"ult_buff_timer": ult_buff_timer,
		"ult_attack_count": ult_attack_count,
		"current_pozhen": current_pozhen,
	}

func import_weapon_data(data: Dictionary) -> void:
	is_ult_active = data.get("is_ult_active", false)
	ult_buff_timer = data.get("ult_buff_timer", 0.0)
	ult_attack_count = data.get("ult_attack_count", 0)
	current_pozhen = data.get("current_pozhen", 0.0)

# ==========================================
# ⏱️ 物理與系統計時器
# ==========================================
func update_timers_only(delta: float) -> void:
	current_pozhen = minf(current_pozhen + POZHEN_REGEN_PER_SECOND * delta, MAX_POZHEN)

	if step_cooldown > 0:
		step_cooldown -= delta

	if ult_buff_timer > 0:
		ult_buff_timer -= delta
		if ult_buff_timer <= 0 and is_ult_active:
			is_ult_active = false

	if damage_buff_time_left > 0:
		damage_buff_time_left -= delta

	if catch_speed_boost_time_left > 0:
		catch_speed_boost_time_left -= delta

	# 🌟 槍是在閃避 (魔女時間) 或格擋期間飛回來的，剛才沒敢硬打斷——
	# 現在每一幀檢查一次，只要玩家離開這些反射型狀態了，就補觸發轉身，不讓這次的強化技機會白白浪費掉
	if pending_catch_recovery and is_instance_valid(player) and is_instance_valid(player.state_machine):
		var deferred_state = player.state_machine.current_state
		var deferred_state_name = deferred_state.name.to_lower() if is_instance_valid(deferred_state) else ""
		if deferred_state_name not in CATCH_RECOVERY_DEFERRED_STATES:
			pending_catch_recovery = false
			# 🌟 在空中的話什麼都不用做，攻擊權限本來就已經還了，不需要轉身動畫也不用強化技緩衝
			if deferred_state_name not in CATCH_RECOVERY_BLOCKED_STATES and player.is_on_floor():
				_begin_catch_recovery(true)
				player.state_machine.transition_to("WeaponAttack")

	if player.is_on_floor():
		air_attack_locked = false
		if not is_attacking and combo_step in [61, 62]:
			combo_step = 0

func get_speed_multiplier() -> float:
	return thrown_speed_mult if spear_is_deployed else 1.0

func get_current_velocity(delta: float) -> Vector2:
	# 🌟 攔截器：如果有武藝在執行，物理位移全權交給它算！
	if is_instance_valid(active_martial_art) and active_martial_art.is_active:
		return active_martial_art.get_current_velocity(delta)

	if not is_attacking: return player.velocity
	if player.is_on_floor(): air_attack_locked = false

	var new_x = player.velocity.x
	var new_y = player.velocity.y

	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	var base_friction = player.FLOOR_ACCELERATION * (speed_mult * speed_mult) * delta

	# ==========================================
	# 🌀 「轉身收槍」前搖播放中——bonus_eligible 時，這段期間就是強化技的輸入緩衝區
	# ==========================================
	if is_catch_recovery:
		if catch_recovery_bonus_eligible:
			# 🌟 真的接槍成功：不鎖移動，讓玩家能邊移動邊播這段前搖。
			# 瞬間爆發移速，純粹依剩餘時間比例線性衰減到 0（不是慢慢加速逼近，是直接按當下比例給速度），
			# 衰減到 0 之後如果還按著方向鍵，自然交給後面正常的 Run 狀態接手加速
			var movement := Input.get_axis("move_left", "move_right")
			if not is_zero_approx(movement) and player is Player:
				player.direction = 1 if movement > 0 else -1
			var boost_ratio = clampf(catch_speed_boost_time_left / catch_speed_boost_duration, 0.0, 1.0)
			new_x = movement * catch_speed_boost_peak_speed * boost_ratio
		else:
			new_x = move_toward(new_x, 0.0, base_friction)

		if not player.is_on_floor(): new_y += player.default_gravity * delta

		if catch_recovery_bonus_eligible:
			if not catch_recovery_input_captured:
				if Input.is_action_just_pressed("attack"):
					catch_recovery_input_captured = true
					catch_recovery_is_heavy = false
					catch_recovery_hold_timer = 0.0
				elif Input.is_action_just_pressed("heavy_attack"):
					catch_recovery_input_captured = true
					catch_recovery_is_heavy = true
					catch_recovery_hold_timer = 0.0
			else:
				var action := "heavy_attack" if catch_recovery_is_heavy else "attack"
				if Input.is_action_pressed(action):
					catch_recovery_hold_timer += delta
					if catch_recovery_hold_timer >= CATCH_HOLD_THRESHOLD:
						catch_recovery_is_hold = true
				else:
					catch_recovery_is_hold = catch_recovery_hold_timer >= CATCH_HOLD_THRESHOLD

		if not player.animation_player.is_playing():
			is_catch_recovery = false
			if catch_recovery_bonus_eligible and catch_recovery_input_captured:
				var skill_id = _resolve_catch_skill_id(catch_recovery_is_heavy, catch_recovery_is_hold)
				_fire_catch_skill_now(skill_id)
			else:
				# 沒緩衝到輸入 (或本來就是誤按收尾)：前搖播完單純恢復攻擊權限，不出任何招
				# 🌟 combo_step 故意留著 44 不歸零：這樣 requires_sheath() 才會判定「這招需要收招」，
				# 讓 WeaponAttackState 自然轉去 Sheath 播收槍動畫，而不是直接跳回 Idle
				is_attacking = false
				player.is_input_locked = false

		return Vector2(new_x, new_y)

	# 🌟 收槍強化技 3 (擊飛) 的挑飛時機，跟舊武藝 Art_Spear_22 完全一樣：
	# 先短暫爆發衝力 (LAUNCH_DURATION 秒)，之後放手讓重力自然接管，不會整段動畫都釘死在最高速度往上衝
	if combo_step == 42:
		var anim_time = player.animation_player.current_animation_position
		if anim_time >= LAUNCH_START_TIME and not is_launch_triggered:
			is_launch_triggered = true
			launch_timer = LAUNCH_DURATION

		if is_launch_triggered:
			if launch_timer > 0:
				launch_timer -= delta
				new_y = LAUNCH_SPEED
				new_x = 0.0
			else:
				new_x = 0.0
				if new_y < 0:
					new_y = move_toward(new_y, 0.0, player.default_gravity * 2.0 * delta)
				else:
					new_y += player.default_gravity * delta
			return Vector2(new_x, new_y)

	# 🌟 收槍強化技 4 (增傷) 沒有動畫，用固定時間頂著這一步驟
	if combo_step == 43:
		catch_skill_43_timer -= delta
		new_x = move_toward(new_x, 0.0, base_friction)
		return Vector2(new_x, new_y)

	# --- 摩擦力減速邏輯 ---
	if combo_step in [1, 2, 3, 4, 40, 41]:
		new_x = move_toward(new_x, 0.0, base_friction)

	# 🌟 空戰慣性滑行與微浮空
	elif combo_step in [61, 62]:
		new_x = move_toward(new_x, 0.0, base_friction)

		if combo_step == 61 and not player.is_on_floor():
			if new_y > 0: new_y = 0.0
			new_y += (player.default_gravity * 0.6) * delta
			if new_y > 50.0: new_y = 50.0

	# 戰技 20：丟出迴旋鏢
	elif combo_step == 20:
		new_x = move_toward(new_x, 0.0, base_friction)

		var anim_time = player.animation_player.current_animation_position
		if anim_time >= 0.15 and not is_spear_thrown:
			is_spear_thrown = true
			spawn_boomerang()

	# ----------------------------------------
	# 🌌 大招前半段 (80)
	# ----------------------------------------
	elif combo_step == 80:
		new_x = move_toward(new_x, 0.0, base_friction * 5.0)
		new_y = 0.0

		var anim_time = player.animation_player.current_animation_position
		if anim_time >= 0.05 and not is_time_stop_triggered:
			is_time_stop_triggered = true
			if player.has_method("trigger_time_stop"):
				player.trigger_time_stop(3.0, 0.001)
			player.animation_player.speed_scale = 1.0 / 0.001
			player.invincible_time_left = 3.0

		if anim_time >= 0.05 and _ult_zoom_phase == 0:
			_ult_zoom_phase = 1
			_apply_charge_zoom(Vector2(1.5, 1.5), 0.3)

		if anim_time >= 0.70 and _ult_zoom_phase == 1:
			_ult_zoom_phase = 2
			if CombatManager.has_method("apply_camera_shake"):
				CombatManager.apply_camera_shake(30.0, 0.1)

	# ----------------------------------------
	# 🌌 大招後半段 (81)
	# ----------------------------------------
	elif combo_step == 81:
		new_x = move_toward(new_x, 0.0, base_friction * 5.0)
		new_y = 0.0
		player.invincible_time_left = 0.6

		var anim_time = player.animation_player.current_animation_position
		if anim_time >= 0.05 and not is_wave_fired:
			is_wave_fired = true
			if CombatManager.has_method("apply_camera_shake"):
				CombatManager.apply_camera_shake(150.0, 0.15)
			spawn_spear_wave("ult_wave")

	else:
		new_x = move_toward(new_x, 0.0, base_friction)

	return Vector2(new_x, new_y)

func is_handling_gravity() -> bool:
	if is_instance_valid(active_martial_art) and active_martial_art.is_active:
		if active_martial_art.has_method("is_handling_gravity"):
			return active_martial_art.is_handling_gravity()

	if combo_step == 42 and is_launch_triggered: return true
	if combo_step in [61] and not player.is_on_floor(): return true
	if combo_step in [80, 81]: return true
	return false

func requires_sheath() -> bool:
	if combo_step == 0: return false
	return combo_step not in no_sheath_steps

## 太刀式的三段出招入口：各自挑好對應字典、播動畫，實際套用判定框設定都交給共用的 _apply_hitbox_config()
func _play_light_step(step: int) -> void:
	disable_hitbox()
	var config: Dictionary = DICT_LIGHT_GROUND[step]
	_apply_hitbox_config(config)
	if player.animation_player.current_animation == config["anim"]: player.animation_player.stop()
	player.play_safe_anim(config["anim"])

func _play_heavy_ult_step(step: int) -> void:
	disable_hitbox()
	var config: Dictionary = DICT_HEAVY_ULT[step]
	_apply_hitbox_config(config)
	combo_step = step
	if player.animation_player.current_animation == config["anim"]: player.animation_player.stop()
	player.play_safe_anim(config["anim"])

func _play_catch_skill_step(skill_id: int) -> void:
	disable_hitbox()
	var config: Dictionary = DICT_CATCH_SKILL[skill_id]
	_apply_hitbox_config(config)
	combo_step = skill_id
	if player.animation_player.current_animation == config["anim"]: player.animation_player.stop()
	player.play_safe_anim(config["anim"])

## 武藝卡帶專用出招入口：config 是武藝自己那個檔案裡的 CONFIG，不屬於武器本體的任何字典——
## combo_step 由武藝自己設定 (見 Art_Spear_4.gd)，這裡只負責套判定框跟播動畫
func _play_martial_art_attack(config: Dictionary) -> void:
	disable_hitbox()
	_apply_hitbox_config(config)
	if player.animation_player.current_animation == config["anim"]: player.animation_player.stop()
	player.play_safe_anim(config["anim"])

## 共用的判定框設定套用邏輯：只負責把 config 的數值灌進 hitbox，不管動畫——動畫由各個 _play_*_step() 自己播
func _apply_hitbox_config(config: Dictionary) -> void:
	_is_hitbox_locked = false

	current_action_type = config.get("action_type", Weapon.ActionType.NONE)

	var target_hitbox_name = config.get("hitbox_name", "Hitbox")
	var hitbox := get_node_or_null(target_hitbox_name) as Hitbox

	if hitbox:
		var final_dmg = float(config.get("base_dmg", 100))
		if damage_buff_time_left > 0:
			final_dmg *= damage_buff_mult
		hitbox.damage_amount = max(1, roundi(final_dmg))
		hitbox.max_hits = config.get("max_hits", 1)
		hitbox.hit_sfx_type = config.get("hit_sfx_type", "")

		if "hit_interval" in hitbox: hitbox.hit_interval = config.get("interval", 0.0)
		if "knockback_force" in hitbox: hitbox.knockback_force = config.get("knockback", Vector2.ZERO)

		if "attack_type" in hitbox: hitbox.attack_type = config.get("type", Damage.Type.LIGHT)
		if "sticky_multi_hit" in hitbox: hitbox.sticky_multi_hit = config.get("sticky", false)
		if "pull_towards_owner" in hitbox: hitbox.pull_towards_owner = config.get("pull", false)

		if "shake_intensity" in hitbox: hitbox.shake_intensity = config.get("shake", 2.5)
		if "shake_on_hit_only" in hitbox: hitbox.shake_on_hit_only = config.get("shake_on_hit_only", true)

		# 🌟 目前長槍還沒有任何一招設 "breaks_guard"，但先照太刀的方式接好——之後要做能破黃圈的招式，
		# 直接在字典裡加這個欄位就會生效，不用再回來補管線
		hitbox.breaks_guard = config.get("breaks_guard", false)
		if hitbox.breaks_guard and player.has_method("trigger_time_stop"):
			var slow_scale = 0.001
			var slow_duration = config.get("guard_slowdown_duration", 0.7)
			player.trigger_time_stop(slow_duration, slow_scale)
			player.animation_player.speed_scale = 1.0 / slow_scale
			if is_instance_valid(active_martial_art):
				active_martial_art.set("_time_stop_triggered", true)

		# 🎨 火花屬性：三層 fallback —— ①這招自己的 "spark" 覆蓋 ②長槍專屬的 get_weapon_default_spark() ③Hitbox.gd 的通用預設
		var spark_cfg: Dictionary = config.get("spark", {})
		var weapon_spark: Dictionary = get_weapon_default_spark()
		hitbox.spark_type = spark_cfg.get("type", weapon_spark.get("type", Hitbox.DEFAULT_SPARK_TYPE))
		hitbox.spark_scale = spark_cfg.get("scale", weapon_spark.get("scale", Hitbox.DEFAULT_SPARK_SCALE))
		hitbox.spark_color = spark_cfg.get("color", weapon_spark.get("color", Hitbox.DEFAULT_SPARK_COLOR))
		hitbox.aura_color = spark_cfg.get("aura_color", weapon_spark.get("aura_color", Hitbox.DEFAULT_AURA_COLOR))
		hitbox.spark_raw_intensity = spark_cfg.get("raw_intensity", weapon_spark.get("raw_intensity", Hitbox.DEFAULT_SPARK_RAW_INTENSITY))
		hitbox.spark_random_angle = spark_cfg.get("random_angle", weapon_spark.get("random_angle", Hitbox.DEFAULT_SPARK_RANDOM_ANGLE))
		hitbox.spark_base_offset = spark_cfg.get("base_offset", weapon_spark.get("base_offset", Hitbox.DEFAULT_SPARK_BASE_OFFSET))
		hitbox.spark_random_offset = spark_cfg.get("random_offset", weapon_spark.get("random_offset", Hitbox.DEFAULT_SPARK_RANDOM_OFFSET))
		hitbox.attach_spark_to_victim = spark_cfg.get("attach_to_victim", weapon_spark.get("attach_to_victim", Hitbox.DEFAULT_ATTACH_SPARK_TO_VICTIM))
		hitbox.custom_spark_scene = spark_cfg.get("custom_scene", weapon_spark.get("custom_scene", null))

		hitbox.hit_targets.clear()
		hitbox.lock_attacker_direction() # 🌟 這次出招的擊退方向鎖定在這一刻，連段期間玩家再怎麼轉身/移動都不會中途變卦

		_current_energy_reward = float(config.get("energy", 0))
		_multi_hit_energy = config.get("multi_hit_energy", false)
		_has_granted_resources_this_step = false
		_current_step_is_martial_art = is_instance_valid(active_martial_art)

		if current_active_hitbox and current_active_hitbox.hit.is_connected(_on_main_hitbox_hit):
			current_active_hitbox.hit.disconnect(_on_main_hitbox_hit)

		current_active_hitbox = hitbox

		if not current_active_hitbox.hit.is_connected(_on_main_hitbox_hit):
			current_active_hitbox.hit.connect(_on_main_hitbox_hit)

## 本體判定框命中：先跑共用的能量獎勵邏輯，再把這個目標鎖死在「當下這招的末端判定框」裡，
## 防止站在本體/末端交界的重疊區同時吃到兩邊傷害
func _on_main_hitbox_hit(hurtbox: Node) -> void:
	_on_hitbox_hit(hurtbox)
	_exclude_from_sibling(hurtbox, _get_tip_hitbox(combo_step))

## 末端判定框命中：一樣先跑共用的能量獎勵邏輯，再把這個目標鎖死在本體判定框裡，
## 道理相同——不能讓同一下攻擊，同一個目標，本體跟末端各打一次
func _on_tip_hitbox_hit(hurtbox: Node) -> void:
	_on_hitbox_hit(hurtbox)
	_exclude_from_sibling(hurtbox, current_active_hitbox)

## 把 hurtbox 標記成「已經打滿次數」，讓 sibling 這顆判定框往後對這個目標視同打完、不再出手——
## 本體/末端誰先命中誰就贏，不會同時吃到兩邊傷害
func _exclude_from_sibling(hurtbox: Node, sibling: Hitbox) -> void:
	if not is_instance_valid(sibling): return
	if not sibling.hit_targets.has(hurtbox):
		sibling.hit_targets[hurtbox] = {"hits_done": 0, "last_hit_time": 0.0}
	sibling.hit_targets[hurtbox]["hits_done"] = sibling.max_hits

func _on_hitbox_hit(hurtbox: Node) -> void:
	if is_instance_valid(player) and is_instance_valid(hurtbox.owner) and hurtbox.owner == player:
		return

	if _multi_hit_energy or not _has_granted_resources_this_step:
		# 🌟 破陣值跟武器能量一樣，是看「這一招」給固定值，不是看連擊命中次數疊加
		current_pozhen = minf(current_pozhen + POZHEN_GAIN_PER_HIT, MAX_POZHEN)

		if _current_energy_reward > 0:
			if player.has_method("add_weapon_resource"):
				player.add_weapon_resource(WEAPON_ID, _current_energy_reward)

		# 🔋 只有「非武藝招式」的命中才給武藝能量——如果連武藝自己打中東西也回能量，
		# 這個能量限制就形同虛設（隨便放一招就把施放它自己的成本賺回來），跟太刀的規則一樣
		if not _current_step_is_martial_art:
			if player.has_method("gain_martial_energy"):
				player.gain_martial_energy(NORMAL_HIT_MARTIAL_ENERGY)

		# 🩸 43 號增傷技的差異化：buff 期間打中的目標額外附加流血 DOT，跟太刀的「瞬間爆發傷害」燃燒劍意做出區隔
		if damage_buff_time_left > 0 and is_instance_valid(hurtbox.owner) and hurtbox.owner.has_method("apply_bleed"):
			hurtbox.owner.apply_bleed(BLEED_DAMAGE_PER_TICK, BLEED_TICKS, BLEED_TICK_INTERVAL)

		_has_granted_resources_this_step = true

func _play_air_step(step: int) -> void:
	disable_hitbox()
	var config: Dictionary = DICT_LIGHT_AIR[step]
	_apply_hitbox_config(config)
	player.velocity.y = air_thrust_force
	if player.animation_player.current_animation == config["anim"]: player.animation_player.stop()
	player.play_safe_anim(config["anim"])

func _get_ground_distance() -> float:
	var space_state = player.get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(player.global_position, player.global_position + Vector2(0, 1000))
	query.collision_mask = 1
	var result = space_state.intersect_ray(query)
	if result: return player.global_position.distance_to(result.position)
	return 1000.0

func enable_hitbox(shape_name: String = "") -> void:
	if _is_hitbox_locked: return
	if current_active_hitbox:
		for child in current_active_hitbox.get_children():
			if child is CollisionShape2D:
				if shape_name == "" or child.name == shape_name:
					child.set_deferred("disabled", false)

	# 🌟 收槍強化技 1/2/3 的末端判定框，跟原本動畫呼叫 enable_weapon_hitbox 的時間點同步開
	if combo_step in [40, 41, 42]:
		_set_tip_shape_active(_get_tip_hitbox(combo_step), true)

func disable_hitbox(shape_name: String = "") -> void:
	if current_active_hitbox:
		for child in current_active_hitbox.get_children():
			if child is CollisionShape2D:
				if shape_name == "" or child.name == shape_name:
					child.set_deferred("disabled", true)

	# 🌟 收槍強化技 1/2/3 的末端判定框，跟原本動畫呼叫 disable_weapon_hitbox 的時間點同步關
	if combo_step in [40, 41, 42]:
		_set_tip_shape_active(_get_tip_hitbox(combo_step), false)

func is_attack_finished() -> bool:
	if not is_attacking: return true
	if is_catch_recovery: return false

	if combo_step == 43 and catch_skill_43_timer > 0:
		return false

	if not player.animation_player.is_playing() or combo_step == 43:
		if combo_step == 80:
			combo_step = 81
			if player.has_method("clear_time_stop"):
				player.clear_time_stop()
			_apply_charge_zoom(ZOOM_LEVELS[0], 0.15)
			_ult_zoom_phase = 0
			is_time_stop_triggered = false
			player.invincible_time_left = 1.0
			_play_heavy_ult_step(81)
			return false

		player.is_input_locked = false
		if combo_step in [61, 62]:
			air_attack_locked = true

		if combo_step == 81 or _ult_zoom_phase > 0:
			_ult_zoom_phase = 0
			_apply_charge_zoom(ZOOM_LEVELS[0], 0.4)
			if player.has_method("clear_time_stop"): player.clear_time_stop()

		step_cooldown = 0.0
		last_attack_time = Time.get_ticks_msec() / 1000.0

		_is_hitbox_locked = true
		disable_hitbox()
		_set_tip_shape_active(hitbox_tip, false)
		_set_tip_shape_active(attack_enhanced_tip, false)
		_set_tip_shape_active(attack_enhanced_2_tip, false)

		if is_instance_valid(active_martial_art):
			active_martial_art.is_active = false
			active_martial_art = null

		if not requires_sheath() and player.get("scabbard"):
			player.scabbard.fade_in()
		return true

	return false

func cancel_attack() -> void:
	if is_instance_valid(active_martial_art):
		active_martial_art.cancel()
		active_martial_art = null

	if not player.is_on_floor() and combo_step in [61, 62]:
		air_attack_locked = true
	player.is_input_locked = false
	is_attacking = false
	combo_step = 0
	step_cooldown = 0.0

	# 🌟 spear_is_deployed 故意不在這裡解除：cancel_attack() 在「攻擊正常播完」跟「真的被打斷」
	# 兩種情況都會被 WeaponAttackState.exit() 呼叫，槍還沒收回來的話本來就該繼續鎖著——
	# 真正的解鎖只有兩條路：SpearBoomerang 正常接住 (notify_spear_caught)，或是失蹤保底 (notify_spear_lost)

	is_catch_recovery = false
	catch_recovery_bonus_eligible = false
	catch_recovery_input_captured = false
	catch_recovery_is_heavy = false
	catch_recovery_is_hold = false
	catch_recovery_hold_timer = 0.0
	catch_skill_43_timer = 0.0
	is_launch_triggered = false
	launch_timer = 0.0

	_is_hitbox_locked = true
	disable_hitbox()
	_set_tip_shape_active(hitbox_tip, false)
	_set_tip_shape_active(attack_enhanced_tip, false)
	_set_tip_shape_active(attack_enhanced_2_tip, false)

	is_wave_fired = false
	_ult_zoom_phase = 0

	if is_time_stop_triggered:
		is_time_stop_triggered = false
		if player.has_method("clear_time_stop"): player.clear_time_stop()

	if player.get("scabbard"):
		player.scabbard.fade_in()

	_apply_charge_zoom(ZOOM_LEVELS[0])

# ==========================================
# 🪃 收槍強化技系統
# ==========================================
## 由 SpearBoomerang.gd 在接住的瞬間呼叫：立刻觸發「轉身收槍」前搖
func notify_spear_caught() -> void:
	spear_is_deployed = false
	active_boomerang = null

	# 🌟 接槍瞬間給一段會隨時間衰減的移速提升，而不是強制位移——
	# 這樣前搖期間玩家還能自己按方向鍵移動，不會被迫定在原地又突然被推走
	catch_speed_boost_time_left = catch_speed_boost_duration

	var input_dir = Input.get_axis("move_left", "move_right")
	if not is_zero_approx(input_dir) and player is Player:
		player.direction = 1 if input_dir > 0 else -1

	_try_auto_catch_recovery()

## 保底用：迴旋鏢因為某種原因沒有正常飛回來被接住（例如 5 秒保底計時器到期），只解鎖不開強化技窗口
func notify_spear_lost() -> void:
	spear_is_deployed = false
	active_boomerang = null

## 接槍當下自動觸發前搖——但如果玩家正處於硬直/死亡/攻擊中，就不要硬把狀態機切走打斷這些行為；
## 這種情況下槍照樣算收回來了（攻擊權限已經還了），只是這次沒有轉身動畫可看，也沒有強化技緩衝。
## 閃避 (含魔女時間) 跟格擋則是特例：不會就這樣放棄，改成記下來等狀態真正結束再補觸發 (見 update_timers_only)，
## 這樣躲招/格擋躲到一半也不會卡手，更不會白白虧損掉這次強化技的機會
func _try_auto_catch_recovery() -> void:
	if not is_instance_valid(player) or not is_instance_valid(player.state_machine): return

	# 🌟 在空中的話什麼都不用做，攻擊權限本來就已經還了，不需要轉身動畫也不用強化技緩衝
	if not player.is_on_floor(): return

	var current_state = player.state_machine.current_state
	var state_name = current_state.name.to_lower() if is_instance_valid(current_state) else ""

	if state_name in CATCH_RECOVERY_DEFERRED_STATES:
		pending_catch_recovery = true
		return

	if state_name in CATCH_RECOVERY_BLOCKED_STATES:
		return

	_begin_catch_recovery(true)
	player.state_machine.transition_to("WeaponAttack")

## 短按/長按決定出哪招
func _resolve_catch_skill_id(is_heavy: bool, is_hold: bool) -> int:
	if not is_heavy and is_hold: return 40       # 長按普攻：爆發 (三連刺)
	if not is_heavy and not is_hold: return 41   # 短按普攻：突進
	if is_heavy and not is_hold: return 42        # 短按戰技：擊飛
	return 43                                     # 長按戰技：增傷

## 「轉身收槍」前搖：
## bonus_eligible = true —— 槍真的收回來了，前搖播放期間會緩衝攻擊/戰技鍵，播完依緩衝結果自動出強化技；
## bonus_eligible = false —— 槍還沒飛回來就先誤按，強制把槍拉回來，前搖播完什麼都不出，純粹恢復攻擊權限
func _begin_catch_recovery(bonus_eligible: bool) -> void:
	is_catch_recovery = true
	catch_recovery_bonus_eligible = bonus_eligible
	catch_recovery_input_captured = false
	catch_recovery_is_heavy = false
	catch_recovery_is_hold = false
	catch_recovery_hold_timer = 0.0
	combo_step = 44
	is_attacking = true
	step_cooldown = 0.15
	player.is_input_locked = true

	var input_dir = Input.get_axis("move_left", "move_right")
	if not is_zero_approx(input_dir) and player is Player:
		player.direction = 1 if input_dir > 0 else -1

	if not bonus_eligible and spear_is_deployed:
		spear_is_deployed = false
		if is_instance_valid(active_boomerang):
			active_boomerang.force_early_recall()
			active_boomerang = null

	var recovery_anim := CATCH_RECOVERY_ANIM if bonus_eligible else CATCH_RECOVERY_INTERRUPT_ANIM
	if player.animation_player.current_animation == recovery_anim:
		player.animation_player.stop()
	player.play_safe_anim(recovery_anim)

	# 🌟 只有真的接槍成功的轉身才給無敵，提早誤按打斷的那段不給——用動畫本身的長度頂滿整段前搖
	if bonus_eligible and catch_recovery_invincible:
		var anim_res: Animation = player.animation_player.get_animation(recovery_anim)
		var invincible_duration: float = anim_res.length if anim_res else 0.5
		player.invincible_time_left = maxf(player.invincible_time_left, invincible_duration)

## 「轉身收槍」前搖播完、緩衝到了輸入，真的要出強化技了
func _fire_catch_skill_now(skill_id: int) -> void:
	# 🌟 成功使出任意收槍強化技，不管有沒有真的打到人，都給一大筆破陣值
	current_pozhen = minf(current_pozhen + POZHEN_GAIN_PER_ENHANCED_SKILL, MAX_POZHEN)

	var input_dir = Input.get_axis("move_left", "move_right")
	if not is_zero_approx(input_dir) and player is Player:
		player.direction = 1 if input_dir > 0 else -1

	is_launch_triggered = false
	launch_timer = 0.0

	_play_catch_skill_step(skill_id)

	if skill_id in [40, 41, 42]:
		_setup_tip_hitbox(skill_id)

	if skill_id == 43:
		catch_skill_43_timer = CATCH_SKILL_43_DURATION
		damage_buff_time_left = DAMAGE_BUFF_DURATION
		print("💪 長槍增傷！接下來 ", DAMAGE_BUFF_DURATION, " 秒攻擊傷害 x", damage_buff_mult)

## 收槍強化技 1/2/3 的「末端」判定框設定：獨立傷害值，不依賴命中次數或時間點猜測
func _get_tip_hitbox(skill_id: int) -> Hitbox:
	if skill_id == 40: return hitbox_tip
	if skill_id == 41: return attack_enhanced_tip
	if skill_id == 42: return attack_enhanced_2_tip
	return null

func _setup_tip_hitbox(skill_id: int) -> void:
	var tip := _get_tip_hitbox(skill_id)
	if not is_instance_valid(tip): return

	var cfg: Dictionary = DICT_CATCH_SKILL[skill_id]
	var final_dmg = float(cfg.get("base_dmg", 100)) * CATCH_SKILL_TIP_MULT[skill_id]
	if damage_buff_time_left > 0:
		final_dmg *= damage_buff_mult

	# 🌟 除了傷害數值以外，其餘打擊屬性（連擊數、間隔、黏著、拉扯、擊退、震動）都要跟本體判定框完全一致——
	# 末端判定框只是「同一招換個更高的傷害」，架構不能自己搞一套，不然連段手感會跟本體不一樣
	tip.damage_amount = max(1, roundi(final_dmg))
	tip.max_hits = cfg.get("max_hits", 1)
	tip.attack_type = cfg.get("type", Damage.Type.LIGHT)
	tip.hit_sfx_type = cfg.get("hit_sfx_type", "")

	if "hit_interval" in tip: tip.hit_interval = cfg.get("interval", 0.0)
	if "knockback_force" in tip: tip.knockback_force = cfg.get("knockback", Vector2.ZERO)
	if "sticky_multi_hit" in tip: tip.sticky_multi_hit = cfg.get("sticky", false)
	if "pull_towards_owner" in tip: tip.pull_towards_owner = cfg.get("pull", false)
	if "shake_intensity" in tip: tip.shake_intensity = cfg.get("shake", 2.5)
	if "shake_on_hit_only" in tip: tip.shake_on_hit_only = cfg.get("shake_on_hit_only", true)

	tip.hit_targets.clear()

	tip.spark_type = 0
	tip.spark_scale = 0.4
	tip.spark_color = Color(1.6, 0.6, 0.1, 1.0)
	tip.aura_color = Color(1.0, 0.5, 0.0, 1.0)

	if not tip.hit.is_connected(_on_tip_hitbox_hit):
		tip.hit.connect(_on_tip_hitbox_hit)

	# 🌟 這裡只負責把數值配好，先確保是關的——實際開關時機交給 enable_hitbox()/disable_hitbox()，
	# 跟著動畫本來的 enable_weapon_hitbox/disable_weapon_hitbox 呼叫走
	_set_tip_shape_active(tip, false)

func _set_tip_shape_active(tip: Hitbox, active: bool) -> void:
	if not is_instance_valid(tip): return
	for child in tip.get_children():
		if child is CollisionShape2D:
			child.set_deferred("disabled", not active)

func _apply_charge_zoom(target_zoom: Vector2, duration: float = 0.2) -> void:
	if not (player is Player): return
	var camera = get_viewport().get_camera_2d()
	if camera:
		if _camera_tween and _camera_tween.is_valid(): _camera_tween.kill()
		_camera_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

		var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
		_camera_tween.set_speed_scale(speed_mult)

		if target_zoom == ZOOM_LEVELS[0]:
			var final_zoom = CombatManager.base_zoom if CombatManager.get("base_zoom") != null else Vector2(1.0, 1.0)
			_camera_tween.tween_property(camera, "zoom", final_zoom, duration)
			_camera_tween.tween_callback(func():
				if CombatManager.get("is_close_up_active") != null:
					CombatManager.is_close_up_active = false
			)
		else:
			if CombatManager.get("is_close_up_active") != null:
				CombatManager.is_close_up_active = true
			_camera_tween.tween_property(camera, "zoom", target_zoom, duration)

func spawn_spear_wave(wave_type: String) -> void:
	if not SPEAR_WAVE_SCENE: return
	var wave = SPEAR_WAVE_SCENE.instantiate()
	get_tree().current_scene.add_child(wave)

	wave.global_position = player.global_position + Vector2(30 * player.direction, -20)
	wave.direction = player.direction

	await get_tree().process_frame
	if not is_instance_valid(wave) or not wave.hitbox: return

	match wave_type:
		"ult_wave":
			wave.speed = 800.0
			wave.max_distance = 800.0
			wave.scale = Vector2(3.0 * player.direction, 3.0)

			wave.hitbox.damage_amount = 800
			wave.hitbox.absolute_knockback = Vector2(800.0 * player.direction, 0.0)
			wave.hitbox.knockback_force = Vector2(0.0, -700.0)
			wave.hitbox.attack_type = Damage.Type.HEAVY

			wave.hitbox.spark_type = 0
			wave.hitbox.spark_scale = 1.0
			wave.hitbox.spark_color = Color(1.0, 0.8, 0.2, 1.0)
			wave.hitbox.aura_color = Color(1.0, 0.5, 0.0, 1.0)
			wave.hitbox.hit_sfx_type = "hit_4"

func spawn_boomerang() -> void:
	if not BOOMERANG_SCENE: return
	var boomerang = BOOMERANG_SCENE.instantiate() as SpearBoomerang
	get_tree().current_scene.add_child(boomerang)

	boomerang.global_position = player.global_position + Vector2(30 * player.direction, -30)
	boomerang.direction = player.direction
	boomerang.thrower = player
	boomerang.weapon = self
	active_boomerang = boomerang

	await get_tree().process_frame
	if not is_instance_valid(boomerang) or not boomerang.hitbox: return

	boomerang.hitbox.damage_amount = 120
	boomerang.hitbox.attack_type = Damage.Type.HEAVY
	boomerang.hitbox.sticky_multi_hit = false
	boomerang.hitbox.max_hits = 1
	boomerang.hitbox.hit_interval = 0.15
	boomerang.hitbox.knockback_force = Vector2(20.0, -300.0)
	boomerang.hitbox.shake_intensity = 1.5
	boomerang.hitbox.shake_on_hit_only = true
	boomerang.hitbox.hit_sfx_type = "hit"

	var w_energy = 2.0
	var b_state = [false]

	boomerang.hitbox.hit.connect(func(hurtbox: Node):
		if is_instance_valid(player) and is_instance_valid(hurtbox.owner) and hurtbox.owner == player: return
		if not b_state[0]:
			# 🌟 一樣看「丟這一次槍」給固定值，不管命中幾個目標
			current_pozhen = minf(current_pozhen + POZHEN_GAIN_PER_HIT, MAX_POZHEN)
			if player.has_method("add_weapon_resource"):
				player.add_weapon_resource(WEAPON_ID, w_energy)
			if player.has_method("gain_martial_energy"):
				player.gain_martial_energy(NORMAL_HIT_MARTIAL_ENERGY)
			b_state[0] = true
	)

	boomerang.hitbox.spark_type = 0
	boomerang.hitbox.spark_scale = 0.4
	boomerang.hitbox.spark_color = Color(1.2, 1.5, 0.5, 1.0)
	boomerang.hitbox.aura_color = Color(0.8, 0.5, 0.2, 1.0)

func can_air_light() -> bool:
	if air_attack_locked or _get_ground_distance() < min_air_attack_height:
		return false
	return true

func can_air_skill() -> bool: return false

func can_use_heavy() -> bool:
	if not player.is_on_floor(): return false
	# 🌟 spear_is_deployed 故意不擋在這裡：槍還沒飛回來時按戰技鍵要能觸發「提早轉身」，
	# 真正的判斷交給 start_heavy_attack() 自己內部處理。
	# 但如果槍已經在手上、這一下按下去是要丟槍，破陣值沒滿就直接在這裡擋掉——
	# 讓輸入根本不會被緩衝、不會觸發 WeaponAttackState 進場，從源頭避免任何進場副作用 (例如刀鞘淡出) 空跑一次
	if not spear_is_deployed and current_pozhen < MAX_POZHEN: return false
	return true
