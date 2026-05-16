class_name BaseStats
extends Resource

# ==========================================
# 📊 角色/怪物 基礎屬性模板
# ==========================================

@export_group("生命與防禦 (Health & Defense)")
## 最大血量
@export var max_health: int = 3
## 破韌系統 (未來擴充用)
@export var max_poise: float = 100.0   

@export_group("玩家能量與機動 (Energy)")
## 最大體力/能量
@export var max_energy: float = 9.0
## 每秒能量回復速度
@export var energy_regen: float = 2.0
