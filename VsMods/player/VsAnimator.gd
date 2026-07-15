## VsAnimator — 用 code 驅動 Sprite2D，取代複製 AnimationPlayer 資料
class_name VsAnimator
extends Node

@onready var sprite: Sprite2D = $"../Graphics/Sprite2D"

# ── 動畫設定表 ────────────────────────────────────────────────────────────────
# { 名稱: { tex, hf, vf, frames(幀數), spf(秒/幀), pos, region, loop } }
const ANIMS: Dictionary = {
	"idle": {
		"tex": preload("res://player/state/IDLE.png"),
		"hf": 3, "vf": 3, "frames": 6, "spf": 0.10,
		"pos": Vector2(0, -31), "region": Rect2(0, 0, 192, 192), "loop": true
	},
	"running": {
		"tex": preload("res://player/state/run.png"),
		"hf": 4, "vf": 3, "frames": 10, "spf": 0.07,
		"pos": Vector2(2, -27), "region": Rect2(0, 0, 256, 192), "loop": true
	},
	"jump": {
		"tex": preload("res://player/state/jump.png"),
		"hf": 2, "vf": 2, "frames": 3, "spf": 0.20,
		"pos": Vector2(0, -27), "region": Rect2(0, 0, 128, 128), "loop": true
	},
	"fall": {
		"tex": preload("res://player/state/fall.png"),
		"hf": 2, "vf": 2, "frames": 3, "spf": 0.10,
		"pos": Vector2(1, -23), "region": Rect2(0, 0, 128, 128), "loop": true
	},
	"sliding": {
		"tex": preload("res://player/state/sliding.png"),
		"hf": 2, "vf": 2, "frames": 3, "spf": 0.07,
		"pos": Vector2(0, -24), "region": Rect2(0, 0, 128, 128), "loop": false
	},
}

# ── 狀態 ─────────────────────────────────────────────────────────────────────
var _current: String = ""
var _frame:   int    = 0
var _timer:   float  = 0.0
var _finished: bool  = false  # 單次動畫播完後為 true

signal animation_finished(anim_name: String)

# ── 公開 API ──────────────────────────────────────────────────────────────────
func play(anim_name: String) -> void:
	if _current == anim_name:
		return
	if not ANIMS.has(anim_name):
		push_warning("VsAnimator: 找不到動畫 '%s'" % anim_name)
		return
	_current  = anim_name
	_frame    = 0
	_timer    = 0.0
	_finished = false
	_apply_frame()

## 不重置幀數（例如停在 jump 最後一幀，不跳回第0幀）
func play_keep_frame(anim_name: String) -> void:
	if not ANIMS.has(anim_name):
		return
	if _current != anim_name:
		_current = anim_name
		_apply_frame()

func flip(facing_dir: int) -> void:
	sprite.flip_h = facing_dir < 0

func is_finished() -> bool:
	return _finished

# ── 每幀推進 ─────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _current == "" or _finished:
		return
	var cfg: Dictionary = ANIMS[_current]
	_timer += delta
	if _timer >= cfg["spf"]:
		_timer -= cfg["spf"]
		_frame += 1
		if _frame >= cfg["frames"]:
			if cfg["loop"]:
				_frame = 0
			else:
				_frame = cfg["frames"] - 1
				if not _finished:
					_finished = true
					animation_finished.emit(_current)
		_apply_frame()

# ── 內部 ─────────────────────────────────────────────────────────────────────
func _apply_frame() -> void:
	if _current == "":
		return
	var cfg: Dictionary = ANIMS[_current]
	sprite.texture       = cfg["tex"]
	sprite.hframes       = cfg["hf"]
	sprite.vframes       = cfg["vf"]
	sprite.frame         = _frame
	sprite.position      = cfg["pos"]
	sprite.region_enabled = true
	sprite.region_rect   = cfg["region"]
