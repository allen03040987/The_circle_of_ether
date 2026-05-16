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
func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		body.register_interactable(self)

func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		body.unregister_interactable(self)
