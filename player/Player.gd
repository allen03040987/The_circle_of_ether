class_name Player
extends CharacterBody2D
## 玩家總控制樞紐 (Player Controller Hub)
## 負責管理生命週期、統整玩家輸入、處理時間流逝與緩衝邏輯。
## 具體的移動與攻擊行為下放給 StateMachine 執行。

# ==========================================
# 📐 物理常數與列舉 
# ==========================================
enum Direction { LEFT = -1, RIGHT = 1 }

const WALK_SPEED := 150.0
const RUN_SPEED := 350.0
const JUMP_VELOCITY := -410.0
const FLOOR_ACCELERATION := RUN_SPEED / 0.04
const AIR_ACCELERATION := RUN_SPEED / 0.03
const TERMINAL_VELOCITY := 700.0 # 終端下落速度
const WALL_JUMP_VELOCITY := Vector2(300, -500) 

var default_gravity := ProjectSettings.get("physics/2d/default_gravity") as float
var external_force := Vector2.ZERO # 用來儲存風力或黑洞牽引力
# ==========================================
# 廣播信號 (Signals)
# ==========================================
signal weapon_switched(new_weapon: Weapon) # 當玩家成功切換武器時廣播

# ==========================================
# 🔗 節點參考 
# ==========================================
@onready var graphics: Node2D = $Graphics
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var state_machine: StateMachine = $StateMachine
@onready var stats: Node = Game.player_stats
@onready var weapon_slot: Node2D = $Graphics/WeaponSlot
@onready var scabbard: Node2D = $ScabbardContainer

# --- 計時器 ---
@onready var coyote_timer: Timer = $CoyoteTimer
@onready var jump_request_timer: Timer = $JumpRequestTimer
@onready var slide_request_timer: Timer = $SlideRequestTimer
@onready var slide_cooldown_timer: Timer = $SlideCooldownTimer
@onready var invincible_timer: Timer = $InvincibleTimer

# --- 射線檢測 ---
@onready var foot_checker: RayCast2D = $Graphics/FootChecker
@onready var hand_checker: RayCast2D = $Graphics/HandChecker
@onready var wall_slide_checker: RayCast2D = $WallSlideChecker

# --- UI 與互動 ---
@onready var interaction_icon: AnimatedSprite2D = $InteractionIcon

# ==========================================
# 🧠 核心變數 
# ==========================================
var direction := Direction.RIGHT :
	set(v):
		direction = v
		if not is_node_ready(): await ready
		graphics.scale.x = direction

var locked_facing_dir: int = 0
var invincible_time_left: float = 0.0 
var interacting_with: Array[Interactable] = []
var is_dead := false
var is_walking := false

# ==========================================
# ⚔️ 戰鬥輸入緩存 (Input Buffer)
# ==========================================
@export var can_combo := false
var is_combo_requested := false
var is_heavy_requested := false
var is_martial_requested := false # 🌟 武藝輸入緩衝
var requested_martial_slot := 0   # 🌟 記錄要求的是哪一槽 (1, 2, 3)

signal martial_mode_changed(is_active: bool) # 🌟 通知 UI 顯示發光的信號
var _last_martial_mode := false

var is_weapon_invincible := false
var is_ult_requested := false 
var is_input_locked := false  # 領域展開絕對鎖死標記

var combo_buffer_time: float = 0.0
var heavy_buffer_time: float = 0.0
var martial_buffer_time: float = 0.0 # 🌟 武藝倒數
const ATTACK_BUFFER_DURATION: float = 0.2

var is_counter_requested := false

var is_perfect_dodging := false
var pending_damage = null
var current_weapon: Weapon = null

# 武器切換冷卻系統
const WEAPON_SWITCH_COOLDOWN: float = 1.0 
var weapon_switch_cooldown_timer: float = 0.0     

# ==========================================
# 🧰 武器庫目錄 (Weapon Arsenal)
# ==========================================
# 將所有的武器場景預載入，方便隨時實例化
const WEAPON_BLUEPRINTS: Dictionary = {
	"katana": preload("res://player/Katana/katana.tscn"), # 請確保這些路徑與你的專案相符！
	"spear": preload("res://player/Spear/spear.tscn"),
	"talisman": preload("res://player/Talisman/talisman.tscn"),
	"sickle": preload("res://player/Sickle/Sickle.tscn"),
}

# 記錄玩家目前「裝備」在身上的武器 ID 清單
@export var equipped_weapon_ids: Array[String] = ["katana", "spear"]

# ==========================================
# ⚙️ 初始化與生命週期 
# ==========================================
func _ready() -> void:
	equip_loadout(equipped_weapon_ids)
	var is_base = false
	var current_world = get_tree().current_scene
	if current_world is World and "is_base" in current_world:
		is_base = current_world.is_base
		
	update_movement_by_scene(is_base)
	
	if not Game.settings_changed.is_connected(_on_global_settings_changed):
		Game.settings_changed.connect(_on_global_settings_changed)
		
# ==========================================
# 🎒 動態裝備系統 (Loadout System)
# ==========================================
func equip_loadout(weapon_ids: Array[String]) -> void:
	# 🌟 核心修復 1：在清空舊武器節點之前，先抓取「依然保留在新名單中」的武器內部數據（如居合/破陣值）
	var saved_weapons_data = {}
	for i in range(weapon_slot.get_child_count()):
		if i < equipped_weapon_ids.size():
			var old_w_id = equipped_weapon_ids[i]
			var old_weapon = weapon_slot.get_child(i)
			# 如果這把武器在新的 weapon_ids 裡面也有，就呼叫它的 export 函數備份
			if old_w_id in weapon_ids and old_weapon.has_method("export_weapon_data"):
				saved_weapons_data[old_w_id] = old_weapon.export_weapon_data()

	equipped_weapon_ids = weapon_ids
	
	# 1. 清空目前的 WeaponSlot
	for child in weapon_slot.get_children():
		child.queue_free()
		weapon_slot.remove_child(child) 
	
	current_weapon = null
	
	# 🌟 核心優化：銀行清算！註銷所有「未裝備武器」的資源帳戶
	var keys_to_remove = []
	for old_w_id in weapon_resources.keys():
		if old_w_id not in equipped_weapon_ids:
			keys_to_remove.append(old_w_id)
			
	for key in keys_to_remove:
		weapon_resources.erase(key)
		print("🗑️ [系統] 武器 [", key, "] 已卸下，其大招能量與合軸值已徹底歸零註銷！")
	
	# 2. 根據清單生成新武器
	for w_id in equipped_weapon_ids:
		if WEAPON_BLUEPRINTS.has(w_id):
			var new_weapon = WEAPON_BLUEPRINTS[w_id].instantiate()
			weapon_slot.add_child(new_weapon)
			new_weapon.hide() 
			new_weapon.player = self 
			
			# 🌟 核心修復 2：如果新生成的武器有剛才備份的數據，立刻將遺產還原給它！
			if saved_weapons_data.has(w_id) and new_weapon.has_method("import_weapon_data"):
				new_weapon.import_weapon_data(saved_weapons_data[w_id])
				print("♻️ [系統] 武器 [", w_id, "] 成功繼承內部資源狀態（居合/破陣值等）。")
			
			if not weapon_resources.has(w_id):
				weapon_resources[w_id] = {"energy": 0.0}
				print("🏦 [系統] 裝備新武器！已為 [", w_id, "] 建立資源帳戶。")
		else:
			printerr("❌ 找不到武器藍圖：", w_id)
			
	# 3. 強制裝備第一把武器
	if weapon_slot.get_child_count() > 0:
		_force_equip_weapon(weapon_slot.get_child(0))
		print("🎒 裝備更新完成！目前持有：", equipped_weapon_ids)
		
func _process(delta: float) -> void:
	
	# 🌟 武藝模式切換偵測與 UI 通知
	var current_martial_mode = Input.is_action_pressed("martial_modifier") and not is_input_locked
	if current_martial_mode != _last_martial_mode:
		_last_martial_mode = current_martial_mode
		martial_mode_changed.emit(current_martial_mode) # 讓你的 UI 接收信號發光！
	
	interaction_icon.visible = not interacting_with.is_empty()
	
	# ==========================================
	# ⏳ 真實時間引擎 (Unscaled Time)
	# ==========================================
	var unscaled_delta = delta / Engine.time_scale if Engine.time_scale > 0.0 else 0.0
	
	# 防喚醒衝擊
	if unscaled_delta > 0.1:
		unscaled_delta = 0.0166 
	
	# ==========================================
	# 🌟 核心修復：讓後台武器也能正常冷卻 (後台時間流動)
	# ==========================================
	# 巡視武器槽裡所有的武器 (包含前台與後台)
	for weapon in weapon_slot.get_children():
		# 防呆：確保武器是有效的，且有我們需要的函數
		if is_instance_valid(weapon) and weapon.has_method("update_timers_only"):
			# 把真實時間傳給每一把武器，讓它們各自倒數冷卻
			weapon.update_timers_only(unscaled_delta)

	# --- 計時器倒數 ---
	if invincible_time_left > 0:
		invincible_time_left -= unscaled_delta
		if not is_perfect_dodging:
			graphics.modulate.a = 0.8 
	else:
		graphics.modulate.a = 1.0
		is_perfect_dodging = false
	
	if time_stop_left > 0:
		time_stop_left -= unscaled_delta
		if time_stop_left <= 0:
			clear_time_stop()
	
		
	if weapon_switch_cooldown_timer > 0:
		weapon_switch_cooldown_timer -= unscaled_delta
		
	if combo_buffer_time > 0 and not is_input_locked:
		combo_buffer_time -= unscaled_delta
	else:
		is_combo_requested = false
		is_ult_requested = false

	if heavy_buffer_time > 0 and not is_input_locked:
		heavy_buffer_time -= unscaled_delta
	else:
		is_heavy_requested = false
		
	# 🌟 新增：武藝輸入的倒數與清理
	if martial_buffer_time > 0 and not is_input_locked:
		martial_buffer_time -= unscaled_delta
	else:
		is_martial_requested = false
	
	# 鎖死狀態下的強制清潔
	if is_input_locked:
		is_combo_requested = false; is_heavy_requested = false; is_ult_requested = false; is_martial_requested = false
		combo_buffer_time = 0.0; heavy_buffer_time = 0.0; martial_buffer_time = 0.0
		
	# 落地解鎖空戰限制
	if is_on_floor() and is_instance_valid(current_weapon):
		if "air_attack_locked" in current_weapon:
			current_weapon.air_attack_locked = false
	
	# ==========================================
	# 🔄 處理武器切換 (長短按識別)
	# ==========================================
	# 🌟 核心修復：向狀態機確認目前的物理狀態
	var current_state = state_machine.current_state.name.to_lower() if is_instance_valid(state_machine.current_state) else ""
	var is_in_hitstun = current_state in ["hurt", "launched", "dying"]
	
	# 🛡️ 絕對防護網：未鎖死、未死亡、不在受擊硬直中、且沒有正在排隊準備放的大招，才允許切換！
	if not is_input_locked and not is_dead and not is_in_hitstun and not is_ult_requested and weapon_slot.get_child_count() >= 2:
		if weapon_switch_cooldown_timer <= 0:
			if Input.is_action_just_pressed("switch_weapon"):
				_execute_weapon_switch()
				weapon_switch_cooldown_timer = WEAPON_SWITCH_COOLDOWN # 🌟 觸發冷卻
			
# ==========================================
# 🎮 玩家輸入控制 
# ==========================================
func _input(event: InputEvent) -> void:
	# 第一道防線：鎖定時攔截實體按鍵
	if is_input_locked:
		if event.is_action("ui_cancel") or event.is_action("ui_accept"):
			return 
		if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
			get_viewport().set_input_as_handled() 
		return

func _unhandled_input(event: InputEvent) -> void:
		
	if is_input_locked: return 
		
	if event.is_action_pressed("toggle_walk"):
		toggle_walk_mode()
		
	# --- 攻擊輸入緩衝 ---
	var is_mod_held = Input.is_action_pressed("martial_modifier")
	
	# 🌟 左鍵：普攻 或 武藝1
	if event.is_action_pressed("attack"):
		if is_mod_held:
			if _has_martial_art(0): # 🛡️ 防呆：確認 1 號槽有裝備卡帶才允許發動！
				is_martial_requested = true
				is_combo_requested = true 
				requested_martial_slot = 1
				martial_buffer_time = ATTACK_BUFFER_DURATION
				combo_buffer_time = ATTACK_BUFFER_DURATION
		else:
			var can_buffer = true
			if not is_on_floor() and is_instance_valid(current_weapon) and current_weapon.has_method("can_air_light"):
				can_buffer = current_weapon.can_air_light()
			if can_buffer:
				is_combo_requested = true
				combo_buffer_time = ATTACK_BUFFER_DURATION
	
	# 🌟 中鍵：專屬武藝2
	if event.is_action_pressed("middle_click"):
		if is_mod_held:
			if _has_martial_art(1): # 🛡️ 防呆：確認 2 號槽有裝備卡帶
				is_martial_requested = true
				is_combo_requested = true 
				requested_martial_slot = 2
				martial_buffer_time = ATTACK_BUFFER_DURATION
				combo_buffer_time = ATTACK_BUFFER_DURATION
			
	# 🌟 右鍵：戰技中立 或 武藝3
	if event.is_action_pressed("heavy_attack"):
		if is_mod_held:
			if _has_martial_art(2): # 🛡️ 防呆：確認 3 號槽有裝備卡帶
				is_martial_requested = true
				is_combo_requested = true 
				requested_martial_slot = 3
				martial_buffer_time = ATTACK_BUFFER_DURATION
				combo_buffer_time = ATTACK_BUFFER_DURATION
		else:
			var can_buffer = true
			if is_instance_valid(current_weapon) and current_weapon.has_method("can_use_heavy"):
				can_buffer = current_weapon.can_use_heavy()
			if can_buffer:
				is_heavy_requested = true
				heavy_buffer_time = ATTACK_BUFFER_DURATION
		
	if event.is_action_pressed("ultimate"):
		var can_buffer = true
		if is_instance_valid(current_weapon) and current_weapon.has_method("can_use_ultimate"):
			can_buffer = current_weapon.can_use_ultimate()
			
		if can_buffer:
			is_ult_requested = true
			combo_buffer_time = ATTACK_BUFFER_DURATION
		
	# --- 移動與互動 ---
	if event.is_action_pressed("jump"):
		jump_request_timer.start()
		
	# 變動跳躍高度
	if event.is_action_released("jump"):
		jump_request_timer.stop()
		if velocity.y < JUMP_VELOCITY / 2:
			velocity.y = JUMP_VELOCITY / 2

	if event.is_action_pressed("silde"): 
		slide_request_timer.start()
	
	if event.is_action_pressed("interact") and not interacting_with.is_empty():
		interacting_with.back().interact()

# ==========================================
# 🛡️ 狀態機專用介面 
# ==========================================
func play_safe_anim(anim_name: String) -> void:
	if animation_player.has_animation(anim_name):
		if animation_player.current_animation != anim_name:
			animation_player.play(anim_name)
	else:
		printerr("❌ 找不到動畫: ", anim_name)

func custom_move_and_slide() -> void:
	if pending_damage != null:
		return
		
	# 🌟 神級物理：把外部牽引力疊加進去，算完立刻還原！
	# 這樣就算玩家正在普攻(速度被武器鎖死)，也依然會被吸走！
	var original_x = velocity.x
	velocity.x += external_force.x
	move_and_slide()
	velocity.x = original_x 
	
	# 牽引力每幀快速衰減，確保吸力一停，玩家就恢復正常
	external_force.x = move_toward(external_force.x, 0.0, 1500.0 * get_physics_process_delta_time())

# ==========================================
# ⚔️ 受擊系統與運算
# ==========================================
func take_damage(temp_damage: Damage) -> void:
	if is_dead or state_machine.current_state.name.to_lower() == "dying": return
	if invincible_time_left > 0 or invincible_timer.time_left > 0: return
	
	is_combo_requested = false
	is_heavy_requested = false
	is_ult_requested = false
	combo_buffer_time = 0.0
	heavy_buffer_time = 0.0
	
	# 🌟 1. 這裡只負責扣血
	stats.health -= temp_damage.amount
	velocity = Vector2.ZERO 
	
	# 🌟 2. 根據你要的設計，精準發放無敵時間！
	match temp_damage.type:
		Damage.Type.NO_STUN:
			pending_damage = null
		Damage.Type.HEAVY:
			grant_invincibility(0.6) # 挑飛給 0.6 秒無敵！
			state_machine.call_deferred("transition_to", "Launched") 
		Damage.Type.THROW:
			pending_damage = null
		_: # 預設與 LIGHT
			grant_invincibility(0.35) # 輕受擊給 0.35 秒無敵！
			state_machine.call_deferred("transition_to", "Hurt")
			
	if stats.health <= 0:
		state_machine.call_deferred("transition_to", "Dying")

# 🌟 統一下發無敵時間，確保 Hitbox 跟 Player 不會精神分裂
func grant_invincibility(duration: float) -> void:
	invincible_time_left = duration
	invincible_timer.start(duration)
	
# ==========================================
# ⚔️ 受擊系統與運算
# ==========================================
func _on_hurtbox_hurt(hitbox: Hitbox) -> void:
	if is_dead or state_machine.current_state.name.to_lower() == "dying":
		return

	# 🚨 抓鬼專用監視器：印出到底是哪個 Hitbox 打到了玩家！
	var final_amount: int = hitbox.get("damage_amount") if "damage_amount" in hitbox else 1
	var final_type: int = hitbox.get("attack_type") if "attack_type" in hitbox else Damage.Type.LIGHT
	# 讀取來源標籤
	var final_source_type: int = hitbox.get("source_type") if "source_type" in hitbox else Damage.SourceType.MELEE
	
	print("🔍 [受擊偵測] 來源 Hitbox: ", hitbox.name, " | 傷害: ", final_amount)

	# 算出擊退力道
	var final_knockback := Vector2.ZERO
	if "absolute_knockback" in hitbox and hitbox.absolute_knockback != Vector2.ZERO:
		final_knockback = hitbox.absolute_knockback
	else:
		var raw_force := Vector2(150.0, 0.0)
		if "knockback_force" in hitbox: raw_force = hitbox.knockback_force
		var dir_x : float = sign(global_position.x - hitbox.owner.global_position.x)
		if dir_x == 0: dir_x = -direction 
		final_knockback = Vector2(raw_force.x * dir_x, raw_force.y)

	# ==========================================
	# 📍 絕對特權防線：只要傷害是 0，一律視為環境風力！絕對不准往下走！
	# ==========================================
	if final_amount <= 0:
		external_force = final_knockback
		return # 🚨 程式在這裡強制結束，底下的無敵跟閃避連看都看不到！

	# ==========================================
	# 📍 戰鬥防禦防線 (被大於 0 傷害打到才會執行)
	# ==========================================
	# 1. 無敵判定
	if invincible_time_left > 0 or invincible_timer.time_left > 0:
		return

	# 2. 極限閃避攔截
	if state_machine.current_state.name.to_lower() == "slide":
		if state_machine.current_state.has_method("trigger_perfect_dodge"):
			state_machine.current_state.trigger_perfect_dodge()
		return

	# ==========================================
	# 📍 正常受擊與扣血
	# ==========================================
	pending_damage = {
		"source": hitbox,
		"amount": final_amount,
		"type": final_type,
		"source_type": final_source_type, # 🌟 裝進字典
		"knockback_force": final_knockback
	}
	
	var temp_damage = Damage.new()
	temp_damage.amount = final_amount
	temp_damage.type = final_type
	temp_damage.source_type = final_source_type # 🌟 裝進物件
	temp_damage.knockback_force = final_knockback
	
	take_damage(temp_damage)

func die() -> void:
	if is_dead: return
	is_dead = true
	
	invincible_timer.stop()
	graphics.modulate.a = 1.0
	is_perfect_dodging = false
	
	# 🌟 透過正規管道解除時停，不要自己硬改 Engine
	clear_time_stop()
	
	if has_node("CanvasLayer/GameOverScreen"):
		$CanvasLayer/GameOverScreen.show_game_over()

func strike_impulse(strength: float) -> void:
	var current_state = state_machine.current_state.name.to_lower()
	if current_state in ["hurt", "launched", "dying"]:
		print("🛡️ [防護網觸發] 受傷中，成功攔截動畫偷渡！")
		return
		
		
	var speed_mult = 1.0 / Engine.time_scale if Engine.time_scale > 0 else 1.0
	velocity.x = direction * (strength * speed_mult)
	
	# 🚨 監視器 A：印出衝刺瞬間的引擎時間與最終速度
	if speed_mult > 2.0:
		print("⚠️ [警告] 異常 TimeScale: ", Engine.time_scale, " | 動畫賦予的極端速度: ", velocity.x)

# ==========================================
# 🎨 視覺特效與環境互動 
# ==========================================
func add_ghost() -> void:
	var ghost := Sprite2D.new()
	var original_sprite := $Graphics/Sprite2D
	
	ghost.texture = original_sprite.texture
	ghost.hframes = original_sprite.hframes
	ghost.vframes = original_sprite.vframes
	ghost.frame = original_sprite.frame
	ghost.region_enabled = original_sprite.region_enabled
	ghost.region_rect = original_sprite.region_rect
	ghost.offset = original_sprite.offset
	ghost.flip_h = original_sprite.flip_h
	ghost.flip_v = original_sprite.flip_v
	
	var manual_offset := Vector2(0, -29) 
	ghost.global_position = global_position + manual_offset
	ghost.scale = graphics.scale 
	
	if is_perfect_dodging:
		ghost.modulate = Color(1.8, 0.4, 2.5, 0.15) 
	else:
		ghost.modulate = Color(0.5, 1.8, 1.0, 0.4) 
	
	get_parent().add_child(ghost)
	
	var tween := create_tween()
	tween.tween_property(ghost, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(ghost.queue_free)

func can_wall_slide() -> bool:
	return is_on_wall() and hand_checker.is_colliding() and foot_checker.is_colliding()
	
func register_interactable(v: Interactable) -> void:
	if state_machine.current_state.name.to_lower() == "dying": 
		return
	if v not in interacting_with:
		interacting_with.append(v)

func unregister_interactable(v: Interactable) -> void:
	interacting_with.erase(v)

# ==========================================
# 🚶 模式切換邏輯
# ==========================================
func update_movement_by_scene(force_walk: bool) -> void:
	if force_walk:
		is_walking = true 
	else:
		is_walking = Game.config_default_walking 
	
	if state_machine.current_state != null:
		if state_machine.current_state.name.to_lower() == "run":
			play_safe_anim("walking" if is_walking else "running")

func toggle_walk_mode() -> void:
	# 1. 基地防護：如果在基地內強制走路，就不允許玩家用快捷鍵切換
	var current_world = get_tree().current_scene
	if current_world is World and "is_base" in current_world and current_world.is_base:
		print("🛑 基地內強制步行，無法切換奔跑！")
		return 

	# 2. 核心狀態切換
	is_walking = !is_walking
	
	# 3. 只有當狀態真的改變時，才同步全域設定與存檔
	if Game.config_default_walking != is_walking:
		Game.config_default_walking = is_walking
		Game.save_settings()
		print("🏃 快捷鍵切換成功！目前行走模式：", is_walking)
	
	# 4. 視覺即時回饋：如果玩家現在正在移動，立刻無縫切換動畫！
	if state_machine.current_state.name.to_lower() == "run":
		play_safe_anim("walking" if is_walking else "running")

func _on_global_settings_changed() -> void:
	var is_base = false
	var current_world = get_tree().current_scene
	if current_world is World and "is_base" in current_world:
		is_base = current_world.is_base
	update_movement_by_scene(is_base)

# ==========================================
# 🎨 動畫特效分組 (VFX Categories)
# ==========================================

@export_group("VFX: 基礎通用 (環境/煙塵)")
@export var vfx_common: Dictionary = {}

@export_group("VFX: 武器特效與火花")
@export var vfx_weapon: Dictionary = {}

@export_group("VFX: 系統反饋 (蓄力/受擊)")
@export var vfx_system: Dictionary = {}

## 呼叫並生成特效 (已擴充：支援獨立 XY 縮放與動態旋轉)
## 
## [參數說明]
## @param vfx_name     : 特效在字典中的名稱 (字串，必填)
## @param offset_x     : 橫向位置偏移量 (數值，會根據玩家面向自動左右翻轉，預設 0.0)
## @param offset_y     : 縱向位置偏移量 (數值，負數為往上，預設 0.0)
## @param custom_scale : 自定義縮放比例 (Vector2，可獨立控制寬高，預設 Vector2(1.0, 1.0) 不縮放)
## @param rotation_deg : 動態旋轉角度 (數值，單位為度，例如 45.0 為順時針轉 45 度，預設 0.0)
## @param custom_color : 特效的主要渲染顏色 (Color，預設白色)
## @param aura_color   : 特效專屬光暈(Aura)的顏色 (Color，預設白色)
## @param detach       : 是否脫離玩家獨立存在 (布林值，true=留在原地，false=黏在玩家身上，預設 true)
## @param custom_z_index: 圖層偏移，預設 1 (蓋在玩家前面)
## @param raw_intensity: HDR 發光強度 (數值，數值越大特效越刺眼，必須放在最後面！預設 1.0)
func spawn_anim_vfx(
	vfx_name: String, 
	offset_x: float = 0.0, 
	offset_y: float = 0.0, 
	custom_scale: Vector2 = Vector2(1.0, 1.0), 
	rotation_deg: float = 0.0, 
	custom_color: Color = Color.WHITE, 
	aura_color: Color = Color.WHITE, 
	detach: bool = true, 
	custom_z_index: int = 1,
	raw_intensity: float = 1.0
) -> void:
	
	# 遍歷所有字典找特效
	var vfx_scene = null
	if vfx_common.has(vfx_name): vfx_scene = vfx_common[vfx_name]
	elif vfx_weapon.has(vfx_name): vfx_scene = vfx_weapon[vfx_name]
	elif vfx_system.has(vfx_name): vfx_scene = vfx_system[vfx_name]
	
	if vfx_scene == null: return # 找不到就安靜退出
	
	var vfx = vfx_scene.instantiate()
	
	if CombatManager.has_method("_apply_anti_timestop"):
		CombatManager._apply_anti_timestop(vfx)
		
	# 4.處理空間解綁與 Z-Index
	if detach:
		get_parent().add_child(vfx)
		var spawn_pos = global_position
		spawn_pos.x += offset_x * direction
		spawn_pos.y += offset_y
		vfx.global_position = spawn_pos
		
		# 脫離玩家時：必須加上玩家本身的 Z-Index，確保特效不會掉到背景後面
		vfx.z_index = self.z_index + custom_z_index 
	else:
		self.add_child(vfx)
		vfx.position = Vector2(offset_x * direction, offset_y)
		
		# 掛在玩家身上時：Godot 預設 z_as_relative = true，所以直接給相對值即可
		vfx.z_index = custom_z_index

	# 5. 處理動態變換 (獨立 XY 縮放與旋轉)
	# 把 Vector2(x, y) 拆開：X 軸乘上 direction 控制左右翻轉，Y 軸保持原樣
	vfx.scale = Vector2(direction * custom_scale.x, custom_scale.y)
	
	# 神級細節：旋轉角度必須乘上 direction！
	# 這樣設定 45 度時，面向右邊是右上，面向左邊會自動鏡像成左上，動畫師不用做兩套！
	vfx.rotation_degrees = rotation_deg * direction
	
	# 6. 處理 HDR 發光渲染與顏色疊加
	var hdr_color = Color(
		custom_color.r * raw_intensity, 
		custom_color.g * raw_intensity, 
		custom_color.b * raw_intensity, 
		custom_color.a
	)
	
	# 遞迴染色
	_apply_vfx_colors(vfx, hdr_color, aura_color)

func _apply_vfx_colors(node: Node, main_color: Color, aura_color: Color) -> void:
	if node is CanvasItem and node.name != "AnimationPlayer":
		if node.name == "Aura":
			node.self_modulate = aura_color
		else:
			node.self_modulate = main_color
			
	for child in node.get_children():
		_apply_vfx_colors(child, main_color, aura_color)

# ==========================================
# ⏳ 泛用時停系統 (Time Stop / Domain Expansion)
# ==========================================
var time_stop_left: float = 0.0
var current_time_scale: float = 1.0

func trigger_time_stop(real_duration: float, target_time_scale: float) -> void:
	# Player 這裡只負責倒數計時，修改 Engine 的工作交給仲裁者！
	if target_time_scale < current_time_scale or real_duration > time_stop_left:
		current_time_scale = target_time_scale
		time_stop_left = real_duration 
		
		if CombatManager.has_method("set_domain_time"):
			CombatManager.set_domain_time(target_time_scale)

func clear_time_stop() -> void:
	if current_time_scale != 1.0 or time_stop_left > 0:
		current_time_scale = 1.0
		time_stop_left = 0.0
		animation_player.speed_scale = 1.0
		
		if CombatManager.has_method("clear_domain_time"):
			CombatManager.clear_domain_time()

# ==========================================
# 📊 合軸戰鬥資源中樞 
# ==========================================
@export_group("合軸戰鬥倍率")
var energy_regen_mult: float = 1.0   
var switch_regen_mult: float = 1.0   

var weapon_resources: Dictionary = {}
var current_outro_buff: String = "" 

func add_weapon_resource(weapon_id: String, base_energy: float, _base_switch: float = 0.0) -> void:
	if not weapon_resources.has(weapon_id): 
		weapon_resources[weapon_id] = {"energy": 0.0}
		print("🏦 [系統] 大腦偵測到新武器，已自動為 [", weapon_id, "] 建立專屬資源帳戶！")
	
	var data = weapon_resources[weapon_id]
	data["energy"] = clamp(data["energy"] + (base_energy * energy_regen_mult), 0.0, 100.0)

func get_weapon_energy(weapon_id: String) -> float:
	if weapon_resources.has(weapon_id):
		return weapon_resources[weapon_id]["energy"]
	return 0.0

func consume_weapon_energy(weapon_id: String, amount: float) -> bool:
	if weapon_resources.has(weapon_id) and weapon_resources[weapon_id]["energy"] >= amount:
		weapon_resources[weapon_id]["energy"] -= amount
		print("💥 [", weapon_id, "] 消耗能量: ", amount, " | 剩餘能量: ", weapon_resources[weapon_id]["energy"])
		return true
	return false

func consume_switch_value(weapon_id: String) -> bool:
	if weapon_resources.has(weapon_id) and weapon_resources[weapon_id]["switch"] >= 100.0:
		weapon_resources[weapon_id]["switch"] = 0.0
		return true
	return false

# ==========================================
# 🥋 高自由度武藝配置路由器 (UI 選單對接端)
# ==========================================

## 供 UI 選單開啟時，初始化讀取本尊目前的配置狀態
func get_all_weapons_martial_arts() -> Dictionary:
	var current_config = {
		"katana": ["", "", ""],
		"spear": ["", "", ""],
		"talisman": ["", "", ""],
		"sickle": ["", "", ""]
	}
	
	# 遍歷裝備槽，將各武器的實際配置路徑拉出來給 UI
	if is_instance_valid(weapon_slot):
		for weapon_node in weapon_slot.get_children():
			var w_id = weapon_node.get("WEAPON_ID")
			var ma_paths = weapon_node.get("equipped_martial_arts")
			if w_id and ma_paths is Array:
				current_config[w_id] = ma_paths.duplicate()
	return current_config

# 🛡️ 檢查當前武器的指定槽位是否有裝備武藝
func _has_martial_art(slot_index: int) -> bool:
	if not is_instance_valid(current_weapon): return false
	var m_slots = current_weapon.get("martial_slots")
	if m_slots is Array and m_slots.size() > slot_index:
		return is_instance_valid(m_slots[slot_index])
	return false
	
## 終極接口：接收選單確認後的武器名單與武藝字典，進行神經重組
func equip_loadout_with_arts(new_weapon_ids: Array[String], new_arts_config: Dictionary) -> void:
	# 1. 呼叫原本的換裝備邏輯 (這樣能順便結算資源帳戶與生成新武器)
	equip_loadout(new_weapon_ids)
	
	# 2. 新武器生成完畢後，強行將選單中配置好的「3張卡帶路徑」塞進去並立刻載入
	if is_instance_valid(weapon_slot):
		for weapon_node in weapon_slot.get_children():
			var w_id = weapon_node.get("WEAPON_ID")
			if w_id and new_arts_config.has(w_id):
				
				# ==========================================
				# 🌟 核心修復：強制將泛用 Array 轉換為嚴格的 Array[String]！
				# ==========================================
				var raw_paths = new_arts_config[w_id]
				var safe_paths: Array[String] = []
				for path in raw_paths:
					safe_paths.append(str(path))
				
				# 修改武器內部的導航字串陣列
				weapon_node.set("equipped_martial_arts", safe_paths)
				
				# 呼叫武器的卡帶讀取槽，動態實例化子節點！
				if weapon_node.has_method("load_martial_arts"):
					weapon_node.load_martial_arts(safe_paths)
					
	# 3. 強制刷新一次 UI 圖標，確保切換後的技能圖示正確
	get_tree().call_group("HUD", "_refresh_weapon_icons", current_weapon)
	
# ==========================================
# 📡 跨實例武器專線路由器 (Weapon Router) 
# ==========================================
## 允許殘影或外部特效，直接呼叫背包裡對應武器的方法 (如 gain_pozhen, gain_iai)
func route_weapon_method(target_weapon_id: String, method_name: String, amount: int) -> void:
	for w in weapon_slot.get_children():
		# 核對身分證 (WEAPON_ID) 並且確認它真的有這個功能
		if w.get("WEAPON_ID") == target_weapon_id and w.has_method(method_name):
			w.call(method_name, amount)
			return

func _execute_weapon_switch() -> void:
	var total_weapons = weapon_slot.get_child_count()
	if total_weapons <= 1:
		print("⚠️ 只有一把武器，無法切換！")
		return
		
	var current_idx = current_weapon.get_index() if is_instance_valid(current_weapon) else 0
	var next_idx = (current_idx + 1) % total_weapons
	var next_weapon = weapon_slot.get_child(next_idx)

	_perform_swap(next_weapon)

func _perform_swap(next_weapon: Node) -> void:
	is_input_locked = false
	var is_attacking = state_machine.current_state.name.to_lower() == "weaponattack"
	
	# 切換動能抑制
	if self.velocity.y < -300:
		self.velocity.y = -300
		
	# --- 視覺演出與殘影 ---
	if is_attacking:
		spawn_phantom_striker(current_weapon)
		_flash_character() 
	elif not is_on_floor():
		_flash_character() # 空中非攻擊切換：只閃白，不留殘影

	# --- 武器替換 ---
	if is_instance_valid(current_weapon):
		if current_weapon.has_method("cancel_attack"):
			current_weapon.cancel_attack()
		current_weapon.hide()

	next_weapon.show()
	current_weapon = next_weapon
	
	if current_weapon.get("scabbard_texture") and scabbard.has_method("set_scabbard_texture"):
		scabbard.set_scabbard_texture(current_weapon.scabbard_texture)
	
	weapon_switched.emit(current_weapon)
	
	# --- 狀態機分流 (直接走一般切換與常規收招) ---
	if is_attacking:
		state_machine.transition_to("Idle" if is_on_floor() else "Fall")
	elif not is_on_floor():
		var current_state = state_machine.current_state.name.to_lower()
		if current_state not in ["jump", "fall", "wallslide"]:
			state_machine.transition_to("Fall") 
	else:
		state_machine.transition_to("SwapWeapon")
	
# ==========================================
# 👻 殘影代打系統核心 (Phantom Striker)
# ==========================================
const PHANTOM_SCENE = preload("res://player/PhantomStriker.tscn") 

func spawn_phantom_striker(outgoing_weapon: Weapon) -> void:
	if not PHANTOM_SCENE: return
	
	var phantom = PHANTOM_SCENE.instantiate()
	
	# 🌟 核心修復：先在「離線狀態」下完成所有設定！(致敬原版邏輯)
	phantom.setup(self, outgoing_weapon)
	
	# 🌟 設定完畢後，最後一步才把它加進遊戲世界！
	get_tree().current_scene.add_child(phantom)

# ==========================================
# ✨ 視覺與 Hitbox 接口 (Proxy Methods)
# ==========================================
func _flash_character() -> void:
	if graphics:
		graphics.modulate = Color(2.5, 2.5, 2.5, 1.0)
		var tween = create_tween()
		tween.tween_property(graphics, "modulate", Color.WHITE, 0.2).set_trans(Tween.TRANS_SINE)

# ==========================================
# 💾 跨場景戰鬥狀態繼承 (Combat State Persistence)
# ==========================================
func export_combat_state() -> Dictionary:
	var state = {
		"equipped_weapon_ids": equipped_weapon_ids, 
		"weapon_resources": weapon_resources,
		"weapon_switch_cooldown_timer": weapon_switch_cooldown_timer,
		"current_weapon_index": current_weapon.get_index() if is_instance_valid(current_weapon) else 0,
		"weapons_data": {},
		
		# 🌟 核心修復：把現在所有武器上的武藝卡帶清單，呼叫接口打包成字典帶走！
		"martial_arts_config": get_all_weapons_martial_arts() if has_method("get_all_weapons_martial_arts") else {}
	}
	
	for weapon in weapon_slot.get_children():
		if weapon.has_method("export_weapon_data"):
			state["weapons_data"][weapon.name] = weapon.export_weapon_data()
			
	return state

func import_combat_state(state: Dictionary) -> void:
	print("📥 [時空法術] 偵測到跨場景背包，正在強制覆蓋預設武器與武藝！")
	
	if state.has("equipped_weapon_ids"):
		var raw_array = state["equipped_weapon_ids"]
		var safe_array: Array[String] = []
		
		for item in raw_array:
			safe_array.append(str(item))
			
		# 🌟 核心修復：如果背包裡有「武藝配置」，就改用新的高自由度接口來裝備武器與武藝！
		if state.has("martial_arts_config") and not state["martial_arts_config"].is_empty():
			equip_loadout_with_arts(safe_array, state["martial_arts_config"])
		else:
			equip_loadout(safe_array) # 舊存檔相容保險
		
	if state.has("weapon_resources"): weapon_resources = state["weapon_resources"]
	if state.has("weapon_switch_cooldown_timer"): weapon_switch_cooldown_timer = state["weapon_switch_cooldown_timer"]
	
	# 恢復各武器內部數據
	if state.has("weapons_data"):
		for weapon in weapon_slot.get_children():
			if state["weapons_data"].has(weapon.name) and weapon.has_method("import_weapon_data"):
				weapon.import_weapon_data(state["weapons_data"][weapon.name])
				
	# 恢復原本拿在手上的武器 (無聲強制切換)
	if state.has("current_weapon_index"):
		var target_idx = int(state["current_weapon_index"])
		if target_idx >= 0 and target_idx < weapon_slot.get_child_count():
			_force_equip_weapon(weapon_slot.get_child(target_idx))

func _force_equip_weapon(target_weapon: Node) -> void:
	if current_weapon == target_weapon: return
	if is_instance_valid(current_weapon): current_weapon.hide()
	
	target_weapon.show()
	current_weapon = target_weapon
	if current_weapon.get("scabbard_texture") and scabbard.has_method("set_scabbard_texture"):
		scabbard.set_scabbard_texture(current_weapon.scabbard_texture)
	
	
	
# ==========================================
# 🎬 動畫事件轉接器 (Animation Events)
# ==========================================
# 讓 AnimationPlayer 呼叫這個函數，再由它轉交給總機 AudioManager 播放
func trigger_swing_sfx(sfx_type: String) -> void:
	AudioManager.play_action_sfx(sfx_type, -8.0)
		
func enable_weapon_hitbox(shape_name: String = "") -> void:
	if is_instance_valid(current_weapon) and current_weapon.has_method("enable_hitbox"):
		current_weapon.enable_hitbox(shape_name)

func disable_weapon_hitbox(shape_name: String = "") -> void:
	if is_instance_valid(current_weapon) and current_weapon.has_method("disable_hitbox"):
		current_weapon.disable_hitbox(shape_name)
