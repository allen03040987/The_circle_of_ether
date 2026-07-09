class_name Player
extends CharacterBody2D
## 玩家總控制樞紐 (Player Controller Hub)
## 負責協調狀態機、輸入緩衝、武器切換、受擊判定與特效調度。

enum Direction { LEFT = -1, RIGHT = 1 }

# ==========================================
# 📐 物理與基礎屬性
# ==========================================
const WALK_SPEED := 200.0
const RUN_SPEED := 350.0
const JUMP_VELOCITY := -410.0
const FLOOR_ACCELERATION := RUN_SPEED / 0.04
const AIR_ACCELERATION := RUN_SPEED / 0.03
const TERMINAL_VELOCITY := 700.0
const WALL_JUMP_VELOCITY := Vector2(300, -500) 

var default_gravity := ProjectSettings.get("physics/2d/default_gravity") as float
var external_force := Vector2.ZERO

signal weapon_switched(new_weapon: Weapon)

@onready var graphics: Node2D = $Graphics
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var state_machine: StateMachine = $StateMachine
@onready var stats: Node = Game.player_stats
@onready var weapon_slot: Node2D = $Graphics/WeaponSlot
@onready var scabbard: Node2D = $ScabbardContainer

@onready var coyote_timer: Timer = $CoyoteTimer
@onready var jump_request_timer: Timer = $JumpRequestTimer
@onready var slide_request_timer: Timer = $SlideRequestTimer
@onready var slide_cooldown_timer: Timer = $SlideCooldownTimer
@onready var guard_request_timer: Timer = $GuardRequestTimer
@onready var invincible_timer: Timer = $InvincibleTimer
@onready var dash_chain_timer: Timer = $DashChainTimer

@onready var foot_checker: RayCast2D = $Graphics/FootChecker
@onready var hand_checker: RayCast2D = $Graphics/HandChecker
@onready var wall_slide_checker: RayCast2D = $WallSlideChecker
@onready var interaction_icon: AnimatedSprite2D = $InteractionIcon

var direction := Direction.RIGHT :
	set(v):
		direction = v
		if not is_node_ready(): await ready
		graphics.scale.x = direction

var locked_facing_dir: int = 0
var invincible_time_left: float = 0.0 
var interacting_with: Array[Interactable] = []
var is_dead := false
var is_walking := false ## 目前這一刻走路(true)還是奔跑(false)——由 Run.gd 每幀依加速進度動態更新，Jump/Fall 也會讀這個決定空中極速
var move_ramp_time: float = 0.0 ## 走路連續加速到奔跑的進度計時，停下來(進 Idle)就會歸零
var is_force_walk_zone: bool = false ## 強制走路區域（目前只有大本營場景在用；未來的「安全區」觸發器也應該透過 update_movement_by_scene() 設定這個旗標）

# ==========================================
# ⚔️ 戰鬥狀態與輸入緩存
# ==========================================
@export var can_combo := false
var is_combo_requested := false
var is_heavy_requested := false
var is_martial_requested := false
var requested_martial_slot := 0

signal martial_mode_changed(is_active: bool)
var _last_martial_mode := false

var is_weapon_invincible := false
var is_input_locked := false

var combo_buffer_time: float = 0.0
var heavy_buffer_time: float = 0.0
var martial_buffer_time: float = 0.0
const ATTACK_BUFFER_DURATION: float = 0.2

var is_perfect_dodging := false
var pending_damage = null
var current_weapon: Weapon = null

# ==========================================
# 🔋 武藝能量 (Martial Art Energy)
# ==========================================
## 全域資源(不分武器)：非武藝招式命中、完美閃避都能獲得，施放武藝依各招 energy_cost 扣除
const MAX_MARTIAL_ENERGY: float = 10.0
var martial_energy: float = 0.0

func gain_martial_energy(amount: float) -> void:
	martial_energy = clampf(martial_energy + amount, 0.0, MAX_MARTIAL_ENERGY)

func consume_martial_energy(amount: float) -> bool:
	if martial_energy < amount: return false
	martial_energy -= amount
	return true

const WEAPON_SWITCH_COOLDOWN: float = 1.0
var weapon_switch_cooldown_timer: float = 0.0

# ==========================================
# 🧰 裝備庫與初始化
# ==========================================
const WEAPON_BLUEPRINTS: Dictionary = {
	"katana": preload("res://player/Katana/katana.tscn"), 
	"spear": preload("res://player/Spear/spear.tscn"),
	"talisman": preload("res://player/Talisman/talisman.tscn"),
	"sickle": preload("res://player/Sickle/Sickle.tscn"),
}

@export var equipped_weapon_ids: Array[String] = ["katana", "spear"]

## 初始化玩家，載入裝備並根據場景更新移動模式
func _ready() -> void:
	equip_loadout(equipped_weapon_ids)
	var is_base = false
	var current_world = get_tree().current_scene
	if current_world is World and "is_base" in current_world:
		is_base = current_world.is_base
		
	update_movement_by_scene(is_base)
	if not Game.settings_changed.is_connected(_on_global_settings_changed):
		Game.settings_changed.connect(_on_global_settings_changed)

## 根據提供的 ID 陣列實例化並裝備武器
func equip_loadout(weapon_ids: Array[String]) -> void:
	var saved_weapons_data = {}
	for i in range(weapon_slot.get_child_count()):
		if i < equipped_weapon_ids.size():
			var old_w_id = equipped_weapon_ids[i]
			var old_weapon = weapon_slot.get_child(i)
			if old_w_id in weapon_ids and old_weapon.has_method("export_weapon_data"):
				saved_weapons_data[old_w_id] = old_weapon.export_weapon_data()

	equipped_weapon_ids = weapon_ids
	
	for child in weapon_slot.get_children():
		child.queue_free()
		weapon_slot.remove_child(child) 
	
	current_weapon = null

	for w_id in equipped_weapon_ids:
		if WEAPON_BLUEPRINTS.has(w_id):
			var new_weapon = WEAPON_BLUEPRINTS[w_id].instantiate()
			weapon_slot.add_child(new_weapon)
			new_weapon.hide()
			new_weapon.player = self

			if saved_weapons_data.has(w_id) and new_weapon.has_method("import_weapon_data"):
				new_weapon.import_weapon_data(saved_weapons_data[w_id])
		else:
			printerr("❌ 找不到武器藍圖：", w_id)
			
	if weapon_slot.get_child_count() > 0:
		_force_equip_weapon(weapon_slot.get_child(0))

# ==========================================
# ⏳ 核心物理與計時更新
# ==========================================
## 處理系統輸入鎖定、武器內部計時器與玩家狀態緩衝倒數
func _process(delta: float) -> void:
	if Input.is_physical_key_pressed(KEY_ALT):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		
	var current_martial_mode = Input.is_action_pressed("martial_modifier") and not is_input_locked
	if current_martial_mode != _last_martial_mode:
		_last_martial_mode = current_martial_mode
		martial_mode_changed.emit(current_martial_mode)
	
	interaction_icon.visible = not interacting_with.is_empty()
	
	var unscaled_delta = delta / Engine.time_scale if Engine.time_scale > 0.0 else 0.0
	if unscaled_delta > 0.1: unscaled_delta = 0.0166 
	
	for weapon in weapon_slot.get_children():
		if is_instance_valid(weapon) and weapon.has_method("update_timers_only"):
			weapon.update_timers_only(unscaled_delta)

	if invincible_time_left > 0:
		invincible_time_left -= unscaled_delta
		if not is_perfect_dodging: graphics.modulate.a = 0.8 
	else:
		graphics.modulate.a = 1.0
		is_perfect_dodging = false
	
	if time_stop_left > 0:
		time_stop_left -= unscaled_delta
		if time_stop_left <= 0: clear_time_stop()
		
	if weapon_switch_cooldown_timer > 0: weapon_switch_cooldown_timer -= unscaled_delta
		
	if combo_buffer_time > 0 and not is_input_locked: combo_buffer_time -= unscaled_delta
	else: is_combo_requested = false

	if heavy_buffer_time > 0 and not is_input_locked: heavy_buffer_time -= unscaled_delta
	else: is_heavy_requested = false
		
	if martial_buffer_time > 0 and not is_input_locked: martial_buffer_time -= unscaled_delta
	else: is_martial_requested = false
	
	if is_input_locked:
		is_combo_requested = false; is_heavy_requested = false; is_martial_requested = false
		combo_buffer_time = 0.0; heavy_buffer_time = 0.0; martial_buffer_time = 0.0

	if is_on_floor() and is_instance_valid(current_weapon) and "air_attack_locked" in current_weapon:
		current_weapon.air_attack_locked = false

	var current_state = state_machine.current_state.name.to_lower() if is_instance_valid(state_machine.current_state) else ""
	var is_in_hitstun = current_state in ["hurt", "launched", "dying"]

	if not is_input_locked and not is_dead and not is_in_hitstun and weapon_slot.get_child_count() >= 2:
		if weapon_switch_cooldown_timer <= 0 and Input.is_action_just_pressed("switch_weapon"):
			_execute_weapon_switch()
			weapon_switch_cooldown_timer = WEAPON_SWITCH_COOLDOWN

# ==========================================
# 🎮 輸入攔截與緩衝
# ==========================================
## 攔截被鎖定時的無效操作
func _input(event: InputEvent) -> void:
	if is_input_locked:
		if event.is_action("ui_cancel") or event.is_action("ui_accept"): return 
		if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
			get_viewport().set_input_as_handled() 
		return

## 處理玩家主動操作的輸入緩衝 (跳躍、攻擊、閃避)
func _unhandled_input(event: InputEvent) -> void:
	if is_input_locked: return 
		
	if event.is_action_pressed("toggle_walk"): toggle_walk_mode()
		
	var is_mod_held = Input.is_action_pressed("martial_modifier")
	
	if is_mod_held:
		if event.is_action_pressed("art_1") and _has_martial_art(0):
			is_martial_requested = true; is_combo_requested = true; requested_martial_slot = 1
			martial_buffer_time = ATTACK_BUFFER_DURATION; combo_buffer_time = ATTACK_BUFFER_DURATION
			get_viewport().set_input_as_handled() 
		elif event.is_action_pressed("art_2") and _has_martial_art(1):
			is_martial_requested = true; is_combo_requested = true; requested_martial_slot = 2
			martial_buffer_time = ATTACK_BUFFER_DURATION; combo_buffer_time = ATTACK_BUFFER_DURATION
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("art_3") and _has_martial_art(2):
			is_martial_requested = true; is_combo_requested = true; requested_martial_slot = 3
			martial_buffer_time = ATTACK_BUFFER_DURATION; combo_buffer_time = ATTACK_BUFFER_DURATION
			get_viewport().set_input_as_handled()
	else:
		if event.is_action_pressed("attack"):
			var can_buffer = true
			if not is_on_floor() and is_instance_valid(current_weapon) and current_weapon.has_method("can_air_light"):
				can_buffer = current_weapon.can_air_light()
			if can_buffer: is_combo_requested = true; combo_buffer_time = ATTACK_BUFFER_DURATION
		elif event.is_action_pressed("heavy_attack"):
			var can_buffer = true
			if is_instance_valid(current_weapon) and current_weapon.has_method("can_use_heavy"):
				can_buffer = current_weapon.can_use_heavy()
			if can_buffer: is_heavy_requested = true; heavy_buffer_time = ATTACK_BUFFER_DURATION
		
	if event.is_action_pressed("guard"): guard_request_timer.start()

	if event.is_action_pressed("jump"): jump_request_timer.start()
	if event.is_action_released("jump"):
		jump_request_timer.stop()
		if velocity.y < JUMP_VELOCITY / 2: velocity.y = JUMP_VELOCITY / 2

	if event.is_action_pressed("slide"): slide_request_timer.start()
	if event.is_action_pressed("interact") and not interacting_with.is_empty():
		interacting_with.back().interact()

# ==========================================
# 🛡️ 行為介面與受擊判定
# ==========================================
## 安全播放動畫，避免重複呼叫打斷當前幀
func play_safe_anim(anim_name: String) -> void:
	if animation_player.has_animation(anim_name):
		if animation_player.current_animation != anim_name: animation_player.play(anim_name)
	else: printerr("❌ 找不到動畫: ", anim_name)

## 套用外部擊退力與武器自訂速度的滑行函數
func custom_move_and_slide() -> void:
	if pending_damage != null: return
	var original_x = velocity.x
	velocity.x += external_force.x
	move_and_slide()
	velocity.x = original_x 
	external_force.x = move_toward(external_force.x, 0.0, 1500.0 * get_physics_process_delta_time())

## 實際計算傷害、擊退力並分發受擊狀態
func take_damage(temp_damage: Damage) -> void:
	if is_dead or state_machine.current_state.name.to_lower() == "dying": return
	if invincible_time_left > 0 or invincible_timer.time_left > 0: return
	
	is_combo_requested = false; is_heavy_requested = false
	combo_buffer_time = 0.0; heavy_buffer_time = 0.0
	
	stats.health -= temp_damage.amount
	velocity = Vector2.ZERO 
	
	match temp_damage.type:
		Damage.Type.NO_STUN: pending_damage = null
		Damage.Type.HEAVY:
			grant_invincibility(0.6) 
			state_machine.call_deferred("transition_to", "Launched") 
		Damage.Type.THROW: pending_damage = null
		_: 
			grant_invincibility(0.35) 
			state_machine.call_deferred("transition_to", "Hurt")
			
	if stats.health <= 0: state_machine.call_deferred("transition_to", "Dying")

## 給予玩家絕對無敵時間
func grant_invincibility(duration: float) -> void:
	invincible_time_left = duration
	invincible_timer.start(duration)

## Hurtbox 偵測到碰撞時的預處理邏輯
func _on_hurtbox_hurt(hitbox: Hitbox) -> void:
	if is_dead or state_machine.current_state.name.to_lower() == "dying": return

	var final_amount: int = hitbox.get("damage_amount") if "damage_amount" in hitbox else 1
	var final_type: int = hitbox.get("attack_type") if "attack_type" in hitbox else Damage.Type.LIGHT
	var final_source_type: int = hitbox.get("source_type") if "source_type" in hitbox else Damage.SourceType.MELEE
	
	var final_knockback := Vector2.ZERO
	if "absolute_knockback" in hitbox and hitbox.absolute_knockback != Vector2.ZERO:
		final_knockback = hitbox.absolute_knockback
	else:
		var raw_force := Vector2(150.0, 0.0)
		if "knockback_force" in hitbox: raw_force = hitbox.knockback_force
		
		var attacker_pos = hitbox.global_position
		if is_instance_valid(hitbox.owner):
			attacker_pos = hitbox.owner.global_position
			
		var dir_x : float = sign(global_position.x - attacker_pos.x)
		if dir_x == 0: dir_x = -direction 
		final_knockback = Vector2(raw_force.x * dir_x, raw_force.y)
		
	if final_amount <= 0:
		external_force = final_knockback
		return 

	if invincible_time_left > 0 or invincible_timer.time_left > 0: return

	if state_machine.current_state.name.to_lower() == "slide":
		if state_machine.current_state.has_method("trigger_perfect_dodge"):
			state_machine.current_state.trigger_perfect_dodge()
		if hitbox.has_method("suppress_feedback"):
			hitbox.suppress_feedback()
		return

	# 🛡️ 格擋：判定完全交給 GuardState.try_block() 現場裁決（是否還在判定窗內、是否為黃圈技），
	# 不使用全域無敵旗標，避免長時間開啟的敵人 hitbox 在無敵結束後補上第二下傷害
	if state_machine.current_state.name.to_lower() == "guard":
		if state_machine.current_state.has_method("try_block") and state_machine.current_state.try_block(hitbox):
			if hitbox.has_method("suppress_feedback"):
				hitbox.suppress_feedback()
			return

	# 🌟 武藝卡帶的格擋反擊接口（例如逆鱗返這類「彈反型招式」）：只有武藝自己回報「接住了」才完全格擋這一下
	# ⚠️ 「黃圈技」的攻擊會標記 requires_countermeasure，只有專屬的「對策技」能破解，通用彈反型招式對它無效
	var is_yellow_circle_attack = ("requires_countermeasure" in hitbox) and hitbox.requires_countermeasure
	if not is_yellow_circle_attack and is_instance_valid(current_weapon) and is_instance_valid(current_weapon.get("active_martial_art")):
		var active_art = current_weapon.active_martial_art
		if active_art.is_active and active_art.has_method("trigger_counter") and active_art.trigger_counter():
			if hitbox.has_method("suppress_feedback"):
				hitbox.suppress_feedback()
			return

	pending_damage = {
		"source": hitbox, "amount": final_amount, "type": final_type,
		"source_type": final_source_type, "knockback_force": final_knockback
	}
	
	var temp_damage = Damage.new()
	temp_damage.amount = final_amount
	temp_damage.type = final_type
	temp_damage.source_type = final_source_type
	temp_damage.knockback_force = final_knockback
	temp_damage.source = hitbox.owner if is_instance_valid(hitbox.owner) else hitbox
	
	take_damage(temp_damage)

## 觸發死亡序列
func die() -> void:
	if is_dead: return
	is_dead = true
	invincible_timer.stop()
	graphics.modulate.a = 1.0
	is_perfect_dodging = false
	clear_time_stop()
	if has_node("CanvasLayer/GameOverScreen"): $CanvasLayer/GameOverScreen.show_game_over()

## 動畫幀調用的強制位移推力
func strike_impulse(strength: float) -> void:
	var current_state = state_machine.current_state.name.to_lower()
	if current_state in ["hurt", "launched", "dying"]: return
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	velocity.x = direction * (strength * speed_mult)

# ==========================================
# 🎨 特效與環境互動 
# ==========================================
## 生成殘影特效 (閃避或 BUFF 期間)：實際生成邏輯統一交給 CombatManager，這裡只組裝玩家專屬參數
## color 由呼叫端指定（不同情境的殘影顏色不一樣，例如 Slide 用白色、太刀強化用亮綠藍色）
func add_ghost(color: Color = Color(1.0, 1.0, 1.0, 0.4)) -> void:
	CombatManager.spawn_ghost($Graphics/Sprite2D, global_position + Vector2(0, -29), graphics.scale, color)

func can_wall_slide() -> bool: return is_on_wall() and hand_checker.is_colliding() and foot_checker.is_colliding()
func register_interactable(v: Interactable) -> void:
	if state_machine.current_state.name.to_lower() != "dying" and v not in interacting_with: interacting_with.append(v)
func unregister_interactable(v: Interactable) -> void: interacting_with.erase(v)

## force_walk 目前只有 World.is_base（大本營場景）在用；未來的「安全區」觸發器也應該呼叫這個方法
## 來鎖死走路速度——不管自動奔跑設定或衝刺銜接與否，強制走路區域一律優先
func update_movement_by_scene(force_walk: bool) -> void:
	is_force_walk_zone = force_walk
	if force_walk:
		move_ramp_time = 0.0
		is_walking = true
		if state_machine.current_state != null and state_machine.current_state.name.to_lower() == "run":
			play_safe_anim("walking")

## 快捷鍵版本的「自動奔跑」開關，跟設定面板裡的勾選框是同一份設定
func toggle_walk_mode() -> void:
	if is_force_walk_zone: return
	Game.config_auto_run = !Game.config_auto_run
	Game.save_settings()
	Game.settings_changed.emit()

func _on_global_settings_changed() -> void:
	var is_base = false
	var current_world = get_tree().current_scene
	if current_world is World and "is_base" in current_world: is_base = current_world.is_base
	update_movement_by_scene(is_base)

@export_group("VFX: 基礎通用 (環境/煙塵)")
@export var vfx_common: Dictionary = {}
@export_group("VFX: 武器特效與火花")
@export var vfx_weapon: Dictionary = {}
@export_group("VFX: 系統反饋 (蓄力/受擊)")
@export var vfx_system: Dictionary = {}

## 生成通用或武器綁定的視覺特效
func spawn_anim_vfx(
	vfx_name: String, offset_x: float = 0.0, offset_y: float = 0.0, custom_scale: Vector2 = Vector2(1.0, 1.0), 
	rotation_deg: float = 0.0, custom_color: Color = Color.WHITE, aura_color: Color = Color.WHITE, 
	detach: bool = true, custom_z_index: int = 1, raw_intensity: float = 1.0
) -> void:
	var vfx_scene = null
	if vfx_common.has(vfx_name): vfx_scene = vfx_common[vfx_name]
	elif vfx_weapon.has(vfx_name): vfx_scene = vfx_weapon[vfx_name]
	elif vfx_system.has(vfx_name): vfx_scene = vfx_system[vfx_name]
	if vfx_scene == null: return 
	
	var vfx = vfx_scene.instantiate()
	if CombatManager.has_method("_apply_anti_timestop"): CombatManager._apply_anti_timestop(vfx)
		
	if detach:
		get_parent().add_child(vfx)
		vfx.global_position = global_position + Vector2(offset_x * direction, offset_y)
		vfx.z_index = self.z_index + custom_z_index 
	else:
		self.add_child(vfx)
		vfx.position = Vector2(offset_x * direction, offset_y)
		vfx.z_index = custom_z_index

	vfx.scale = Vector2(direction * custom_scale.x, custom_scale.y)
	vfx.rotation_degrees = rotation_deg * direction
	var hdr_color = Color(custom_color.r * raw_intensity, custom_color.g * raw_intensity, custom_color.b * raw_intensity, custom_color.a)
	CombatManager._apply_vfx_colors(vfx, hdr_color, aura_color)

# ==========================================
# 📊 系統調度與資源 
# ==========================================
var time_stop_left: float = 0.0
var current_time_scale: float = 1.0

## 觸發遊戲時停機制
func trigger_time_stop(real_duration: float, target_time_scale: float) -> void:
	if target_time_scale < current_time_scale or real_duration > time_stop_left:
		current_time_scale = target_time_scale; time_stop_left = real_duration 
		if CombatManager.has_method("set_domain_time"): CombatManager.set_domain_time(target_time_scale)

## 清除遊戲時停機制
func clear_time_stop() -> void:
	if current_time_scale != 1.0 or time_stop_left > 0:
		current_time_scale = 1.0; time_stop_left = 0.0; animation_player.speed_scale = 1.0
		if CombatManager.has_method("clear_domain_time"): CombatManager.clear_domain_time()

var current_outro_buff: String = ""

func get_all_weapons_martial_arts() -> Dictionary:
	var current_config = {"katana": ["", "", ""], "spear": ["", "", ""], "talisman": ["", "", ""], "sickle": ["", "", ""]}
	if is_instance_valid(weapon_slot):
		for weapon_node in weapon_slot.get_children():
			var w_id = weapon_node.get("WEAPON_ID")
			var ma_paths = weapon_node.get("equipped_martial_arts")
			if w_id and ma_paths is Array: current_config[w_id] = ma_paths.duplicate()
	return current_config

## 除了確認該槽位有裝備武藝，也一併檢查能量夠不夠——不夠的話直接在輸入層擋掉，
## 不要等到 WeaponAttack/Guard 已經取消目前招式才發現放不出來，會卡出一個很怪的空檔
func _has_martial_art(slot_index: int) -> bool:
	if not is_instance_valid(current_weapon): return false
	var m_slots = current_weapon.get("martial_slots")
	if not (m_slots is Array and m_slots.size() > slot_index): return false

	var art = m_slots[slot_index]
	if not is_instance_valid(art): return false

	var cost = art.get("energy_cost") if "energy_cost" in art else 0.0
	return martial_energy >= cost
	
func equip_loadout_with_arts(new_weapon_ids: Array[String], new_arts_config: Dictionary) -> void:
	equip_loadout(new_weapon_ids)
	if is_instance_valid(weapon_slot):
		for weapon_node in weapon_slot.get_children():
			var w_id = weapon_node.get("WEAPON_ID")
			if w_id and new_arts_config.has(w_id):
				var raw_paths = new_arts_config[w_id]
				var safe_paths: Array[String] = []
				for path in raw_paths: safe_paths.append(str(path))
				weapon_node.set("equipped_martial_arts", safe_paths)
				if weapon_node.has_method("load_martial_arts"): weapon_node.load_martial_arts(safe_paths)
	get_tree().call_group("HUD", "_refresh_weapon_icons", current_weapon)
	
func route_weapon_method(target_weapon_id: String, method_name: String, amount: int) -> void:
	for w in weapon_slot.get_children():
		if w.get("WEAPON_ID") == target_weapon_id and w.has_method(method_name): w.call(method_name, amount); return

## 觸發換把武器的切換邏輯
func _execute_weapon_switch() -> void:
	var total_weapons = weapon_slot.get_child_count()
	if total_weapons <= 1: return
	var current_idx = current_weapon.get_index() if is_instance_valid(current_weapon) else 0
	var next_idx = (current_idx + 1) % total_weapons
	_perform_swap(weapon_slot.get_child(next_idx))

## 實際執行武器交換
func _perform_swap(next_weapon: Node) -> void:
	is_input_locked = false
	var is_attacking = state_machine.current_state.name.to_lower() == "weaponattack"
	if self.velocity.y < -300: self.velocity.y = -300

	if is_attacking or not is_on_floor(): _flash_character()

	if is_instance_valid(current_weapon):
		if current_weapon.has_method("cancel_attack"): current_weapon.cancel_attack()
		current_weapon.hide()

	next_weapon.show(); current_weapon = next_weapon
	if current_weapon.get("scabbard_texture") and scabbard.has_method("set_scabbard_texture"):
		scabbard.set_scabbard_texture(current_weapon.scabbard_texture)
	
	weapon_switched.emit(current_weapon)
	
	if is_attacking: state_machine.transition_to("Idle" if is_on_floor() else "Fall")
	elif not is_on_floor():
		var current_state = state_machine.current_state.name.to_lower()
		if current_state not in ["jump", "fall", "wallslide"]: state_machine.transition_to("Fall") 
	else: state_machine.transition_to("SwapWeapon")
	
func _flash_character() -> void:
	if graphics:
		graphics.modulate = Color(2.5, 2.5, 2.5, 1.0)
		var tween = create_tween()
		tween.tween_property(graphics, "modulate", Color.WHITE, 0.2).set_trans(Tween.TRANS_SINE)

## 匯出玩家目前戰鬥狀態 (用於跨場景或存檔)
func export_combat_state() -> Dictionary:
	var state = {
		"equipped_weapon_ids": equipped_weapon_ids, "martial_energy": martial_energy,
		"weapon_switch_cooldown_timer": weapon_switch_cooldown_timer,
		"current_weapon_index": current_weapon.get_index() if is_instance_valid(current_weapon) else 0,
		"weapons_data": {}, "martial_arts_config": get_all_weapons_martial_arts() if has_method("get_all_weapons_martial_arts") else {}
	}
	for weapon in weapon_slot.get_children():
		if weapon.has_method("export_weapon_data"): state["weapons_data"][weapon.name] = weapon.export_weapon_data()
	return state

## 匯入玩家存檔的戰鬥狀態
func import_combat_state(state: Dictionary) -> void:
	if state.has("equipped_weapon_ids"):
		var raw_array = state["equipped_weapon_ids"]; var safe_array: Array[String] = []
		for item in raw_array: safe_array.append(str(item))
		if state.has("martial_arts_config") and not state["martial_arts_config"].is_empty(): equip_loadout_with_arts(safe_array, state["martial_arts_config"])
		else: equip_loadout(safe_array) 
		
	if state.has("martial_energy"): martial_energy = state["martial_energy"]
	if state.has("weapon_switch_cooldown_timer"): weapon_switch_cooldown_timer = state["weapon_switch_cooldown_timer"]
	
	if state.has("weapons_data"):
		for weapon in weapon_slot.get_children():
			if state["weapons_data"].has(weapon.name) and weapon.has_method("import_weapon_data"):
				weapon.import_weapon_data(state["weapons_data"][weapon.name])
				
	if state.has("current_weapon_index"):
		var target_idx = int(state["current_weapon_index"])
		if target_idx >= 0 and target_idx < weapon_slot.get_child_count():
			_force_equip_weapon(weapon_slot.get_child(target_idx))

func _force_equip_weapon(target_weapon: Node) -> void:
	if current_weapon == target_weapon: return
	if is_instance_valid(current_weapon): current_weapon.hide()
	target_weapon.show(); current_weapon = target_weapon
	if current_weapon.get("scabbard_texture") and scabbard.has_method("set_scabbard_texture"):
		scabbard.set_scabbard_texture(current_weapon.scabbard_texture)

func trigger_swing_sfx(sfx_type: String) -> void: AudioManager.play_action_sfx(sfx_type, -8.0)
func enable_weapon_hitbox(shape_name: String = "") -> void:
	if is_instance_valid(current_weapon) and current_weapon.has_method("enable_hitbox"): current_weapon.enable_hitbox(shape_name)
func disable_weapon_hitbox(shape_name: String = "") -> void:
	if is_instance_valid(current_weapon) and current_weapon.has_method("disable_hitbox"): current_weapon.disable_hitbox(shape_name)
