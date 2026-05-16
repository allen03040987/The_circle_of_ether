## 統一的除錯工具類別
## 提供集中化的除錯輸出管理，方便在開發和生產環境間切換
class_name DebugTool

## 除錯模式開關
static var enabled := true

## 攻擊系統除錯標誌
static var attack_debug := true

## 狀態機除錯標誌
static var state_machine_debug := true

## 輸入系統除錯標誌
static var input_debug := true

# ==========================================
# 🐛 通用除錯方法
# ==========================================

## 通用除錯輸出
static func debug_log(context: String, message: String, data: Variant = null) -> void:
	if not enabled: return
	
	var output = "🔍 [" + context + "] " + message
	if data != null:
		output += ": " + str(data)
	print(output)

## 錯誤輸出
static func error(context: String, message: String, data: Variant = null) -> void:
	var output = "❌ [" + context + "] " + message
	if data != null:
		output += ": " + str(data)
	printerr(output)

## 警告輸出
static func warn(context: String, message: String, data: Variant = null) -> void:
	var output = "⚠️ [" + context + "] " + message
	if data != null:
		output += ": " + str(data)
	print(output)

# ==========================================
# ⚔️ 攻擊系統專用除錯
# ==========================================

## 攻擊執行除錯
static func log_attack_execute(function_name: String, combo_step: int, last_attack_time: float, frame: int = -1) -> void:
	if not enabled or not attack_debug: return
	
	var data = {
		"combo_step": combo_step,
		"last_attack_time": last_attack_time,
		"time": Time.get_ticks_msec() / 1000.0
	}
	if frame >= 0:
		data["frame"] = frame
	
	debug_log("攻擊系統", function_name + " 執行", data)

## 連段步驟更新除錯
static func log_combo_step_update(old_step: int, new_step: int, reason: String) -> void:
	if not enabled or not attack_debug: return
	
	debug_log("連段系統", "combo_step 更新: " + str(old_step) + " → " + str(new_step) + " (" + reason + ")")

## 動畫播放除錯
static func log_animation_play(step: int, anim_name: String) -> void:
	if not enabled or not attack_debug: return
	
	debug_log("動畫系統", "播放動畫: 步驟 " + str(step) + " → " + anim_name)

## 輸入請求除錯
static func log_input_request(request_type: String, is_requested: bool, can_combo: bool = false) -> void:
	if not enabled or not input_debug: return
	
	var can_combo_str = " (can_combo: " + str(can_combo) + ")" if can_combo else ""
	debug_log("輸入系統", request_type + " 請求: " + ("是" if is_requested else "否") + can_combo_str)

# ==========================================
# 🎮 狀態機專用除錯
# ==========================================

## 狀態轉換除錯
static func log_state_transition(from_state: String, to_state: String, reason: String = "") -> void:
	if not enabled or not state_machine_debug: return
	
	var message = "狀態轉換: " + from_state + " → " + to_state
	if reason != "":
		message += " (" + reason + ")"
	debug_log("狀態機", message)

## 狀態進入除錯
static func log_state_enter(state_name: String, flags: Dictionary = {}) -> void:
	if not enabled or not state_machine_debug: return
	
	var message = "進入狀態: " + state_name
	if not flags.is_empty():
		message += " | 標誌: " + str(flags)
	debug_log("狀態機", message)

# ==========================================
# ⚙️ 配置方法
# ==========================================

## 啟用所有除錯輸出
static func enable_all() -> void:
	enabled = true
	attack_debug = true
	state_machine_debug = true
	input_debug = true
	print("✅ 啟用所有除錯輸出")

## 禁用所有除錯輸出
static func disable_all() -> void:
	enabled = false
	print("🔇 禁用所有除錯輸出")

## 僅啟用攻擊系統除錯
static func enable_attack_debug_only() -> void:
	enabled = true
	attack_debug = true
	state_machine_debug = false
	input_debug = false
	print("🎯 僅啟用攻擊系統除錯")

## 僅啟用狀態機除錯
static func enable_state_machine_debug_only() -> void:
	enabled = true
	attack_debug = false
	state_machine_debug = true
	input_debug = false
	print("🔄 僅啟用狀態機除錯")
