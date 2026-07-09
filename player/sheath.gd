extends State

# ==========================================
# 🎬 狀態生命週期 (State Lifecycle)
# ==========================================
func enter() -> void:
	# ==========================================
	# ⚡ 第 0 影格攔截 (Frame 0 Intercept)
	# 在播收刀動畫前，先檢查有沒有預輸入的動作或方向鍵，
	# 如果有，直接轉移狀態並 return，消滅 1 幀的動畫閃爍！
	# ==========================================
	if not player.is_on_floor():
		state_machine.transition_to("Fall")
		return
	
	if player.jump_request_timer.time_left > 0:
		state_machine.transition_to("Jump")
		return
		
	if player.slide_request_timer.time_left > 0 and player.stats.energy >= 3:
		if player.slide_cooldown_timer.is_stopped():
			state_machine.transition_to("Slide")
			return

	if player.guard_request_timer.time_left > 0:
		state_machine.transition_to("Guard")
		return


	if player.is_heavy_requested or player.is_combo_requested:
		state_machine.transition_to("WeaponAttack")
		return
		
	var movement := Input.get_axis("move_left", "move_right")
	if not is_zero_approx(movement):
		state_machine.transition_to("Run")
		return

	# ==========================================
	# 確定真的要留下來收刀了，才開始處理動畫與變數
	# ==========================================
	# 動態決定收刀動畫名稱
	var anim_name: String = "sheath" # 預設底線方案
	
	if is_instance_valid(player.current_weapon):
		# 優先嘗試讀取武器合約裡的 WEAPON_ID (例如 "katana" 或 "spear")
		if "WEAPON_ID" in player.current_weapon:
			anim_name = player.current_weapon.WEAPON_ID + "/sheath"
		else:
			# 備用方案：如果忘了設 WEAPON_ID，直接抓武器節點的名稱轉小寫 (例如節點叫 Katana -> "katana/sheath")
			anim_name = player.current_weapon.name.to_lower() + "/sheath"
			
	player.play_safe_anim(anim_name)
	
	# 進入收刀時，確保玩家身上沒有殘留的攻擊緩衝
	# 避免上一招的餘溫不小心觸發下一刀
	player.is_combo_requested = false
	player.is_heavy_requested = false
	player.combo_buffer_time = 0.0
	player.heavy_buffer_time = 0.0
	
func physics_update(delta: float) -> void:
	# 1. 物理煞車：保留地面摩擦力，展現滑順停步
	player.velocity.x = move_toward(player.velocity.x, 0.0, player.FLOOR_ACCELERATION * delta)
	player.velocity.y += player.default_gravity * delta
	player.custom_move_and_slide()
	
	# ==========================================
	# ⚡ 任意動作打斷 (Any Action Cancel)
	# ==========================================
	
	# 邊緣判定：踩空立刻掉落！
	if not player.is_on_floor():
		state_machine.transition_to("Fall")
		return
	
	# 預輸入：跳躍
	if player.jump_request_timer.time_left > 0:
		state_machine.transition_to("Jump")
		return
		
	# 預輸入：閃避
	if player.slide_request_timer.time_left > 0 and player.stats.energy >= 3:
		if player.slide_cooldown_timer.is_stopped():
			state_machine.transition_to("Slide")
			return

	if player.guard_request_timer.time_left > 0:
		state_machine.transition_to("Guard")
		return


	# 預輸入：戰鬥大門 (統一聽從 Player.gd 的舉牌)
	if player.is_heavy_requested or player.is_combo_requested:
		state_machine.transition_to("WeaponAttack")
		return
		
	# 🌟 新增移動打斷：只要玩家按下左右方向鍵，立刻取消收刀，開始移動！
	var movement := Input.get_axis("move_left", "move_right")
	if not is_zero_approx(movement):
		state_machine.transition_to("Run")
		return

	# ==========================================
	# 🎬 動畫自然結束
	# ==========================================
	if not player.animation_player.is_playing():
		state_machine.transition_to("Idle")

func exit() -> void:
	# 🌟 保險機制：無論收刀是被什麼動作打斷，離開狀態時劍鞘強制現身！
	if player.scabbard:
		player.scabbard.fade_in()
