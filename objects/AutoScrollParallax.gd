class_name AutoScrollParallax
extends Node2D
## 讓任意 2D 節點自動朝一個方向緩慢位移（天空雲層飄動、水流、遠山漂移等
## 背景常見效果）。掛在 ParallaxLayer 節點上時，走 motion_offset（跟相機
## 捲動疊加、不衝突，配合節點原有的 motion_mirroring 循環，Godot 會無限
## 循環接續、不會露出貼圖邊界或跳格）；掛在其他一般 2D 節點（例如 Sprite2D）
## 上時，沒有 motion_mirroring 那套循環機制，直接位移 position，單純往一個
## 方向持續飄。
##
## extends Node2D 而不是 extends ParallaxLayer——這樣才能掛在任何 2D 節點上
## （包含 Sprite2D），不會因為節點類型跟腳本宣告的基底類型不符被 Godot 拒絕
## 附加（ParallaxLayer 版本試過直接掛 Sprite2D 會報錯，因為 Sprite2D 不是
## ParallaxLayer 的子類）。
##
## 純視覺效果，用 _process()（每個畫面只跑一次）而非 _physics_process()——
## VsMods 對戰模式 rollback 重新模擬同一個畫面幀可能連跑好幾次
## _physics_process()，這裡若用物理 delta 累加，畫面會跟著同一幀內的
## 重模擬次數多跑好幾次，肉眼看起來像跳動；純視覺效果一律走 _process()
## 真實時間，不受 rollback 影響（跟 BattleHud 能量條滿時的動態彩色效果
## 同一個原則）。
##
## 全專案通用、不屬於任何模式——直接把這支腳本掛在任何一個 2D 節點上（不用
## 改場景結構、不用重新指定子節點），在 Inspector 設定 scroll_speed 即可生效。

@export var scroll_speed: Vector2 = Vector2(10.0, 0.0)   ## 每秒位移量（px/s），正負決定方向

func _process(delta: float) -> void:
	var offset := scroll_speed * delta
	# 用 get()/set() 動態判斷有沒有 motion_offset 屬性（duck typing），不用
	# `self is ParallaxLayer` 靜態型別檢查——腳本宣告 extends Node2D，GDScript
	# 靜態分析會認定 self 固定是 AutoScrollParallax 這個類別，跟 ParallaxLayer
	# 互為平輩（兩者都繼承 Node2D，彼此不是對方的子型別），編譯期就會直接
	# 判定這個型別檢查恆假而報錯，即使實際掛載的節點真的是 ParallaxLayer。
	var mo = get(&"motion_offset")
	if mo != null:
		set(&"motion_offset", mo + offset)
	else:
		position += offset
