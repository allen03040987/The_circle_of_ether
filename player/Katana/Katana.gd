class_name Katana
extends Weapon
## 武器腳本：太刀 (Katana) 
## 負責處理太刀專屬的連段派生與大招運鏡 (已剝離共鳴與底層蓄力)。

# ==========================================
# 🎛️ 1. 武器核心參數
# ==========================================
@export_group("武器核心參數")
@export var combo_timeout: float = 0.3      
@export var no_sheath_steps: Array[int] = [1, 11, 12, 31, 32, 40 , 99] # 招式代號已更新
 

const WEAPON_ID: String = "katana"          
const DIMENSIONAL_SLASH_SCENE = preload("res://Explod/tscn/Dimensional Slash.tscn")
const SWORD_WAVE_SCENE = preload("res://player/Katana/c_3_wave.tscn")

# ==========================================
# 🥋 專屬武藝系統 (Martial Arts Loadout)
# ==========================================
@export var equipped_martial_arts: Array[String] = [
	"res://player/MartialArts/Katana/Art_Katana_1.gd", 
	"res://player/MartialArts/Katana/Art_Katana_2.gd", 
	"res://player/MartialArts/Katana/Art_Katana_3.gd"
]

func _ready() -> void:
	super._ready() 
	call_deferred("_delayed_load_arts")

func _delayed_load_arts() -> void:
	load_martial_arts(equipped_martial_arts)

const ZOOM_LEVELS = { 0: Vector2(1.0, 1.0), 1: Vector2(1.01, 1.01), 2: Vector2(1.02, 1.02), 3: Vector2(1.03, 1.03) }

# ==========================================
# 📖 2. 招式數據庫 (Data-Driven Combat Config)
# ==========================================

# 🗡️ [地面普攻字典] (代號: 1 ~ 5)
const DICT_LIGHT_GROUND = {
	1: {"anim": "katana/light_1", "hitbox_name": "light", "max_hits": 1, "interval": 0.0, "knockback": Vector2(100.0, 0.0), "base_dmg": 512, "hit_sfx_type": "hit_3", "energy": 200, "switch": 500, "action_type": Weapon.ActionType.NORMAL},
	2: {"anim": "katana/light_2", "hitbox_name": "light", "max_hits": 1, "interval": 0.0, "knockback": Vector2(150.0, 0.0), "base_dmg": 512, "hit_sfx_type": "hit", "energy": 2, "switch": 5, "action_type": Weapon.ActionType.NORMAL},
	3: {"anim": "katana/light_3", "hitbox_name": "light", "max_hits": 1, "interval": 0.0, "knockback": Vector2(200.0, 0.0), "base_dmg": 512, "hit_sfx_type": "hit", "energy": 2, "switch": 5, "action_type": Weapon.ActionType.NORMAL},
	4: {"anim": "katana/light_4", "hitbox_name": "light", "max_hits": 1, "interval": 0.0, "knockback": Vector2(200.0, 0.0), "base_dmg": 512, "hit_sfx_type": "hit", "energy": 2, "switch": 5, "action_type": Weapon.ActionType.NORMAL},
	5: {"anim": "katana/light_5", "hitbox_name": "light", "max_hits": 1, "interval": 0.0, "knockback": Vector2(400.0, 0.0), "shake": 30.0, "hit_sfx_type": "hit_5", "base_dmg": 645, "energy": 2, "switch": 5, "action_type": Weapon.ActionType.NORMAL},
	10: {"anim": "katana/light_enhanced_2", "hitbox_name": "light_2","type": Damage.Type.HEAVY,"knockback": Vector2(50.0, -400.0),"shake": 30.0,"shake_on_hit_only": false,"base_dmg": 560,"hit_sfx_type": "hit_2","energy": 10,"switch": 15,"spark_type": 1, "spark_scale": 0.8, "action_type": Weapon.ActionType.SKILL}
}


# 🦅 [空中連段字典] (代號: 11, 12)
const DICT_LIGHT_AIR = {
	11: { "anim": "katana/air_light_1", "hitbox_name": "air_light", "max_hits": 1, "interval": 0.0, "type": Damage.Type.LIGHT, "knockback": Vector2(20.0, -200.0), "base_dmg": 300,"hit_sfx_type": "hit", "energy": 2, "switch": 4, "action_type": Weapon.ActionType.NORMAL},
	12: { "anim": "katana/air_light_2", "hitbox_name": "air_light", "max_hits": 1, "interval": 0.0, "type": Damage.Type.LIGHT, "knockback": Vector2(200.0, -200.0), "base_dmg": 300,"hit_sfx_type": "hit", "energy": 2, "switch": 4, "action_type": Weapon.ActionType.NORMAL},
	13: { "anim": "katana/air_light_3", "hitbox_name": "air_light", "max_hits": 1, "interval": 0.0, "type": Damage.Type.LIGHT, "knockback": Vector2(300.0, -300.0), "shake": 10.0, "base_dmg": 350,"hit_sfx_type": "hit", "energy": 2, "switch": 4, "action_type": Weapon.ActionType.NORMAL},
}

# 💥 [戰技與大招字典] (代號: 21, 31, 32)
const DICT_HEAVY_ULT = {
	21: { "anim": "katana/heavy_1", "hitbox_name": "heavy", "type": Damage.Type.LIGHT, "knockback": Vector2(100.0, 0.0), "shake": 2.0, "shake_on_hit_only": true, "base_dmg": 200, "hit_sfx_type": "hit", "energy": 10, "switch": 15, "max_hits": 3, "interval": 0.1, "sticky": true },
	22: { "anim": "katana/heavy_2", "hitbox_name": "heavy_1", "type": Damage.Type.HEAVY, "knockback": Vector2(50.0, -100.0), "shake": 5.0, "shake_on_hit_only": true, "base_dmg": 200, "max_hits": 8, "interval": 0.05, "sticky": true, "hit_sfx_type": "hit", "energy": 15, "switch": 20 },
	23: { "anim": "katana/heavy_3", "hitbox_name": "heavy_2", "type": Damage.Type.HEAVY, "knockback": Vector2(50.0, -400.0), "shake": 5.0, "shake_on_hit_only": true, "base_dmg": 300, "max_hits": 3, "interval": 0.1, "sticky": true, "hit_sfx_type": "hit", "energy": 10, "switch": 15 }, 
	25: { "anim": "katana/air_heavy_start", "hitbox_name": "None", "base_dmg": 0 }, # 階段 1：下墜前準備（無判定）
	26: { "anim": "katana/air_heavy_loop", "hitbox_name": "air_light", "type": Damage.Type.LIGHT, "knockback": Vector2(200.0, -50.0), "base_dmg": 120, "max_hits": 5, "interval": 0.1, "hit_sfx_type": "hit", "sticky": true }, # 階段 2：下墜循環（帶有多段向下拖拽判定）
	27: { "anim": "katana/air_heavy_land", "hitbox_name": "None", "shake": 45.0, "shake_on_hit_only": false, "base_dmg": 0 },
	30: { "anim": "katana/sheath_enhanced_loop", "hitbox_name": "None", "base_dmg": 0 },
	31: { "anim": "katana/sheath_enhanced", "hitbox_name": "sheath_enhanced", "type": Damage.Type.HEAVY, "knockback": Vector2(0.0, -80.0), "shake": 0.0, "shake_on_hit_only": true, "base_dmg": 600, "hit_sfx_type": "hit", "energy": 25, "switch": 30, "max_hits": 12, "interval": 0.1, "sticky": true, "action_type": Weapon.ActionType.SKILL },
	40: { "anim": "katana/sheath_enhanced_2", "hitbox_name": "None", "base_dmg": 0 }
}

# ==========================================
# 🚀 3. 物理運算與手感參數
# ==========================================
@export_group("戰技中立設定")
@export var skill_neutral_friction_rate: float = 0.2 

@export_group("空戰設定 (Air Combat)")
@export var min_air_attack_height: float = 40.0 
@export var air_thrust_force: float = -150.0    
@export var air_skill_gravity_rate: float = 0.25 

# --- 內部狀態 ---
var current_active_hitbox: Hitbox = null

var _current_energy_reward: float = 0.0
var _current_switch_reward: float = 0.0
var _multi_hit_energy: bool = false
var _has_granted_resources_this_step: bool = false

var combo_step: int = 0
var last_attack_time: float = 0.0
var is_attacking: bool = false
var step_cooldown: float = 0.0
var _last_action_was_martial_art: bool = false  # 🔧 標記上一招是否為武藝卡帶，避免 combo_step 殘留誤觸連段

var air_attack_locked: bool = false             

var is_time_stop_triggered: bool = false 
var _camera_tween: Tween 
var _is_hitbox_locked: bool = false

# 🌟 劍意值資源 (原閃避充能)
var current_iai: float = 0.0                    
const MAX_IAI: float = 40.0 
var heavy_hold_timer: float = 0.0 
var _tsubame_zoom_phase: int = 0    
var is_wave_fired: bool = false
var _is_uppercut_launched: bool = false


var light_hold_timer: float = 0.0
var is_iai_buff_active: bool = false
var ghost_timer: float = 0.0
var _is_buff_triggered_this_cast: bool = false

func gain_iai(amount: float) -> void:
	current_iai = clampf(current_iai + amount, 0.0, MAX_IAI)
	print("✨ 獲得劍意！目前劍意值: ", current_iai, "/", MAX_IAI)

# ==========================================
# 🎬 實作 Weapon.gd 合約接口
# ==========================================
func start_light_attack() -> void:
	if step_cooldown > 0: return 
	step_cooldown = 0.15

	if is_instance_valid(active_martial_art):
		active_martial_art.cancel()
		active_martial_art = null

	if not is_attacking:
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - last_attack_time > combo_timeout or _last_action_was_martial_art:
			combo_step = 0
		_last_action_was_martial_art = false

	# --- 🦅 空戰邏輯 ---
	if not player.is_on_floor():
		if air_attack_locked or _get_ground_distance() < min_air_attack_height:
			return
		if combo_step == 11:
			combo_step = 12
		elif combo_step == 12: # 🌟 核心修改：12 之後接 13，並在此上鎖空戰權限
			combo_step = 13
			air_attack_locked = true 
		else:
			combo_step = 11
		is_attacking = true
		_play_air_step(combo_step)
		return

	# --- 🗡️ 陸戰邏輯 ---
	# 🌟 修改：將 27 從普攻接升龍斬的白名單中移除！
	if combo_step in [10, 21, 31]: # ⬅️ 移除了 27 和 31
		combo_step = 23
		is_attacking = true
		_is_uppercut_launched = false
		
		var input_dir = Input.get_axis("move_left", "move_right")
		if input_dir != 0 and player is Player:
			player.direction = 1 if input_dir > 0 else -1
			
		_play_heavy_ult_step(23)
		print("🌪️ 短按普攻：升龍斬起飛 (23)！")
		return

	# 清理殘留：打完 5段、10號大招，落地 (27) 或 31號終極燕返 時重置回起手式
	# 🌟 新增：把 27 加進重置名單
	if DICT_HEAVY_ULT.has(combo_step) or combo_step in [5, 10, 27, 31]:
		combo_step = 0
	
	combo_step += 1
	if not DICT_LIGHT_GROUND.has(combo_step):
		combo_step = 1

	is_attacking = true
	_play_light_step(combo_step)

func start_heavy_attack() -> void:
	if step_cooldown > 0:
		is_attacking = false
		return
	
	step_cooldown = 0.15
	air_attack_locked = false
	
	if is_instance_valid(active_martial_art):
		active_martial_art.cancel()
		active_martial_art = null
		
	if not is_attacking:
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - last_attack_time > combo_timeout or _last_action_was_martial_art:
			combo_step = 0
		_last_action_was_martial_art = false

	is_attacking = true
	is_time_stop_triggered = false
	
	# 🌟 空戰邏輯：進入第 1 階段「下墜前準備」
	if not player.is_on_floor():
		combo_step = 25
		heavy_hold_timer = 0.0
		
		var input_dir = Input.get_axis("move_left", "move_right")
		if input_dir != 0 and player is Player:
			player.direction = 1 if input_dir > 0 else -1
			
		player.velocity.y = air_thrust_force * 2.0
		_play_heavy_ult_step(25)
		print("🦅 空中重擊：躍起並進入下墜前準備 (25)")
		return

	# 🌟 陸戰邏輯：短按派生分流
	# 1. 普攻第一段 (1) 後短按戰技 ➔ 陸戰大招 (10)
	if combo_step == 1:
		combo_step = 10 # 🌟 修正
		heavy_hold_timer = 0.0
		
		var input_dir = Input.get_axis("move_left", "move_right")
		if input_dir != 0 and player is Player:
			player.direction = 1 if input_dir > 0 else -1
			
		_play_light_step(10) # 🌟 修正
		print("💥 普攻後短按戰技：陸戰大招 (10)！")
		return

	# 2. 在 10, 21, 31 (與落地27) 後，短按戰技 ➔ 二段重斬 (22)
	if combo_step in [10, 21, 27, 31]: # 🌟 修正
		combo_step = 22
		heavy_hold_timer = 0.0
		
		var input_dir = Input.get_axis("move_left", "move_right")
		if input_dir != 0 and player is Player:
			player.direction = 1 if input_dir > 0 else -1
			
		_play_heavy_ult_step(22)
		print("💥 短按戰技：二段高傷重斬 (22)！")
		return

	# 🌟 預設陸戰邏輯起手 (21)
	combo_step = 21
	heavy_hold_timer = 0.0
	
	var input_dir = Input.get_axis("move_left", "move_right")
	if input_dir != 0 and player is Player:
		player.direction = 1 if input_dir > 0 else -1
		
	_play_heavy_ult_step(21)
	
func update_timers_only(delta: float) -> void:
	if step_cooldown > 0: step_cooldown -= delta 
	
	# 🌟 燃燒劍意機制 (持續燃燒型 BUFF)
	if is_iai_buff_active:
		current_iai -= (1.0 / 0.5) * delta
		
		# 🌟 視覺化新增：魔人化殘影拖曳特效！
		ghost_timer += delta
		if ghost_timer >= 0.05:
			if player.has_method("add_ghost"):
				player.add_ghost()
			ghost_timer = 0.0
			
		# 劍意見底，關閉 BUFF
		if current_iai <= 0.0:
			current_iai = 0.0
			is_iai_buff_active = false
			print("🔽 劍意見底！BUFF 結束！(殘影消失，傷害與移速恢復正常)")
			
	if player.is_on_floor():
		air_attack_locked = false 
		if not is_attacking and combo_step in [11, 12, 13, 25, 26, 27]:
			combo_step = 0

func get_current_velocity(delta: float) -> Vector2:
	if is_instance_valid(active_martial_art) and active_martial_art.is_active:
		return active_martial_art.get_current_velocity(delta)
		
	if not is_attacking:
		return player.velocity

	if player.is_on_floor(): air_attack_locked = false

	# ==========================================
	# 🌟 普攻長按偵測：劍意爆發 (需滿一半方可啟動，隨後持續燃燒)
	# ==========================================
	if Input.is_action_pressed("attack"):
		light_hold_timer += delta
		
		# 按滿 0.3 秒，且只允許在閒置(0)或剛出第一刀(1)時攔截
		if light_hold_timer >= 0.3 and combo_step in [0, 1] and player.is_on_floor():
			if current_iai >= 20.0 and not is_iai_buff_active: 
				combo_step = 40
				light_hold_timer = 0.0
				_is_buff_triggered_this_cast = false # 🌟 新增：重置爆發標記
				
				# ❌ 刪除了原本寫在這裡的 is_iai_buff_active = true 與相機震動
				
				var input_dir = Input.get_axis("move_left", "move_right")
				if input_dir != 0 and player is Player:
					player.direction = 1 if input_dir > 0 else -1
					
				_play_heavy_ult_step(40)
				print("⚔️ 劍意湧動... (等待 0.5 秒爆氣)")
				
			elif is_iai_buff_active:
				light_hold_timer = 0.0
			else:
				if light_hold_timer == delta: 
					print("❌ 劍意不足一半 (需 20 點)，無法發動 BUFF！")
	else:
		light_hold_timer = 0.0

	# ==========================================
	# 🌟 戰技長按偵測 (只保留 21 號蓄力與大招)
	# ==========================================
	if combo_step in [21, 30]:
		if Input.is_action_pressed("heavy_attack"): 
			heavy_hold_timer += delta
			
			# 處於 21 號拔刀狀態下的長按分流 (只判定是否能進大招)
			if combo_step == 21 and heavy_hold_timer >= 0.25:
				if current_iai >= 40.0: 
					combo_step = 30
					_play_heavy_ult_step(30)
					print("⚡ 資源滿載！偵測到長按，轉入燕返蓄力狀態 (30)...")
					
			# 處於 30 號燕返蓄力中，滿 2.0 秒爆發
			elif combo_step == 30 and heavy_hold_timer >= 2.0:
				current_iai -= 40.0         
				combo_step = 31             
				heavy_hold_timer = 0.0
				_tsubame_zoom_phase = 0     
				is_wave_fired = false       
				
				var input_dir = Input.get_axis("move_left", "move_right")
				if input_dir != 0 and player is Player:
					player.direction = 1 if input_dir > 0 else -1
					
				_play_heavy_ult_step(31)
				print("💥 蓄力完成！終極燕返拔刀斬！！！")
				
		else:
			# 放開按鍵時的容錯分流
			if combo_step == 30:
				# 大招蓄力未滿提早放開 ➔ 順勢斬出二段重斬(22)
				combo_step = 22
				heavy_hold_timer = 0.0
				
				var input_dir = Input.get_axis("move_left", "move_right")
				if input_dir != 0 and player is Player:
					player.direction = 1 if input_dir > 0 else -1
					
				_play_heavy_ult_step(22)
				print("💨 蓄力半途釋放！化為二段重斬 (22)！")
				
			heavy_hold_timer = 0.0

	var new_x = player.velocity.x
	var new_y = player.velocity.y
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	var base_friction = player.FLOOR_ACCELERATION * (speed_mult * speed_mult) * delta

	# ==========================================
	# 🏃 物理位移狀態機 (純淨解耦版)
	# ==========================================
	if combo_step == 21: 
		new_x = move_toward(new_x, 0.0, base_friction * skill_neutral_friction_rate)
		
	elif combo_step == 22:
		new_x = move_toward(new_x, 0.0, base_friction)
		
	# 🌟 核心新增：獨立處理 40 號爆氣狀態的延遲引爆
	elif combo_step == 40:
		new_x = move_toward(new_x, 0.0, base_friction)
		
		var anim_time = player.animation_player.current_animation_position
		# 到達 0.5 秒的瞬間，且還沒引爆過
		if anim_time >= 0.5 and not _is_buff_triggered_this_cast:
			_is_buff_triggered_this_cast = true
			is_iai_buff_active = true
			
			# 給予 0.2 秒的肉感持續震動，強調爆發力
			if CombatManager.has_method("apply_camera_shake"):
				CombatManager.apply_camera_shake(30.0, 0.3)
				
			print("🔥 劍意正式爆發！開始持續燃燒！預計可維持 ", snapped(current_iai * 1.5, 0.1), " 秒！")
			
	elif combo_step == 23:
		new_x = move_toward(new_x, 0.0, base_friction * 0.3)
		var anim_time = player.animation_player.current_animation_position
		if anim_time >= 0.2 and not _is_uppercut_launched:
			_is_uppercut_launched = true
			new_y = air_thrust_force * 3.5 
			print("🚀 0.2秒到達！升龍斬正式起飛！")

	# ==========================================
	# 🌪️ 31 號終極燕返
	# ==========================================
	elif combo_step == 31: 
		new_x = move_toward(new_x, 0.0, base_friction * 5.0)
		new_y = 0.0 if player.is_on_floor() else player.default_gravity * air_skill_gravity_rate * delta
		
		var anim_time = player.animation_player.current_animation_position
		if anim_time >= 0.08 and not is_time_stop_triggered:
			is_time_stop_triggered = true 
			if player is Player: 
				player.invincible_time_left = 2.0 
			
		if anim_time >= 0.10 and _tsubame_zoom_phase == 0:
			_tsubame_zoom_phase = 1
			_apply_charge_zoom(Vector2(0.75, 0.75), 1.6) 
				
		if anim_time >= 1.76 and not is_wave_fired:
			is_wave_fired = true 
			if CombatManager.has_method("apply_camera_shake"): 
				CombatManager.apply_camera_shake(60.0) 
				
			if is_instance_valid(current_active_hitbox):
				current_active_hitbox.hit_targets.clear() 
				current_active_hitbox.max_hits = 1        
				current_active_hitbox.sticky_multi_hit = false 
				current_active_hitbox.damage_amount = 4500 
				current_active_hitbox.knockback_force = Vector2(200.0, -500.0) 
				current_active_hitbox.shake_intensity = 400.0
				_has_granted_resources_this_step = false
				
			_is_hitbox_locked = false 
			disable_hitbox() 
			enable_hitbox("CollisionShape2D2") 

	elif combo_step in [10, 11, 12, 13]:
		if player.is_on_floor():
			new_x = move_toward(new_x, 0.0, base_friction)
		else:
			new_x = move_toward(new_x, 0.0, base_friction)
			
			# 🌟 核心新增：空中普攻第三下 (13) 的強力滯空控制
			if combo_step == 13:
				# 這裡套用 0.08 倍的極低重力，讓老爸幾乎定格在半空中慢慢滑行
				# 你可以自由調整這個倍率（越接近 0.0 越飄，若寫死 new_y = 0.0 則是完全水平不下降）
				new_y += player.default_gravity * 0.1 * delta

	# ==========================================
	# 🦅 三段式下墜戰技
	# ==========================================
	elif combo_step == 25:
		new_x = move_toward(new_x, 0.0, base_friction * 0.2)
		new_y += player.default_gravity * 0.5 * delta

	elif combo_step == 26:
		new_x = move_toward(new_x, 0.0, base_friction * 0.5)
		new_y = 800.0 * speed_mult 
		if player.is_on_floor():
			combo_step = 27
			heavy_hold_timer = 0.0  
			_play_heavy_ult_step(27)
			if CombatManager.has_method("apply_camera_shake"): 
				CombatManager.apply_camera_shake(25.0)
			print("💥 觸地！轉換為落地純演出 (27)，長按窗口開啟")

	elif combo_step == 27:
		new_x = move_toward(new_x, 0.0, base_friction)
		new_y = 0.0
	else:
		new_x = move_toward(new_x, 0.0, base_friction)

	return Vector2(new_x, new_y)
	
func is_handling_gravity() -> bool:
	if is_instance_valid(active_martial_art) and active_martial_art.is_active:
		if active_martial_art.has_method("is_handling_gravity"): return active_martial_art.is_handling_gravity()
			
	# 🌟 修改：將 13（空中普攻第三段）加入，允許它在空中時全權接管重力更新
	if not player.is_on_floor() and combo_step in [25, 26, 31, 13]: return true
	return false
# ==========================================
# 🎬 招式結束判定 
# ==========================================
func is_attack_finished() -> bool:
	if is_instance_valid(active_martial_art):
		if active_martial_art.is_active:
			return false 
		else:
			active_martial_art = null
			_is_hitbox_locked = true 
			disable_hitbox()
			is_attacking = false
			last_attack_time = Time.get_ticks_msec() / 1000.0
			if not requires_sheath() and player.get("scabbard"):
				player.scabbard.fade_in()
			_last_action_was_martial_art = true # 🔧 武藝卡帶自然收招，標記讓下一次攻擊強制重置 combo_step
			return true

	if not is_attacking: return true
	
	if not player.animation_player.is_playing():
		if combo_step == 25:
			combo_step = 26
			_play_heavy_ult_step(26)
			return false 
			
		# 🌟 核心修改：只保留 21 號拔刀的長按扣留
		if combo_step == 21:
			if Input.is_action_pressed("heavy_attack"):
				return false 
			
		player.is_input_locked = false 
		if combo_step in [11, 12, 13]: air_attack_locked = true
			
		last_attack_time = Time.get_ticks_msec() / 1000.0
		step_cooldown = 0.0
		light_hold_timer = 0.0 # 🌟 加回這行
		_is_hitbox_locked = true
		disable_hitbox()
		
		if combo_step == 31 or _tsubame_zoom_phase > 0:
			_tsubame_zoom_phase = 0
			_apply_charge_zoom(ZOOM_LEVELS[0], 0.4)
		
		if not requires_sheath() and player.get("scabbard"): 
			player.scabbard.fade_in()
			
		return true
		
	return false

func cancel_attack() -> void:
	if is_instance_valid(active_martial_art):
		active_martial_art.cancel()
		active_martial_art = null

	if not player.is_on_floor() and combo_step in [11, 12, 13]: 
		air_attack_locked = true
		
	player.is_input_locked = false 
	_apply_charge_zoom(ZOOM_LEVELS[0])
	
	is_attacking = false
	_is_uppercut_launched = false
	combo_step = 0
	_last_action_was_martial_art = false
	step_cooldown = 0.0
	_tsubame_zoom_phase = 0
	heavy_hold_timer = 0.0
	light_hold_timer = 0.0
	
	if is_time_stop_triggered:
		is_time_stop_triggered = false
		if player.has_method("clear_time_stop"): player.clear_time_stop() 
	
	_is_hitbox_locked = true 
	disable_hitbox()
	if player.get("scabbard"): player.scabbard.fade_in()
		
func requires_sheath() -> bool:
	if combo_step == 0: return false
	return combo_step not in no_sheath_steps
	
# ==========================================
# ⚙️ 內部實作與接口
# ==========================================
func _play_light_step(step: int) -> void:
	disable_hitbox()
	var config: Dictionary = DICT_LIGHT_GROUND[step]
	_apply_hitbox_config(config)
	if config.has("sfx") and config["sfx"] != null: AudioManager.play_sfx(config["sfx"], -8.0)
	if player.animation_player.current_animation == config["anim"]: player.animation_player.stop()
	player.play_safe_anim(config["anim"])

func _play_heavy_ult_step(step: int) -> void:
	disable_hitbox()
	var config: Dictionary = DICT_HEAVY_ULT[step]
	_apply_hitbox_config(config)
	if config.has("sfx") and config["sfx"] != null: AudioManager.play_sfx(config["sfx"], -5.0)
	combo_step = step
	if player.animation_player.current_animation == config["anim"]: player.animation_player.stop()
	player.play_safe_anim(config["anim"])

func _play_air_step(step: int) -> void:
	disable_hitbox() 
	var config: Dictionary = DICT_LIGHT_AIR[step]
	_apply_hitbox_config(config)
	player.velocity.y = air_thrust_force 
	if player.animation_player.current_animation == config["anim"]: player.animation_player.stop()
	player.play_safe_anim(config["anim"])

func _play_martial_art_attack(config: Dictionary) -> void:
	disable_hitbox()
	_apply_hitbox_config(config)
	if current_active_hitbox:
		if config.has("spark_type"): current_active_hitbox.spark_type = config["spark_type"]
		if config.has("spark_scale"): current_active_hitbox.spark_scale = config["spark_scale"]
	if config.has("sfx") and config["sfx"] != null: AudioManager.play_sfx(config["sfx"], -5.0)
	if player.animation_player.current_animation == config["anim"]: player.animation_player.stop()
	player.play_safe_anim(config["anim"])
	
func _apply_hitbox_config(config: Dictionary) -> void:
	_is_hitbox_locked = false 
	current_action_type = config.get("action_type", Weapon.ActionType.NONE)
	var target_hitbox_name = config.get("hitbox_name", "Hitbox")
	var hitbox := get_node_or_null(target_hitbox_name) as Hitbox
	
	if hitbox:
		var final_dmg = float(config["base_dmg"])
		if is_iai_buff_active:
			final_dmg *= 1.3 
		hitbox.damage_amount = max(1, roundi(final_dmg))
		hitbox.max_hits = config.get("max_hits", 1)
		hitbox.hit_sfx_type = config.get("hit_sfx_type", "")
		hitbox.hit_interval = config.get("interval", 0.0)
		hitbox.attack_type = config.get("type", Damage.Type.LIGHT)
		hitbox.knockback_force = config.get("knockback", Vector2.ZERO)
		var base_kb_x = abs(hitbox.knockback_force.x)
		hitbox.absolute_knockback = Vector2(base_kb_x * player.direction, hitbox.knockback_force.y)
		if "shake_intensity" in hitbox: hitbox.shake_intensity = config.get("shake", 2.5)
		if "shake_on_hit_only" in hitbox: hitbox.shake_on_hit_only = config.get("shake_on_hit_only", true)
		hitbox.sticky_multi_hit = config.get("sticky", false)
		if "energy_reward" in hitbox: hitbox.energy_reward = float(config.get("energy", 0))
		if "switch_reward" in hitbox: hitbox.switch_reward = float(config.get("switch", 0))
		hitbox.spark_type = 0; hitbox.spark_scale = 0.3; hitbox.spark_color = Color(0.7, 1.5, 0.5, 1.0); hitbox.aura_color = Color(0, 1, 1, 1)
		hitbox.hit_targets.clear() 
		_current_energy_reward = float(config.get("energy", 0))
		_multi_hit_energy = config.get("multi_hit_energy", false)
		_has_granted_resources_this_step = false
		if current_active_hitbox and current_active_hitbox.hit.is_connected(_on_hitbox_hit):
			current_active_hitbox.hit.disconnect(_on_hitbox_hit)
		current_active_hitbox = hitbox
		if not current_active_hitbox.hit.is_connected(_on_hitbox_hit):
			current_active_hitbox.hit.connect(_on_hitbox_hit)

func _on_hitbox_hit(hurtbox: Node) -> void:
	if is_instance_valid(player) and is_instance_valid(hurtbox.owner) and hurtbox.owner == player: return
	if _multi_hit_energy or not _has_granted_resources_this_step:
		if _current_energy_reward > 0:
			if player.has_method("add_weapon_resource"): player.add_weapon_resource(WEAPON_ID, _current_energy_reward)
		gain_iai(0.5)
		_has_granted_resources_this_step = true
		
func _get_ground_distance() -> float:
	var space_state = player.get_world_2d().direct_space_state
	var query = PhysicsRayQueryParameters2D.create(player.global_position, player.global_position + Vector2(0, 1000))
	query.collision_mask = 1 
	var result = space_state.intersect_ray(query)
	if result: return player.global_position.distance_to(result.position)
	return 1000.0 

func _apply_charge_zoom(target_zoom: Vector2, duration: float = 0.2) -> void:
	if not (player is Player): return
	if player.name.begins_with("Phantom"): return
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
				if CombatManager.get("is_close_up_active") != null: CombatManager.is_close_up_active = false
			)
		else:
			if CombatManager.get("is_close_up_active") != null: CombatManager.is_close_up_active = true
			_camera_tween.tween_property(camera, "zoom", target_zoom, duration)

func can_air_light() -> bool:
	if air_attack_locked or _get_ground_distance() < min_air_attack_height: return false
	return true

func can_use_heavy() -> bool:
	if not player.is_on_floor(): 
		if _get_ground_distance() < min_air_attack_height: return false
		return true 
	if combo_step in [21, 27]: return true 
	return true

func export_weapon_data() -> Dictionary:
	return { "current_iai": current_iai }

func import_weapon_data(data: Dictionary) -> void:
	current_iai = data.get("current_iai", 0) 
	
func enable_hitbox(shape_name: String = "") -> void:
	if _is_hitbox_locked: return
	if current_active_hitbox:
		for child in current_active_hitbox.get_children():
			if child is CollisionShape2D:
				if shape_name == "" or child.name == shape_name: child.set_deferred("disabled", false)

func disable_hitbox(shape_name: String = "") -> void:
	if current_active_hitbox:
		for child in current_active_hitbox.get_children():
			if child is CollisionShape2D:
				if shape_name == "" or child.name == shape_name: child.set_deferred("disabled", true)
