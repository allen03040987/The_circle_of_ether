extends Area2D
class_name VsHitbox

## 戰鬥判定框核心腳本 (攻擊方)
## 負責攜帶攻擊屬性 (傷害、擊退、硬直時間)，並管理多段打擊的冷卻與記憶。

# ==========================================
# 📋 面板參數設定 (Inspector 屬性)
# ==========================================
enum HitType { LIGHT, MEDIUM, HEAVY }

@export_group("⚔️ 攻擊傷害設定")
## 攻擊造成的基礎傷害數值。
@export var damage: float = 10.0

## 打中對手後，對方無法行動的受擊硬直時間 (秒)。數值越大，越容易接續連段。
@export var hitstun_time: float = 0.5        

## 攻擊類型標籤 (0=輕擊, 1=中擊, 2=重擊)。可用於受擊方決定要播哪種受傷動畫或音效。
@export var hit_type: int = 0

## 破防開關：開啟時 (True)，無視對手的防禦狀態強行造成傷害與硬直。
@export var guard_break: bool = false 

## 破霸開關：開啟時 (True)，無視對手的霸體狀態強行打斷對手動作。
@export var armor_break: bool = false 

@export_group("🪂 擊退與倒地設定")
## 擊中「站在地上」的對手時，給予的擊退力道 (X為水平，Y為垂直)。
@export var ground_knockback: Vector2 = Vector2(150, 0)

## 擊中「在空中」的對手時，給予的擊退力道。(通常 Y 會給負值讓他繼續浮空，或給正值強制砸地)。
@export var air_knockback: Vector2 = Vector2(100, -400) 

## 擊退時的地面摩擦力。數值越大，對手滑行的距離越短 (煞車越快)。
@export var knockback_friction: float = 5000.0

## 強制倒地：開啟時，對手受擊後會進入擊飛且必須躺平的「倒地狀態 (Hard Knockdown)」。
@export var causes_down: bool = false

## 掃地判定 (OTG - Off The Ground)：開啟時，此招能擊中已經倒在地上無敵的對手。
@export var can_hit_otg: bool = false

## 水平擊退隨機誤差值。例如填 50，則實際 X 擊退力會在 -50 到 +50 之間隨機浮動。
@export var random_x_variance: float = 0.0 

@export_group("🔄 多段連擊設定")
## 該判定框對「同一個敵人」最多可造成的傷害總次數。
## 1 為單發普攻；填入大數字則變成絞肉機/持續傷害。
@export var max_hits: int = 1

## 多段連擊的觸發間隔秒數。例如 0.2 代表每 0.2 秒對同一個敵人造成一次傷害。
@export var hit_interval: float = 0.0 

## 單發即逝：只要打中任何一個目標，立即物理關閉此判定框 (適用於狙擊槍或絕對單體攻擊)。
@export var auto_disable_on_hit: bool = false

@export_group("🩸 異常狀態(流血)設定")
## 裝備在此判定框上的自定義流血火花路徑陣列。
@export var hit_sparks: Array[String] = []

## 附魔：每次異常狀態跳血時扣除的血量。(數值大於 0 才會為對手掛上流血狀態)。
@export var bleed_damage: float = 0.0      

## 異常狀態的總持續時間 (秒)。
@export var bleed_duration: float = 5.0    

## 異常狀態的跳血間隔 (例如 0.5 代表每半秒扣一次血)。
@export var bleed_tick_interval: float = 0.5 

## 刷新機制：True = 被此招打中幾次就疊加/刷新幾次毒素；False = 只有第一下命中會上毒。
@export var bleed_every_hit: bool = false

@export_group("⏳ 命中減CD (技能回饋)")
## 填入要減 CD 的技能插槽名稱 (例如 "Skill_Air")。留空則不啟用。
@export var refresh_cd_slot: String = "" 

## 打中敵人時要減少的冷卻秒數。(填 999 代表完全刷新重置)。
@export var reduce_cd_amount: float = 0.0 

@export_group("✨ 視覺特效與震動")
## 受擊時生成的火花/特效場景。可填入多種，將作為隨機池或陣列傳遞給受擊者生成。
@export var hit_effect_1: PackedScene 
@export var hit_effect_2: PackedScene 
@export var hit_effect_3: PackedScene
@export var hit_effect_4: PackedScene 
@export var hit_effect_5: PackedScene

## 每次擊中時，要同時噴出幾個火花？
@export var spark_count: int = 1       

## 連續噴出多個火花時，每個火花生成的延遲時間 (秒)。製造「刷刷刷」的連續切割視覺感。
@export var spark_interval: float = 0.0 

## 火花生成的基準偏移量 (相對於受擊者的中心點)。
@export var spark_offset: Vector2 = Vector2(0, -15) 

## 是否讓火花在 360 度內隨機旋轉 (適用於十字斬或圓形爆炸特效)。
@export var random_spark_angle: bool = false 

## 火花生成的隨機擴散範圍。例如 Vector2(20, 20) 代表在中心周圍 20 像素內隨機噴發。
@export var random_spark_spread: Vector2 = Vector2.ZERO

## 攻擊命中時的螢幕震動強度 (0 代表不震動)。
@export var shake_intensity: float = 0.0 

## 螢幕震動的持續時間 (秒)。
@export var shake_duration: float = 0.0

## 若為多段連擊，是否只在「第一下」打中時觸發螢幕震動，防止持續震動導致玩家暈眩。
@export var shake_only_first_hit: bool = true

# ==========================================
# ⚙️ 內部變數 (不可在面板修改)
# ==========================================
## 攻擊者的實體參照 (近戰為玩家，遠程為發射者)。由爬樹機制自動尋找綁定。
var owner_player: Node2D = null 

## 打擊記憶字典。記錄「打過誰」、「打了幾下」、「還要等多久才能打下一回」。
## 結構：{ hurtbox_node : {"hits_done": 0, "cooldown": 0.0} }
var hit_targets: Dictionary = {}

## 標記當前攻擊判定是否處於開啟狀態。用於防止幽靈判定。
var _attack_session_active: bool = false 

# ==========================================
# 🚀 核心邏輯
# ==========================================
func _ready() -> void:
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
		
	# 🌟 終極尋父機制 (爬樹法)
	# 不管 Hitbox 被包在多深的節點裡，都會往上找，直到找到 CharacterBody2D 為止
	var current_node = get_parent()
	while current_node != null and current_node != get_tree().root:
		if current_node is CharacterBody2D: 
			owner_player = current_node
			break
		current_node = current_node.get_parent()

func _physics_process(delta: float) -> void:
	# ------------------------------------------
	# 1. 偵測開關狀態 (完美支援 monitoring 與 disabled 兩種動畫寫法)
	# ------------------------------------------
	var is_currently_active = monitoring
	var has_active_shape = false
	
	for child in get_children():
		if (child is CollisionShape2D or child is CollisionPolygon2D) and not child.disabled:
			has_active_shape = true
			break
			
	is_currently_active = is_currently_active and has_active_shape

	# 當攻擊框被關閉時，立刻洗掉所有打擊記憶，確保下次揮刀能重新判定
	if not is_currently_active:
		if _attack_session_active:
			hit_targets.clear()
			_attack_session_active = false
		return 
		
	# ------------------------------------------
	# 2. 喚醒瞬間的主動掃描 (解決貼臉揮空 Bug)
	# ------------------------------------------
	# 如果動畫一開啟的瞬間，敵人已經站在框裡面，area_entered 不會觸發！
	# 必須用 get_overlapping_areas() 主動抓取一次。
	if not _attack_session_active:
		_attack_session_active = true
		for area in get_overlapping_areas():
			_try_hit(area)
	
	# ------------------------------------------
	# 3. 更新所有「正在冷卻中」的敵人計時器
	# ------------------------------------------
	var dead_targets = []
	for hurtbox in hit_targets.keys():
		if not is_instance_valid(hurtbox):
			dead_targets.append(hurtbox)
			continue
			
		if hit_targets[hurtbox]["cooldown"] > 0.0:
			hit_targets[hurtbox]["cooldown"] -= delta

	# 清除已死亡/被刪除的受害者節點，防止記憶體洩漏
	for target in dead_targets:
		hit_targets.erase(target)

	# ------------------------------------------
	# 4. 絞肉機掃描 (多段持續傷害專用)
	# ------------------------------------------
	# 如果這是一招持續傷害 (如雷射或旋風斬)，每幀檢查是否有可以再次受傷的目標
	if hit_interval > 0.0:
		for area in get_overlapping_areas():
			_try_hit(area)

func _on_area_entered(area: Area2D) -> void:
	# 碰到受擊框邊界的第一瞬間觸發
	_try_hit(area)

# 獨立的「嘗試打擊」邏輯 (單發與連擊共用)
func _try_hit(area: Area2D) -> void:
	# 基本身份審核：必須是 Hurtbox，且不能是自己人
	if not area is VsHurtbox: return
	if area.owner_player == self.owner_player: return
	
	# 新受害者建檔 (建立獨立的打擊次數與冷卻追蹤)
	if not hit_targets.has(area):
		hit_targets[area] = {"hits_done": 0, "cooldown": 0.0}
		
	var data = hit_targets[area]
	
	# 檢查打擊次數上限 (防無限連擊)
	if data["hits_done"] >= max_hits:
		return
		
	# 檢查該目標的打擊冷卻時間是否結束
	if data["cooldown"] <= 0.0:
		var is_first_hit = (data["hits_done"] == 0)
		
		# 💥 呼叫敵人的受傷函數，送出傷害與自身的所有武器屬性！
		area.take_hit(self, is_first_hit) 
		
		# 更新受害者檔案：次數 +1，並進入冷卻
		data["hits_done"] += 1
		data["cooldown"] = hit_interval 
		
		# 💥 若開啟「單發即逝」，打中一人後立即將自己的物理形狀閹割
		if auto_disable_on_hit:
			for child in get_children():
				if child is CollisionShape2D or child is CollisionPolygon2D:
					child.set_deferred("disabled", true)
