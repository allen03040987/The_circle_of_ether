class_name StateMachine
extends Node
## 狀態機總監 (State Machine Director)
## 負責管理所有子狀態，並確保同一時間只有「一個」狀態在運行。

# 在編輯器面板顯示當前狀態，方便除錯抓蟲
@export var current_state_name: String = ""

# ==========================================
# 🎛️ 核心變數 (Properties)
# ==========================================
# 遊戲開始時的預設狀態
@export var initial_state: State

var current_state: State
var states: Dictionary = {} # 狀態字典，用字串快速尋找狀態節點
var state_time: float = 0.0 

# 🔒 防遞迴鎖 (Transition Lock)
# 這是整個狀態機的保險絲。防止在 enter/exit 的過程中又觸發另一次切換，
# 造成「無限迴圈 (Stack Overflow)」導致遊戲直接崩潰。
var _is_transitioning: bool = false

# ==========================================
# ⚙️ 初始化 (Initialization)
# ==========================================
func _ready() -> void:
	# 等待擁有者 (Player) 準備好，確保取得到 player 實體
	await owner.ready
	
	# 遍歷底下所有的子節點，把它們註冊進字典
	for child in get_children():
		if child is State:
			states[child.name.to_lower()] = child
			# 🌟 依賴注入：把 Player 和 總監自己 的參考，發給每一個子狀態
			child.player = owner as Player
			child.state_machine = self
	
	# 啟動初始狀態
	if initial_state:
		initial_state.enter()
		current_state = initial_state
		current_state_name = current_state.name

# ==========================================
# 🔄 生命週期循環 (Update Loop)
# ==========================================
# 總監自己不寫邏輯，他只負責把時間 (delta) 傳遞給「目前正在值班的狀態」
func _process(delta: float) -> void:
	if current_state and not _is_transitioning:
		current_state.update(delta)

func _physics_process(delta: float) -> void:
	if current_state and not _is_transitioning:
		state_time += delta 
		current_state.physics_update(delta)

# ==========================================
# 🚪 狀態切換引擎 (Transition Engine)
# ==========================================
# 任何狀態想要切換時，都要呼叫這個函數
func transition_to(target_state_name: String) -> void:
	# 🛑 1. 檢查保險絲：如果正在換檔，拒絕新的換檔請求
	if _is_transitioning:
		return
		
	# 🔍 2. 在字典尋找目標狀態
	var key = target_state_name.to_lower()
	if not states.has(key):
		printerr("❌ 狀態機找不到這個狀態: ", target_state_name)
		return
		
	var next_state = states[key]
	
	# 🛑 3. 防呆檢查：如果目標狀態就是現在的狀態，不做事 (防止原地反覆橫跳)
	if current_state == next_state:
		return
		
	# 🔒 4. 換檔開始：上鎖！
	_is_transitioning = true 
	
	# 🚪 5. 讓舊狀態執行下班流程
	if current_state:
		current_state.exit()
		
	# 🔄 6. 更換值班人員
	current_state = next_state
	state_time = 0.0 
	current_state_name = current_state.name
	
	# 🎬 7. 讓新狀態執行上班流程
	current_state.enter()
	
	# 🔓 8. 換檔結束：解鎖！允許接受下一次切換請求
	_is_transitioning = false
