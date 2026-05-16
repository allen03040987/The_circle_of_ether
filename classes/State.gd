class_name State
extends Node
## 狀態基底類別 (State Base Class)
## 這是所有狀態的「合約/插座」。它本身不做任何事，只定義了必須具備的方法，
## 讓狀態機總監可以統一呼叫，不用管現在到底是哪個具體狀態。

# 🌟 這兩個變數會由 StateMachine 初始化時自動「注入 (Inject)」，
# 讓繼承的子狀態可以直接呼叫 `player.velocity` 或 `state_machine.transition_to()`
var player: Player
var state_machine: StateMachine

# 🎬 進入狀態時觸發 (只執行一次)
# 適合用來：播放這招的專屬動畫、重置攻擊次數、清除殘留變數
func enter() -> void:
	pass

# 🚪 離開狀態時觸發 (只執行一次)
# 適合用來：強制中斷攻擊、重置特寫鏡頭、關閉 Hitbox (防止帶到下一個狀態)
func exit() -> void:
	pass

# 🔄 對應 _process (每幀執行)
# 適合用來：處理計時器倒數、UI 更新等「不涉及物理碰撞」的邏輯
func update(_delta: float) -> void:
	pass

# 🏃 對應 _physics_process (每幀執行)
# 適合用來：物理移動 (custom_move_and_slide)、接收玩家輸入並決定要不要派生新狀態
func physics_update(_delta: float) -> void:
	pass
