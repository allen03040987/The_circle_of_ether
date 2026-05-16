class_name MechlGuardState
extends VsPlayerGuardState

# 💡 繼承的威力：enter 和 process_physics 全部交給老爸去算！
# 我們只需要「擴充」離開狀態時的行為就好！

func exit() -> void:
	# 🌟 關鍵碰瓷點：離開防禦狀態的瞬間，呼叫大腦開始倒數 0.3 秒！
	# 使用 has_method 安全檢查，確保老爸不會報錯
	if player.has_method("start_post_guard_stack"):
		player.start_post_guard_stack()
