class_name HealthPack
extends Item
## 血包：沒有動畫，按下去直接補血 + 一個小特效，靠存檔點回滿次數（跟現有 save_stone.gd 回血/回能量同一套邏輯）

const NORMAL_MAX_CHARGES: int = 3
const DEV_MODE_MAX_CHARGES: int = 99 ## 開發模式：上限直接拉到 99，方便測試不用一直跑存檔點

@export var heal_amount: int = 15 # 佔位數值，血量上限 50，先抓 30% 左右，之後再調

func _ready() -> void:
	item_name = "血包"
	_apply_dev_mode_cap()
	if not Game.settings_changed.is_connected(_on_settings_changed):
		Game.settings_changed.connect(_on_settings_changed)

func _apply_dev_mode_cap() -> void:
	max_charges = DEV_MODE_MAX_CHARGES if Game.config_dev_mode else NORMAL_MAX_CHARGES

## 開發模式開關被切換時即時生效：開了直接補滿到 99，關了把目前次數夾回正常上限，避免殘留超額次數
func _on_settings_changed() -> void:
	_apply_dev_mode_cap()
	current_charges = max_charges if Game.config_dev_mode else min(current_charges, max_charges)

func use() -> bool:
	if current_charges <= 0: return false
	if not is_instance_valid(player) or not ("stats" in player): return false

	current_charges -= 1
	player.stats.health += heal_amount
	_spawn_heal_vfx()
	return true

func _spawn_heal_vfx() -> void:
	if not CombatManager.has_method("spawn_spark"): return
	CombatManager.spawn_spark(
		Hitbox.SparkType.BLUNT, player.global_position, 1, player, 0.0, 1.2,
		Color(0.3, 1.0, 0.4, 1.0), null, Color(0.5, 1.0, 0.6, 1.0), 1.5
	)
