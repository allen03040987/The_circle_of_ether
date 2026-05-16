class_name Damage
extends RefCounted

# ==========================================
# 🎛️ 傷害類型定義 (Damage Types)
# ==========================================
enum Type { 
	NO_STUN,# 零硬直 (碰觸傷害/不中斷動作)
	LIGHT,  # 輕擊 (普通硬直)
	HEAVY,  # 重擊 (擊飛/挑空)
	THROW   # 投技 (被抓取/未來擴充)
	
}

# ==========================================
# 📦 封裝資料 (Data Payload)
# ==========================================
## 實際扣除的血量
var amount: int    
## 攻擊的發起者 (用於判斷擊退方向)
var source: Node2D = null 
## 攻擊的種類 (決定受擊方的狀態切換)
var type: Type = Type.LIGHT
## 擊退力度與方向向量
var knockback_force: Vector2 = Vector2.ZERO
