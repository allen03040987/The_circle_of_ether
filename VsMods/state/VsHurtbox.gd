class_name VsHurtbox
extends Area2D

## 負責接收攻擊判定、計算傷害與防禦邏輯的受擊組件。
## 作為「盾牌」，當被 VsHitbox (劍) 砍中時，由 Hitbox 主動呼叫此腳本的 `take_hit` 函數。

@onready var owner_player = get_parent().get_parent()

## 接收並結算傷害的核心函數。由攻擊方的 Hitbox 呼叫。
## is_first_hit: 若為多段連擊 (絞肉機)，則只有第一下會傳入 true，後續傷害為 false。
func take_hit(hitbox_data: VsHitbox, is_first_hit: bool = true) -> void:
	# ==========================================
	# 0. 防範友軍傷害 (Friendly Fire 檢查)
	# ==========================================
	# 如果攻擊沒有老闆 (孤兒彈幕)，或是老闆跟自己一樣 (打到自己)，直接無視！
	if hitbox_data.owner_player == null or hitbox_data.owner_player == self.owner_player:
		return

	# ==========================================
	# 1. 狀態攔截 (無敵與掃地/擊飛保護判定)
	# ==========================================
	if owner_player.invincibility_timer > 0.0:
		return 
	
	var state_machine = owner_player.vs_state_machine
	var current_state = state_machine.current_state

	# 條件 A：真的已經躺在地上
	var is_actually_down = (current_state is VsPlayerDownState) or (current_state.name == "Down")
	
	# 條件 B：還在受擊硬直中 (hurt)，但身上已經被掛上了「這招打完注定會倒地」的命運標籤
	var is_falling_to_down = (current_state is VsPlayerHurtState or current_state.name == "hurt") and owner_player.received_causes_down

	# 🌟 定義「倒地保護狀態」：只要符合 A 或 B，就視為躺平。
	var is_down = is_actually_down or is_falling_to_down

	# 神級保護網：只要躺平，沒勾選 OTG (掃地) 的招式通通打不到！
	if is_down and not hitbox_data.can_hit_otg:
		return
		
	# ==========================================
	# 2. 擊退方向計算 (相對位置判定)
	# ==========================================
	var push_dir: float = 1.0
	if hitbox_data.global_position.x < self.global_position.x:
		push_dir = 1.0  # 攻擊在左邊，往右推
	else:
		push_dir = -1.0 # 攻擊在右邊，往左推
	
	# ==========================================
	# 🛡️ 3. 大師級防禦判定 (拉後防禦 + 空中防禦 + 逆向保護 + 狀態鎖)
	# ==========================================
	var is_on_floor = owner_player.is_on_floor()
	var is_crouching = Input.is_action_pressed(owner_player.down_key)
	var holding_left = Input.is_action_pressed(owner_player.left_key)
	var holding_right = Input.is_action_pressed(owner_player.right_key)
	
	var is_already_guarding = (current_state.name == "Guard")
	var is_in_hitstun = (current_state is VsPlayerHurtState or current_state.name == "hurt")
	
	# 🌟 新增：去問目前的狀態腳本，它允不允許防禦？
	# 如果腳本裡沒寫 (預設)，或者是自訂技能，就用 get_node_or_null 安全取值
	var state_allows_blocking = false
	if "can_block" in current_state:
		state_allows_blocking = current_state.can_block

	# 步驟 A：判定是否「重疊」(逆向保護距離)
	var is_overlapping = false
	if owner_player.opponent != null:
		var dist_x = abs(owner_player.global_position.x - owner_player.opponent.global_position.x)
		if dist_x < 25.0: 
			is_overlapping = true

	# 步驟 B：判定玩家是否有按著「遠離對手」的方向鍵 (拉後)
	var is_holding_back = false
	if owner_player.opponent != null:
		if owner_player.opponent.global_position.x > owner_player.global_position.x:
			is_holding_back = holding_left 
		else:
			is_holding_back = holding_right 

	# 步驟 C：綜合防禦意圖裁決 (海陸空全包)
	var can_initiate_guard = false
	
	if is_on_floor:
		if is_overlapping:
			can_initiate_guard = is_crouching 
		else:
			can_initiate_guard = is_crouching and is_holding_back 
	else:
		can_initiate_guard = is_holding_back 

	# 🌟 步驟 D：終極鐵門檻 (剝奪防禦權)
	var is_guarding = false
	if is_in_hitstun or is_down:
		is_guarding = false # 已經在挨打或躺平了，不准防禦
	elif not state_allows_blocking and not is_already_guarding:
		# 🌟 核心防線：如果現在的狀態「不允許防禦」，而且你現在「也不是在防禦中」
		# 那就算你把搖桿拉斷了，也是不准防禦！強制吃招！
		is_guarding = false 
	else:
		# 完美結合：要有防禦意圖，或者「已經在防禦狀態中」
		is_guarding = can_initiate_guard or is_already_guarding

	# 若攻擊者開啟了「全域破防」，強制沒收防禦權利
	if hitbox_data.owner_player.is_global_guard_break:
		is_guarding = false

	# ==========================================
	# 🛡️ 4. 執行防禦 (防禦成功邏輯)
	# ==========================================
	if is_guarding and not hitbox_data.guard_break:
		var facing_dir = owner_player.get_node("Graphics").scale.x
		var attacker_x = hitbox_data.owner_player.global_position.x
		var my_x = owner_player.global_position.x
		
		# 判斷攻擊是否從角色正面來
		var attack_from_front = (facing_dir == 1.0 and attacker_x > my_x) or (facing_dir == -1.0 and attacker_x < my_x)
		
		# 智慧逆向轉身：背後遇襲但成功拉後防禦時，強制轉頭面朝攻擊者
		if not attack_from_front:
			owner_player.auto_face_opponent()
			push_dir = hitbox_data.owner_player.get_node("Graphics").scale.x
			
		print("🛡️ [%s] 防禦成功！(包含拉後與空中判定)" % owner_player.name)
		
		# 防禦滑行與硬直刷新 (防禦硬直比受擊硬直短)
		owner_player.velocity.x = hitbox_data.ground_knockback.x * push_dir * 1.5 
		owner_player.received_friction = 4500.0 
		owner_player.hitstun_time_left = hitbox_data.hitstun_time * 0.6 
		
		# 如果還沒進入防禦狀態，切換過去 (播放防禦動畫)
		if not is_already_guarding:
			state_machine.change_state(state_machine.get_node("Guard"))
			
		return # ⚠️ 防禦成功，提早結束函數！不扣血、不播受擊火花
		
	# ==========================================
	# 💥 5. 物理擊退計算與異常狀態傳遞 (破防/未防禦)
	# ==========================================
	var chosen_knockback: Vector2
	# 空中受擊與倒地掃地受擊，皆套用空中擊退力 (通常會挑飛)
	if not owner_player.is_on_floor() or is_down: 
		chosen_knockback = hitbox_data.air_knockback
	else:
		chosen_knockback = hitbox_data.ground_knockback
	
	# 🩸 異常狀態(流血)上毒邏輯
	if hitbox_data.bleed_damage > 0:
		# 第一下命中，或是設定為每次命中都刷新時才上毒
		if is_first_hit or hitbox_data.bleed_every_hit:
			owner_player.start_bleed(
				hitbox_data.bleed_duration,      
				hitbox_data.bleed_damage,        
				hitbox_data.bleed_tick_interval ,
				hitbox_data.hit_sparks
			)
			
	# 倒地命運繼承 (Sticky Knockdown)：如果已經被判定會倒地，後續的連擊不會取消這個命運
	var will_go_down = hitbox_data.causes_down or is_down 
	if current_state is VsPlayerHurtState and owner_player.received_causes_down == true:
		will_go_down = true
		
	# 寫入玩家受擊記憶體，等待 HurtState 讀取
	owner_player.received_causes_down = will_go_down
	owner_player.hitstun_time_left = hitbox_data.hitstun_time
	
	# 加入隨機擊退誤差
	var random_x = randf_range(-hitbox_data.random_x_variance, hitbox_data.random_x_variance)
	owner_player.received_knockback = Vector2((chosen_knockback.x * push_dir) + random_x, chosen_knockback.y)
	owner_player.received_friction = hitbox_data.knockback_friction
	owner_player.received_hit_type = hitbox_data.hit_type 
	
	# 扣血與飄字 (完美對接減傷系統)
	var actual_dmg = owner_player.take_damage(hitbox_data.damage) # 🌟 修正了拼字，並接住真實傷害
	owner_player.current_hp = max(owner_player.current_hp, 0) 
	owner_player.spawn_damage_text(int(actual_dmg), Color.WHITE) # 🌟 飄字顯示減傷後的真實數字！
	
	# ==========================================
	# 🎁 6. 命中獎勵：冷卻縮減/刷新發放
	# ==========================================
	if hitbox_data.refresh_cd_slot != "" and hitbox_data.reduce_cd_amount > 0:
		# 為了防止多段連擊瞬間把 CD 減爆，通常只在 "第一下" 給予獎勵
		if is_first_hit:
			print("✨ 命中目標！為攻擊者減少技能冷卻：", hitbox_data.refresh_cd_slot)
			hitbox_data.owner_player.reduce_cooldown(
				hitbox_data.refresh_cd_slot, 
				hitbox_data.reduce_cd_amount
			)

	# ==========================================
	# 🎬 7. 螢幕震動與霸體裁決
	# ==========================================
	if hitbox_data.shake_intensity > 0 and hitbox_data.shake_duration > 0:
		if not hitbox_data.shake_only_first_hit or is_first_hit:
			# 呼叫玩家身上的 RPC 函數來廣播震動給所有人
			owner_player.play_camera_shake(hitbox_data.shake_intensity, hitbox_data.shake_duration)

	# 🌟 霸體與破霸的「最高法院裁決」
	var will_flinch = true # 預設：被打到就會產生硬直 (Flinch)
	
	if owner_player.has_super_armor:
		will_flinch = false # 情況 A：我有普通霸體，擋下硬直！
		
		# 使用 "in" 安全檢查，防止舊版 Hitbox 沒加此變數導致崩潰
		if "armor_break" in hitbox_data and hitbox_data.armor_break:
			will_flinch = true # 情況 B：對手這招是「破霸攻擊」，強行打碎我的霸體！
			
			if "has_absolute_armor" in owner_player and owner_player.has_absolute_armor:
				will_flinch = false # 情況 C：但我是系統級的「絕對霸體」，破甲無效！

	# 最終結算：是否強制切換至受擊硬直狀態 (HurtState)
	if will_flinch:
		if is_down: 
			# 如果已經躺平，只有強大的上挑攻擊能把他重新打起來 (OTG 浮空連段)
			if chosen_knockback.y < -10.0:
				state_machine.change_state(state_machine.hurt_state) 
			else:
				current_state.enter() # 否則只是在地上抽搐一下 (重新進入躺平狀態)
		else:
			if current_state is VsPlayerHurtState:
				current_state.enter() # 已經在挨打，重新洗牌硬直時間
			elif state_machine.hurt_state != null:
				state_machine.change_state(state_machine.hurt_state)

	# ==========================================
	# ✨ 8. 生成打擊特效 (透過網路廣播)
	# ==========================================
	var effect_paths = []
	var raw_effects = [
		hitbox_data.hit_effect_1, hitbox_data.hit_effect_2, 
		hitbox_data.hit_effect_3, hitbox_data.hit_effect_4, 
		hitbox_data.hit_effect_5
	]
	
	# 將實體的 PackedScene 轉換成路徑字串 (因為資源實體不能透過網路傳遞)
	for fx in raw_effects:
		if fx != null:
			effect_paths.append(fx.resource_path)
			
	# 呼叫老爸的 RPC 廣播，讓所有連線玩家的畫面上都噴出火花
	if effect_paths.size() > 0:
		owner_player.broadcast_hit_sparks(
			effect_paths,
			hitbox_data.spark_count,
			hitbox_data.random_spark_spread,
			hitbox_data.random_spark_angle,
			hitbox_data.spark_offset,
			hitbox_data.spark_interval
		)
