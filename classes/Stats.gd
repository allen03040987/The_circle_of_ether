class_name Stats
extends Node
## 戰鬥數值核心 (Stats Core)

signal health_changed
signal energy_changed
signal poise_changed
signal poise_broken(is_broken: bool)

@export var base_stats: BaseStats 

var max_health: int
var max_energy: float
var energy_regen: float
var max_poise: float = 100.0

var is_broken: bool = false
var poise_recharge_speed: float = 20.0 

@onready var health: int = 1 :
	set(v):
		v = clampi(v, 0, max_health)
		if health == v: return
		health = v
		health_changed.emit()
		
@onready var energy: float = 1.0 :
	set(v):
		v = clampf(v, 0, max_energy)
		if energy == v: return
		energy = v
		energy_changed.emit()
		
var poise: float = 0.0 :
	set(v):
		v = clampf(v, 0.0, max_poise)
		if poise == v: return
		poise = v
		poise_changed.emit()
		
		if poise <= 0 and not is_broken:
			_enter_broken_state()

# ==========================================
# ⚙️ 初始化與時間流逝
# ==========================================
func _ready() -> void:
	if base_stats == null:
		printerr("⚠️ [Stats] 未配置 BaseStats，使用預設體質！")
		max_health = 3; max_energy = 9.0; energy_regen = 2.0; max_poise = 100.0
	else:
		max_health = base_stats.max_health
		max_energy = base_stats.max_energy
		energy_regen = base_stats.energy_regen
		max_poise = base_stats.max_poise
		
	health = max_health
	energy = max_energy
	poise = max_poise
	
func _process(delta: float) -> void:
	if energy < max_energy:
		energy += energy_regen * delta
	
	if is_broken:
		poise += poise_recharge_speed * delta
		if poise >= max_poise:
			_exit_broken_state()

# ==========================================
# 🛡️ 狀態控制
# ==========================================
func _enter_broken_state() -> void:
	is_broken = true
	poise_broken.emit(true)
	print("🛡️ 韌性崩潰！進入虛弱狀態")

func _exit_broken_state() -> void:
	is_broken = false
	poise = max_poise
	poise_broken.emit(false)
	print("🛡️ 韌性重置！恢復正常")
	
# ==========================================
# 💾 存檔與讀檔系統 (Save/Load)
# ==========================================
func to_dict() -> Dictionary:
	return {
		max_energy = max_energy, 
		max_health = max_health,
		health = health,
		energy = energy,
	}
	
func from_dict(dict: Dictionary) -> void:
	max_energy = dict.max_energy
	max_health = dict.max_health
	health = dict.health
	energy = dict.energy
