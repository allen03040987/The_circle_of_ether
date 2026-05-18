class_name BossNaihe
extends Enemy
## 奈何橋 (Naihe Bridge) - 關底 BOSS
## 負責管理 BOSS 專屬技能、階段轉換與 Hitbox 動態方向賦予。

@onready var state_machine: StateMachine = $StateMachine
@onready var player_target: Player = get_tree().get_first_node_in_group("Player") 
@onready var hurtbox: Hurtbox = $Graphics/Hurtbox

const CANNON_SCENE = preload("res://enemies/boss/BossNaihe/NaiheCannon.tscn")
# 在最上面的 const 區塊加入這行：
const SPIKE_SPAWNER_SCENE = preload("res://enemies/boss/BossNaihe/NaiheSpikeSpawner.tscn")
# --- 戰鬥階段與招式 ---
var current_phase: int = 1

var _hb_defaults := {} # 🌟 用來備份 Hitbox 的初始面板設定

const ATTACKS = {
	"combo_1": {"anim": "naihe/attack_1", "dist": 150}, 
	"combo_2": {"anim": "naihe/attack_2", "dist": 150}, 
}
var current_attack_anim: String = ""

# ==========================================
# ⚙️ 初始化與生命週期
# ==========================================
func _ready() -> void:
	can_be_launched = false
	has_full_super_armor = true
	
	# 🌟 記下面板設定
	var hb = get_node_or_null("Graphics/WeaponHitbox")
	if hb:
		_hb_defaults = {
			"sticky_multi_hit": hb.get("sticky_multi_hit"),
			"max_hits": hb.get("max_hits"),
			"hit_interval": hb.get("hit_interval"),
			"damage_amount": hb.get("damage_amount"),
			"attack_type": hb.get("attack_type"),
			"knockback_force": hb.get("knockback_force") # 🌟 多備份這行擊退力！
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
	# 1. 呼叫基底計算傷害與削韌
	take_damage(hitbox)
	 
	# 🌟 2. 唯一攔截：只看有沒有被打出癱瘓！
	if stats and stats.is_broken:
		# 確保不會在已經癱瘓或死亡時重複觸發
		var current_state = state_machine.current_state.name.to_lower()
		if current_state != "paralyzed" and current_state != "death":
			state_machine.transition_to("Paralyzed")
			
func face_player() -> void:
	if is_instance_valid(player_target):
		var dir = sign(player_target.global_position.x - global_position.x)
		if dir != 0:
			direction = dir 
			
func _on_health_changed() -> void:
	if stats.health <= 0:
		if state_machine.current_state.name.to_lower() != "death":
			state_machine.transition_to("Death")
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
# 🎬 動畫安全播放與特效接口
# ==========================================
func play_safe_anim(anim_name: String) -> void:
	if animation_player.has_animation(anim_name):
		if animation_player.current_animation != anim_name:
			# 強制套用緩速乘數 (支援韌性破防系統)
			animation_player.play(anim_name, -1, action_speed_mult)
	else:
		printerr("❌ BOSS 找不到動畫: ", anim_name)

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
			hb.max_hits = 5          
			hb.hit_interval = 0.1     
			hb.damage_amount = 0      
			hb.attack_type = Damage.Type.NO_STUN
			
			# 🌟 核心修復：直接改本體的擊退力！讓 Player.gd 完美的數學公式接管吸力！
			hb.knockback_force = Vector2(-400.0, 0.0) 
			
			# 把 absolute_knockback 清空，防止它蓋過我們漂亮的相對數學
			if "absolute_knockback" in hb:
				hb.absolute_knockback = Vector2.ZERO
			
			hb.spark_type = Hitbox.SparkType.OTHER 
			hb.custom_spark_scene = null
			
		else:
			# 🔄 普通招式：還原所有的面板設定
			if not _hb_defaults.is_empty():
				hb.sticky_multi_hit = _hb_defaults["sticky_multi_hit"]
				hb.max_hits = _hb_defaults["max_hits"]
				hb.hit_interval = _hb_defaults["hit_interval"]
				hb.damage_amount = _hb_defaults["damage_amount"]
				hb.attack_type = _hb_defaults["attack_type"]
				hb.knockback_force = _hb_defaults["knockback_force"] # 🌟 還原擊退力！
			
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
