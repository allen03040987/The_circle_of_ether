class_name HealingTower
extends Node2D

# ==========================================
# 📊 數值設定面板
# ==========================================
@export var lifespan: float = 10.0          # 存在總時間 (秒)
@export var pulse_interval: float = 1.0     # 每次爆發間隔 (秒)
@export var heal_amount: int = 2           # 每次爆發的回血量
@export var damage_amount: int = 50         # 每次爆發的傷害量

# 內部計時器
var _life_timer: float = 0.0
var _pulse_timer: float = 0.0
var direction: int = 1

# ==========================================
# 🔗 節點參考
# ==========================================
@onready var animation_player: AnimationPlayer = $AnimationPlayer
@onready var hitbox: Hitbox = $Hitbox             # 負責打怪的判定框
@onready var heal_area: Area2D = $HealArea       # 負責偵測玩家的回血範圍

func _ready() -> void:
	# 1. 初始化 Hitbox 數值
	if hitbox:
		hitbox.damage_amount = damage_amount
		hitbox.attack_type = Damage.Type.LIGHT 
		hitbox.knockback_force = Vector2(80 * direction, -200) 
		hitbox.hit_interval = 0.0 
		
		# ==========================================
		# 🌟 核心修復：完全仿照符咒 A1 的打擊火花與音效！
		# ==========================================
		hitbox.hit_sfx_type = "hit" # 確保打到怪時播的是清脆的 Hit 音效
		hitbox.spark_type = 0
		hitbox.spark_scale = 0.3
		hitbox.spark_color = Color(0.2, 0.8, 1.5, 1.0) # 靈能青藍色
		hitbox.aura_color = Color(0.0, 0.5, 1.0, 1.0)
		
	# 2. 召喚出來的瞬間，立刻強制觸發第一次爆發！
	trigger_pulse()

func _process(delta: float) -> void:
	# 使用普通的 delta，這樣當遊戲觸發時停(time_scale < 1)時，
	# 塔的計時也會乖乖慢下來，不會在時停期間瞬間消失！
	_life_timer += delta
	_pulse_timer += delta
	
	# 🌟 爆發計時器
	if _pulse_timer >= pulse_interval:
		_pulse_timer = 0.0
		trigger_pulse()
		
	# 🌟 壽命計時器
	if _life_timer >= lifespan:
		die()

# ==========================================
# 💥 核心邏輯：脈衝爆發 (攻擊 + 回血)
# ==========================================
func trigger_pulse() -> void:
	# (保留音效與動畫邏輯)
	if AudioManager.has_method("play_action_sfx"):
		AudioManager.play_action_sfx("Earthquake", -0.0)
		AudioManager.play_action_sfx("Get_notification", -10.0)

	if animation_player.has_animation("pulse"):
		animation_player.stop() 
		animation_player.play("pulse")
		
	if hitbox:
		hitbox.hit_targets.clear()
		
	# 🌟 終極解法 1：強制等待一幀，讓物理引擎有時間更新碰撞判定！
	await get_tree().physics_frame
	
	if is_instance_valid(heal_area):
		# 🌟 終極解法 2：不管是實體(Body)還是判定框(Area)，我全都要抓！
		var targets = heal_area.get_overlapping_bodies()
		targets.append_array(heal_area.get_overlapping_areas())
		
		var has_healed = false # 防呆：確保一次脈衝只補一次血
		
		for t in targets:
			# 順藤摸瓜：如果是 Hurtbox，就找它的 owner (Player 本人)
			var target_node = t if t is Player or t.name == "Player" else t.owner
			
			if is_instance_valid(target_node) and target_node is Player and not has_healed:
				if target_node.get("stats") and "health" in target_node.stats:
					
					# 🌟 核心修復：直接利用你完美的 Setter！
					# 寫法極度乾淨，且絕對不會觸發 float 轉 int 的型別報錯
					target_node.stats.health += heal_amount
					
					print("💚 [回血塔] 成功捕獲玩家！恢復 ", heal_amount, " HP！當前 HP: ", target_node.stats.health)
					
					if target_node.has_method("spawn_anim_vfx"):
						target_node.spawn_anim_vfx("heal_flash", 0, -30)
						
					has_healed = true

# ==========================================
# ⚰️ 壽終正寢
# ==========================================
func die() -> void:
	set_process(false)
	
	# 讓塔優雅地淡出消失，而不是瞬間不見
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(self.queue_free)
