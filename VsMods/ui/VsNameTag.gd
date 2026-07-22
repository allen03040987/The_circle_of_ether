class_name VsNameTag
extends Control
## 玩家頭頂身份標籤（文字 + 三角指標）。文字/圖標的相對位置、大小、字型、顏色
## 全部是子節點的一般 Control 屬性，直接在編輯器裡調整 VsNameTag.tscn 即可，
## 不用改這支腳本。這裡只負責兩件事：(1) 上下浮動動畫，(2) 讓外部（BattleHud）
## 每幀餵一個「螢幕座標」進來當浮動的基準點。

@export var float_speed: float = 2.5       ## 上下浮動角速度（rad/s）
@export var float_amplitude: float = 2.0   ## 上下浮動振幅（螢幕像素）
@export var phase: float = 0.0             ## 浮動相位——P1/P2 給不同值，兩個標籤才不會同步上下

@onready var _label: Label = $Label

var _time: float = 0.0
var _base_position: Vector2 = Vector2.ZERO

func _process(delta: float) -> void:
	_time += delta
	position = _base_position + Vector2(0.0, sin(_time * float_speed + phase) * float_amplitude)

func set_text(text: String) -> void:
	_label.text = text

## anchor_screen_pos：跟隨的玩家已經換算成螢幕像素座標的錨點（BattleHud 用
## get_viewport().get_canvas_transform() * vs.vfx_anchor_position() 算出）。
## 這個節點本身在 CanvasLayer 底下，不受 VsCamera 的 zoom 影響，只有位置
## 每幀跟著錨點移動，文字/圖標的螢幕尺寸永遠不變。
func set_anchor_screen_position(anchor_screen_pos: Vector2) -> void:
	_base_position = anchor_screen_pos
