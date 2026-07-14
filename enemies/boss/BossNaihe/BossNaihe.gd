class_name BossNaihe
extends Enemy
## 奈何橋 (Naihe Bridge) - 關底 BOSS
## 負責管理 BOSS 專屬技能、階段轉換與 Hitbox 動態方向賦予。

signal died ## 死亡動畫播完、屍體真正消失前廣播——Worlds/BossArenaTrigger.gd 靠這個訊號開門

@onready var state_machine: StateMachine = $StateMachine
@onready var player_target: Player = get_tree().get_first_node_in_group("Player")
@onready var hurtbox: Hurtbox = $Graphics/Hurtbox
@onready var warning_icon: Sprite2D = $Graphics/WarningIcon

const CANNON_SCENE = preload("res://player/Katana/c_3_wave.tscn")
# 在最上面的 const 區塊加入這行：
const SPIKE_SPAWNER_SCENE = preload("res://enemies/boss/BossNaihe/NaiheSpikeSpawner.tscn")
# --- 戰鬥階段與招式 ---
var current_phase: int = 1

var _hb_defaults := {} # 🌟 用來備份 Hitbox 的初始面板設定

# --- 招式空窗期受擊硬直閘門 ---
@export_group("受擊硬直閘門設定")
@export var hurt_gate_range: Vector2 = Vector2(0.5, 2.0) # 一般被打斷（空窗期挨打）的硬直閘門隨機範圍
@export var guard_break_hurt_gate_range: Vector2 = Vector2(2.0, 4.0) # 黃圈技被彈開時的硬直閘門隨機範圍，每隻 BOSS 可各自調整

var _hurt_gate_active: bool = false
var _hurt_gate_end_time: float = 0.0
var _next_hurt_uses_guard_break_range: bool = false

const ATTACKS = {
	"combo_1": {"anim": "naihe/attack_1", "dist": 150}, 
	"combo_2": {"anim": "naihe/attack_2", "dist": 150}, 
}
var current_attack_anim: String = ""

# ==========================================
# ⚙️ 初始化與生命週期
# ==========================================
func _ready() -> void:
	super._ready() # 🔧 補上：之前漏了呼叫，導致 Enemy 基底的破防紅閃沒接上（Slime/TrainingDummy 都有呼叫這行）
	can_be_launched = true

	# 🌟 記下面板設定
	var hb = get_node_or_null("Graphics/WeaponHitbox")
	if hb:
		_hb_defaults = {
			"sticky_multi_hit": hb.get("sticky_multi_hit"),
			"max_hits": hb.get("max_hits"),
			"hit_interval": hb.get("hit_interval"),
			"damage_amount": hb.get("damage_amount"),
			"attack_type": hb.get("attack_type"),
			"knockback_force": hb.get("knockback_force"), # 🌟 多備份這行擊退力！
			"spark_type": hb.get("spark_type"), # 🔧 補上：A8 吸引攻擊會覆寫這個，普通招式要能還原
			"custom_spark_scene": hb.get("custom_spark_scene")
		}
	
	if hurtbox and not hurtbox.hurt.is_connected(_on_hurtbox_hurt):
		hurtbox.hurt.connect(_on_hurtbox_hurt)
		
	if stats and not stats.health_changed.is_connected(_on_health_changed):
		stats.health_changed.connect(_on_health_changed)
		
func _physics_process(delta: float) -> void:
	pass # 面向控制交由 StateMachine 處理

# ==========================================
# ⚔️ 戰鬥邏輯與狀態
# ==========================================
func _on_hurtbox_hurt(hitbox: Hitbox) -> void:
	var current_state = state_machine.current_state.name.to_lower()

	# 🌟 0. 黃圈彈刀：先檢查這一下有沒有破解目前開啟的判定窗
	if try_guard_break(hitbox):
		# 🔧 這一下如果打死了 BOSS，try_guard_break() 內的 stats.health -= dmg 已經同步觸發
		# health_changed -> _on_health_changed() -> transition_to("Death")，不能再用扣血前的舊 current_state
		# 硬蓋成 Hurt，不然 BOSS 會卡在 Hurt 狀態不會真的死掉
		if stats == null or stats.health <= 0: return

		# BOSS 專屬額外反應：大量削韌 + 強制立刻進入 Hurt（不受空窗期限制）
		if "poise" in stats and not stats.is_broken:
			stats.poise -= 50.0
		if current_state != "paralyzed" and current_state != "death":
			_next_hurt_uses_guard_break_range = true
			state_machine.transition_to("Hurt")
		return

	# 1. 呼叫基底計算傷害與削韌
	take_damage(hitbox)

	# 🔧 同上：這下打死了就不要再處理癱瘓/硬直轉換，避免蓋掉已經同步發生的 Death 轉換
	if stats == null or stats.health <= 0: return

	# 🌟 2. 唯一攔截：只看有沒有被打出癱瘓！
	if stats.is_broken:
		# 確保不會在已經癱瘓或死亡時重複觸發
		if current_state != "paralyzed" and current_state != "death":
			state_machine.transition_to("Paralyzed")
		elif current_state == "paralyzed":
			# 🌟 統一規則：沒有霸體就該正常吃擊退——癱瘓中沒開霸體，一樣要被打到位移，
			# 只是不轉場出 Paralyzed（讓 Paralyzed.gd 自己播完跪下/喘息/起身的既定流程，不被硬凹去 Hurt）
			if pending_damage != null:
				var kb: Vector2 = pending_damage["knockback_force"]
				velocity = kb
				pending_damage = null

	# 🌟 3. 已經在 Hurt 時被打到：重新套用擊退力 + 重播動畫
	elif current_state == "hurt":
		# 🌟 不論是不是第一下，都要重新套用這次的擊退力（含垂直）
		# 這樣連續打的空中連段每一下都會重新墊高，不會只吃第一下初速就被重力拉回地面
		if pending_damage != null:
			var kb: Vector2 = pending_damage["knockback_force"]
			velocity = kb
			pending_damage = null

		# transition_to 會被「同狀態不重入」防呆擋掉，直接強制重播動畫，
		# 確保空中被連續打時每一下都有視覺回饋（閘門到期判定完全交給 Hurt.gd 每幀自己檢查）
		var anim_name = "hurt_1" if randf() < 0.5 else "hurt_2"
		if animation_player.has_animation(anim_name):
			animation_player.play(anim_name, -1, action_speed_mult)

	# 🌟 4. 統一判準：只要現在沒有霸體，不管在哪個狀態都真的能被打斷進 Hurt
	# （Paralyzed/Death 明確排除在外，不能被硬凹回 Hurt）
	elif current_state != "paralyzed" and current_state != "death" and not is_hyper_armored:
		if pending_damage != null:
			var kb: Vector2 = pending_damage["knockback_force"]
			velocity = kb
			pending_damage = null
		state_machine.transition_to("Hurt")

## 供不是透過 take_damage()/_on_hurtbox_hurt() 造成韌性歸零的來源呼叫（例如 GuardState 格擋成功的削韌）。
## _on_hurtbox_hurt() 裡的 Paralyzed 轉換只有在「真的挨了一下攻擊」時才會被檢查到，
## 如果韌性是被這種旁路扣到 0，is_broken 雖然會變 true，但不會有任何東西觸發狀態機轉換，
## 必須等到下一次真的被打中才會進癱瘓——這裡補上這個缺口，讓韌性一歸零就立刻進場
func check_poise_break() -> void:
	if stats == null or not stats.is_broken: return
	var current_state = state_machine.current_state.name.to_lower()
	if current_state != "paralyzed" and current_state != "death":
		state_machine.transition_to("Paralyzed")

func trigger_hurt_gate() -> void:
	if not _hurt_gate_active:
		_hurt_gate_active = true
		# 🌟 黃圈技被彈開強制進 Hurt 時，用比較長的閘門範圍當作懲罰；一般空窗期挨打維持原本範圍
		var gate_range = guard_break_hurt_gate_range if _next_hurt_uses_guard_break_range else hurt_gate_range
		_next_hurt_uses_guard_break_range = false
		_hurt_gate_end_time = (Time.get_ticks_msec() / 1000.0) + randf_range(gate_range.x, gate_range.y)

func is_hurt_gate_open() -> bool:
	if not _hurt_gate_active:
		return true
	if (Time.get_ticks_msec() / 1000.0) >= _hurt_gate_end_time and is_on_floor():
		_hurt_gate_active = false
		return true
	return false

func face_player() -> void:
	if is_instance_valid(player_target):
		var dx = player_target.global_position.x - global_position.x
		# 🔧 死區：X 座標非常接近時不要每幀翻面，避免速度來回抵銷變成原地卡住
		if absf(dx) > 4.0:
			direction = sign(dx)
			
func _on_health_changed() -> void:
	if stats.health <= 0:
		if state_machine.current_state.name.to_lower() != "death":
			state_machine.transition_to("Death")
			
			# 🌟 新增：BOSS 死了，危機解除，相機平滑拉回預設距離
			var world = get_tree().current_scene
			if world and world.has_method("set_boss_camera_mode"):
				world.set_boss_camera_mode(false)
		return
		
	if current_phase == 1 and stats.health <= (stats.max_health * 0.5):
		current_phase = 2
		print("🔥 奈何橋：進入二階段！狂暴化！")

func wake_up() -> void:
	if state_machine.current_state.name.to_lower() == "dormant":
		print("🔥 奈何橋被喚醒！BOSS 戰開始！")
		state_machine.transition_to("Decision")
		
		if has_node("BossUI"):
			$BossUI.show_boss_bar()

# ==========================================
# 🎬 特效接口
# ==========================================
# play_safe_anim() 已搬到 Enemy.gd 基底，讓所有敵人共用同一套「動畫安全播放」邏輯

func fire_cannon() -> void:
	if not CANNON_SCENE: return
	var cannon = CANNON_SCENE.instantiate() as NaiheCannon
	get_tree().current_scene.add_child(cannon)
	
	cannon.global_position = global_position + Vector2(40 * direction, -30)
	cannon.direction = direction
	
	if CombatManager.has_method("apply_camera_shake"):
		CombatManager.apply_camera_shake(15.0)

func spawn_ground_spike() -> void:
	if not SPIKE_SPAWNER_SCENE: return
	var spawner = SPIKE_SPAWNER_SCENE.instantiate()
	get_tree().current_scene.add_child(spawner)
	 
	# 🌟 先算好座標
	var start_pos = global_position + Vector2(60 * direction, 0)
	
	# 🌟 手動下達啟動指令！這樣第一根絕對不會跑掉！
	spawner.start_spawning(start_pos, direction)
	
	if CombatManager.has_method("apply_camera_shake"):
		CombatManager.apply_camera_shake(15.0, 0.2)

# 🌟 A4 專屬接口：只放 3 根地刺
func spawn_ground_spike_a4() -> void:
	if not SPIKE_SPAWNER_SCENE: return
	var spawner = SPIKE_SPAWNER_SCENE.instantiate()
	get_tree().current_scene.add_child(spawner)
	
	# 🌟 核心技巧：動態覆寫屬性！無視編輯器的設定，強制改為 3 根！
	spawner.max_spikes = 3
	
	var start_pos = global_position + Vector2(180 * direction, 0)
	spawner.start_spawning(start_pos, direction)
	
	if CombatManager.has_method("apply_camera_shake"):
		CombatManager.apply_camera_shake(15.0, 0.2)
		
# ==========================================
# 🔪 Hitbox 控制 (動畫軌道呼叫)
# ==========================================
func enable_hitbox(shape_name: String = "") -> void:
	var hb = get_node_or_null("Graphics/WeaponHitbox") as Hitbox
	if hb:
		hb.hit_targets.clear()
		
		var is_pull_attack = (shape_name == "Shape_A8_Pull") or (animation_player and animation_player.current_animation.ends_with("attack_8"))
		
		if is_pull_attack:
			hb.sticky_multi_hit = true
			hb.max_hits = 1
			hb.hit_interval = 0.1
			hb.damage_amount = 0
			hb.attack_type = Damage.Type.NO_STUN

			# 🌟 核心修復：改用 Hitbox.gd 本來就有的 pull_towards_owner 機制——它在命中「當下」才即時算
			# 玩家跟 boss 的相對位置，不像之前手動清 absolute_knockback 那樣，其實會被 _execute_hit()
			# 每次命中無條件覆寫掉、變成用「攻擊前搖開始時」就鎖死的舊朝向，玩家繞到 boss 背後時方向會算反
			hb.pull_towards_owner = true
			hb.knockback_force = Vector2(600.0, 0.0)

			hb.spark_type = Hitbox.SparkType.OTHER
			hb.custom_spark_scene = null

		else:
			# 🔄 普通招式：還原所有的面板設定
			hb.pull_towards_owner = false # 🔧 確保 A8 用過後不會殘留吸力模式
			if not _hb_defaults.is_empty():
				hb.sticky_multi_hit = _hb_defaults["sticky_multi_hit"]
				hb.max_hits = _hb_defaults["max_hits"]
				hb.hit_interval = _hb_defaults["hit_interval"]
				hb.damage_amount = _hb_defaults["damage_amount"]
				hb.attack_type = _hb_defaults["attack_type"]
				hb.knockback_force = _hb_defaults["knockback_force"] # 🌟 還原擊退力！
				hb.spark_type = _hb_defaults["spark_type"] # 🔧 還原火花：修復 A8 用過後永久沒火花的問題
				hb.custom_spark_scene = _hb_defaults["custom_spark_scene"]

			# 普通招式維持原有的強制定向擊退邏輯
			var base_kb_x = abs(hb.knockback_force.x)
			var base_kb_y = hb.knockback_force.y
			if "absolute_knockback" in hb:
				hb.absolute_knockback = Vector2(base_kb_x * direction, base_kb_y)
		
		# 開啟對應的 Hitbox
		for child in hb.get_children():
			if child is CollisionShape2D and (shape_name == "" or child.name == shape_name):
				child.set_deferred("disabled", false)

func disable_hitbox(shape_name: String = "") -> void:
	var hb = get_node_or_null("Graphics/WeaponHitbox")
	if hb:
		for child in hb.get_children():
			if child is CollisionShape2D and (shape_name == "" or child.name == shape_name):
				child.set_deferred("disabled", true)
