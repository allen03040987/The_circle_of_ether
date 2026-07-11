class_name Interactable
extends Area2D 

# ==========================================
# ⚙️ 初始化 (Initialization)
# ==========================================
func _ready() -> void:
	# 🌟 代碼強制綁定訊號，防止編輯器漏接線導致遊戲崩潰
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

# ==========================================
# 🎮 互動介面 (Interface)
# ==========================================
## 供子類別 (如存檔點 SaveStone、NPC) 覆寫的具體互動行為
func interact() -> void:
	pass

# ==========================================
# 📡 訊號接收 (Signal Handlers)
# ==========================================
var interacting_player: Player = null ## 存目前互動範圍內的玩家本體，給 SaveStone 這類需要存取玩家專屬資源(如血包)的子類別用

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		interacting_player = body
		body.register_interactable(self)

func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		if interacting_player == body: interacting_player = null
		body.unregister_interactable(self)
