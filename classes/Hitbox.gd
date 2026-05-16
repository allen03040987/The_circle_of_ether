class_name Hitbox
extends Area2D
## 萬用攻擊判定框 (Hitbox)
## 處理主動攻擊判定、傷害計算、多段連擊、打擊感特效 (時停/震動/火花) 及合軸資源發放。

# ==========================================
# 🎛️ 1. 基礎設定與戰鬥屬性
# ==========================================
enum SparkType { SLASH, BLUNT, OTHER }

@export_group("基礎攻擊屬性")
@export var damage_amount: int = 1
@export var attack_type: Damage.Type = Damage.Type.LIGHT # 決定受擊硬直程度
@export var knockback_force: Vector2 = Vector2(150.0, 0.0) # 基礎擊退力道
@export var poise_damage: float = 10.0 # 削韌數值

# 是否啟用「黑洞聚怪」模式 (將受擊者往 Hitbox 中心拉)
@export var pull_towards_owner: bool = false

var absolute_knockback: Vector2 = Vector2.ZERO # 絕對擊退方向 (由程式動態覆寫)

# ==========================================
# 🌟 2. 動態合軸資源 (由武器動態注入)
# ==========================================
var energy_reward: float = 0.0 # 大招能量
var switch_reward: float = 0.0 # 協奏/切換值

var iai_reward: int = 0        # 專屬資源 (如太刀居合)
var pozhen_reward: int = 0     # 專屬資源 (如長槍破陣值)

var multi_hit_energy: bool = false # 是否每段攻擊皆給予資源

# ==========================================
# 🔄 3. 多段連擊與黏著打擊
# ==========================================
@export_group("多段連擊設定")
@export var max_hits: int = 1 # 總段數
@export var hit_interval: float = 0.0 # 段數間隔 (秒)
@export var sticky_multi_hit: bool = false # 開啟後跨狀態必定打完所有段數

# ==========================================
# 🧃 4. 打擊感與視覺特效 (VFX)
# ==========================================
@export_group("打擊回饋")
@export var hitstop_duration: float = 0.0 # 卡肉 (時停) 時間
@export var shake_intensity: float = 0.0  # 震動強度
@export var shake_on_hit_only: bool = true # 是否僅在命中時震動
@export var spark_type: SparkType = SparkType.SLASH

@export_group("火花進階設定")
@export var spark_base_offset: Vector2 = Vector2.ZERO
@export var attach_spark_to_victim: bool = true # 火花是否跟隨受擊者
@export var spark_random_angle: float = 20.0
@export var spark_random_offset: Vector2 = Vector2(15.0, 15.0)
@export var spark_scale: float = 1.0
@export var spark_color: Color = Color.WHITE
@export var spark_raw_intensity: float = 2.0
@export var custom_spark_scene: PackedScene
@export var aura_color: Color = Color(1.0, 1.0, 1.0, 0.5) 

# ==========================================
# 📡 5. 內部變數與信號
# ==========================================
signal hit(hurtbox: Node)

var hit_targets: Dictionary = {} # 受害者名單：記錄打到誰、次數、時間
var _has_shaken_this_attack: bool = false 
@onready var base_damage: int = damage_amount
var has_generated_energy: bool = false 

# ==========================================
# ⚙️ 核心生命週期
# ==========================================
func _ready() -> void:
	area_entered.connect(_on_area_entered)

func _process(_delta: float) -> void:
	# 使用現實絕對時間，確保時停期間邏輯不受干擾
	var current_time = Time.get_ticks_msec() / 1000.0

	var has_active_shape: bool = false
	if self.monitoring:
		for child in get_children():
			if (child is CollisionShape2D or child is CollisionPolygon2D) and not child.disabled:
				has_active_shape = true
				break
				
	# --- 處理空揮震動 ---
	if has_active_shape:
		if not shake_on_hit_only and not _has_shaken_this_attack and shake_intensity > 0:
			if CombatManager.has_method("apply_camera_shake"):
				CombatManager.apply_camera_shake(shake_intensity)
			_has_shaken_this_attack = true 
	else:
		_has_shaken_this_attack = false
		
	# --- 防呆清理 1：非黏著攻擊正常結束 ---
	if not has_active_shape and not sticky_multi_hit:
		if not hit_targets.is_empty():
			hit_targets.clear()
		has_generated_energy = false
		return 

	# ==========================================
	# 🌀 黏著打擊迴圈 (Sticky Execution Loop)
	# ==========================================
	var dead_targets = []
	var all_sticky_finished: bool = true 

	for hurtbox in hit_targets.keys():
		if not is_instance_valid(hurtbox):
			dead_targets.append(hurtbox)
			continue
			
		var data: Dictionary = hit_targets[hurtbox]

		if sticky_multi_hit:
			if data["hits_done"] < max_hits:
				all_sticky_finished = false 
				
				# 滿足間隔時間，強制出傷 (無視判定框是否已關閉)
				if current_time - data["last_hit_time"] >= hit_interval:
					_execute_hit(hurtbox)
					data["hits_done"] += 1
					data["last_hit_time"] = current_time 

	# 清理已失效的目標，防止 Memory Leak
	for target in dead_targets:
		hit_targets.erase(target)

	# --- 防呆清理 2：黏著攻擊完整結束 ---
	if not has_active_shape and sticky_multi_hit and all_sticky_finished:
		hit_targets.clear()
		has_generated_energy = false
		return

	# --- 持續索敵 (僅限非黏著且開框狀態) ---
	if not sticky_multi_hit and hit_interval > 0.0 and has_active_shape:
		for area in get_overlapping_areas():
			_try_hit(area)

# ==========================================
# ⚔️ 核心戰鬥邏輯 (Core Combat Logic)
# ==========================================
func _on_area_entered(area: Area2D) -> void:
	_try_hit(area)

# 嘗試對目標建檔並觸發傷害
func _try_hit(area: Area2D) -> void:
	# --- 1. 基本有效性檢驗 ---
	if not (area is CollisionObject2D and "hurt" in area): return
	if not is_instance_valid(area.owner): return
	if area.owner == self.owner: return # 友軍傷害防護 (不打自己)
	
	var victim: Node = area.owner
	
	# --- 2. 無敵幀與極限閃避判定 ---
	if is_instance_valid(victim):
		if victim is Player:
			if victim.invincible_timer.time_left > 0 or victim.get("is_weapon_invincible"):
				return 
				
		if "state_machine" in victim:
			var sm: Node = victim.state_machine
			if is_instance_valid(sm) and is_instance_valid(sm.current_state):
				if sm.current_state.name.to_lower() == "slide":
					if sm.current_state.has_method("trigger_perfect_dodge"):
						sm.current_state.trigger_perfect_dodge()
					register_dodge(area) # 閃避成功，記一筆但不扣血
					return
				
	# --- 3. 受害者名單建檔與段數檢查 ---
	if not hit_targets.has(area):
		hit_targets[area] = {"hits_done": 0, "last_hit_time": 0.0}
		
	var data: Dictionary = hit_targets[area]
	if data["hits_done"] >= max_hits: return 
		
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# --- 4. 攻擊間隔判定與出傷 ---
	if data["hits_done"] == 0 or (current_time - data["last_hit_time"] >= hit_interval):
		_execute_hit(area)
		data["hits_done"] += 1
		data["last_hit_time"] = current_time

# 執行傷害派發、合軸資源發放與打擊特效
func _execute_hit(hurtbox: Node) -> void:
	# --- 1. 計算絕對擊退方向 ---
	var attacker_dir: int = 1
	if is_instance_valid(self.owner) and "direction" in self.owner:
		attacker_dir = self.owner.direction
	elif is_instance_valid(self.owner) and "player" in self.owner and is_instance_valid(self.owner.player) and "direction" in self.owner.player:
		attacker_dir = self.owner.player.direction # 武器代為詢問玩家面向
		
	# 核心聚怪邏輯：如果開啟黑洞模式，計算對方相對於我的位置，給予反方向拉力
	if pull_towards_owner and is_instance_valid(hurtbox):
		var victim_node = hurtbox.owner if is_instance_valid(hurtbox.owner) else hurtbox
		# 計算怪物在我的左邊(-1)還是右邊(1)，然後乘上負數變成拉力
		var pull_dir = sign(self.global_position.x - victim_node.global_position.x)
		if pull_dir == 0: pull_dir = attacker_dir
		
		# 使用 abs() 確保原本填的數值不會被搞亂，強制轉化為向心力
		absolute_knockback = Vector2(abs(knockback_force.x) * pull_dir, knockback_force.y)
	else:
		# 正常攻擊，照著玩家面向擊退
		absolute_knockback = Vector2(knockback_force.x * attacker_dir, knockback_force.y)
	
	# --- 2. 傳遞傷害訊號 ---
	hit.emit(hurtbox)     
	
	if hurtbox.has_method("hurt"):
		hurtbox.hurt(self)
	elif hurtbox.has_signal("hurt"):
		hurtbox.emit_signal("hurt", self) 
	
	# --- 3. 合軸戰鬥資源發放 ---
	var players = get_tree().get_nodes_in_group("Player")
	if players.size() > 0:
		var p = players[0]
		if is_instance_valid(p) and hurtbox.owner != p:
			if multi_hit_energy or not has_generated_energy:
				# 發放專屬資源 (如居合)
				if iai_reward > 0 and is_instance_valid(p.current_weapon):
					if p.current_weapon.has_method("gain_iai"):
						p.current_weapon.gain_iai(iai_reward)
				# 發放長槍專屬資源 (破陣值)
				if pozhen_reward > 0 and is_instance_valid(p.current_weapon):
					if p.current_weapon.has_method("gain_pozhen"):
						p.current_weapon.gain_pozhen(pozhen_reward)
						
				# 發放通用資源 (大招能量與協奏值)
				if energy_reward > 0 or switch_reward > 0:
					if multi_hit_energy or not has_generated_energy:
						var w_id = "katana"
						if is_instance_valid(p.current_weapon) and "WEAPON_ID" in p.current_weapon:
							w_id = p.current_weapon.WEAPON_ID
								
						if p.has_method("add_weapon_resource"):
							p.add_weapon_resource(w_id, energy_reward, switch_reward)
						
						if not multi_hit_energy:
							has_generated_energy = true
	
	# --- 4. 觸發打擊感回饋 (卡肉與震動) ---
	if hitstop_duration > 0 and CombatManager.has_method("apply_hitstop"):
		CombatManager.apply_hitstop(hitstop_duration)
	if shake_intensity > 0 and CombatManager.has_method("apply_camera_shake"):
		CombatManager.apply_camera_shake(shake_intensity)
		
	# --- 5. 生成火花與打擊特效 ---
	if (spark_type != SparkType.OTHER or custom_spark_scene != null) and CombatManager.has_method("spawn_spark"):
		var base_pos: Vector2 = hurtbox.global_position
		base_pos.x += spark_base_offset.x * attacker_dir
		base_pos.y += spark_base_offset.y
		
		var spawn_pos: Vector2 = base_pos
		spawn_pos.x += randf_range(-spark_random_offset.x, spark_random_offset.x)
		spawn_pos.y += randf_range(-spark_random_offset.y, spark_random_offset.y)
		
		var angle_offset: float = randf_range(-spark_random_angle, spark_random_angle)
		var target: Node = hurtbox.owner if attach_spark_to_victim else null
		
		# 把 spark_raw_intensity 放到參數最後面
		CombatManager.spawn_spark(
			spark_type, spawn_pos, attacker_dir, target, angle_offset,
			spark_scale, spark_color, custom_spark_scene, aura_color, spark_raw_intensity
		)

# 紀錄極限閃避次數，避免重複判定
func register_dodge(hurtbox: Area2D) -> void:
	if not hit_targets.has(hurtbox):
		hit_targets[hurtbox] = {"hits_done": 0, "last_hit_time": 0.0}
	var data: Dictionary = hit_targets[hurtbox]
	if data["hits_done"] < max_hits:
		data["hits_done"] += 1
