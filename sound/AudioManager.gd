extends Node
## 全域音訊管理器 (Autoload)
## 負責播放背景音樂 (BGM) 以及不受場景銷毀影響的全域音效 (SFX)

# ==========================================
# 💥 受擊音效庫 (Hit SFX Bank)
# ==========================================
# 🌟 在這裡預載所有「可共用」的受擊音效 (強烈建議這裡放 AudioStreamRandomizer 資源)
var hit_sfx_bank: Dictionary = {
	"hit": preload("res://sound/SFX/hit/hit.wav"), 
	"hit_2": preload("res://sound/SFX/hit/hit_2.wav"), 
	"hit_3": preload("res://sound/SFX/hit/hit_3.wav"), 
	"hit_4": preload("res://sound/SFX/hit/hit_4.wav"),
	"hit_5": preload("res://sound/SFX/hit/hit_5.wav"),
	"hit_6": preload("res://sound/SFX/hit/hit_6.wav"),
	"hit_7": preload("res://sound/SFX/hit/hit_7.wav"),
}

# ==========================================
# 🗡️ 揮空與動作音效庫 (Action SFX Bank)
# ==========================================
# 🌟 未來所有的空揮聲、拔刀聲、腳步聲，通通集中在這裡註冊！
var action_sfx_bank: Dictionary = {
	"wave": preload("res://sound/SFX/attack/wave.wav"),
	"wave_2": preload("res://sound/SFX/attack/wave_2.wav"),
	"cut": preload("res://sound/SFX/attack/cut.wav"),
	"cut_2": preload("res://sound/SFX/attack/cut_2.wav"),
	"cut_3": preload("res://sound/SFX/attack/cut_3.wav"), 
	"cut_4": preload("res://sound/SFX/attack/cut_4.wav"), 
	"cut_5": preload("res://sound/SFX/attack/cut_5.wav"), 
	
	"Earthquake": preload("res://sound/SFX/attack/Earthquake.wav"),
	"Earthquake_2": preload("res://sound/SFX/attack/Earthquake_2.wav"),
	"wind": preload("res://sound/SFX/attack/wind.wav"),
	"hit": preload("res://sound/SFX/hit/hit.wav"), 
	"hit_2": preload("res://sound/SFX/hit/hit_2.wav"), 
	"hit_3": preload("res://sound/SFX/hit/hit_3.wav"), 
	"hit_4": preload("res://sound/SFX/hit/hit_4.wav"),
	"hit_5": preload("res://sound/SFX/hit/hit_5.wav"),
	"hit_6": preload("res://sound/SFX/hit/hit_6.wav"),
	"hit_7": preload("res://sound/SFX/hit/hit_7.wav"),
	
	"ult": preload("res://sound/SFX/attack/uit.wav") ,
	
	"laser": preload("res://sound/SFX/attack/laser.wav") ,
	"beam": preload("res://sound/SFX/attack/beam.wav") ,
	"beam_2": preload("res://sound/SFX/attack/beam_2.wav") ,
	"lightsaber": preload("res://sound/SFX/attack/lightsaber.wav") ,
	"Energy Beam": preload("res://sound/SFX/attack/Energy Beam.wav") ,
	"Explosive bass": preload(	"res://sound/SFX/attack/Explosive bass.wav") ,

	"Sheath": preload("res://sound/SFX/attack/Sheath.wav"), 

	# ==========================================
	# 場景音效庫 (Action SFX Bank)
	# ==========================================
	"ding": preload("res://sound/Scene sound/ding.wav"), 
	"elevator": preload("res://sound/Scene sound/elevator.wav"), 
	"Get_notification": preload("res://sound/Scene sound/Get notification sound.wav"), 
	"christmas_bells": preload("res://sound/SFX/christmas bells.wav"), 
}


# 負責接收各個角色傳來的「點歌標籤」
func play_action_sfx(sfx_key: String, volume_db: float = -8.0) -> void:
	if sfx_key == "" or not action_sfx_bank.has(sfx_key):
		printerr("⚠️ [AudioManager] 找不到動作音效標籤: ", sfx_key)
		return
		
	var stream = action_sfx_bank[sfx_key]
	play_sfx(stream, volume_db)
	
# 武器或 Hitbox 只要傳遞「字串標籤」過來點歌即可
func play_hit_sfx(sfx_key: String, volume_db: float = -2.0) -> void:
	if sfx_key == "" or not hit_sfx_bank.has(sfx_key):
		return # 如果沒這個標籤，就不播
		
	var stream = hit_sfx_bank[sfx_key]
	play_sfx(stream, volume_db)
	
	
# 🌟 智能音量防爆機制：記錄同一幀內，各個音效被呼叫的次數
var _frame_sfx_pool: Dictionary = {}
# ==========================================
# 🎵 背景音樂 (BGM) 控制
# ==========================================
var _bgm_player: AudioStreamPlayer
var _bgm_base_volume: float = 0.0 # 記住我們設定的預設音量

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "BGM"
	add_child(_bgm_player)

# 🌟 新增：每一幀結束時，把「同幀去重池」洗乾淨，準備迎接下一幀的音效
func _process(_delta: float) -> void:
	_frame_sfx_pool.clear()

# 🌟 新增 volume_db 參數：預設 0.0 (原音量)，負數變小聲 (例如 -10.0 是小聲，-20.0 是非常小聲)
# 在 AudioManager.gd 裡：
func play_bgm(stream: AudioStream, volume_db: float = 0.0) -> void:
	if not stream: return
	
	_bgm_base_volume = volume_db
	
	# 如果同一首正在播，只需把音量平滑地拉回正常
	if _bgm_player.stream == stream and _bgm_player.playing:
		# 🌟 修復：只有當音量真的不同時，才需要調整，節省效能
		if _bgm_player.volume_db != _bgm_base_volume:
			var tween = create_tween()
			# 🌟 核心防護：讓音量漸變無視 tree.paused = true 的凍結效果！
			tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS) 
			tween.tween_property(_bgm_player, "volume_db", _bgm_base_volume, 0.5)
		return 
		
	_bgm_player.stream = stream
	_bgm_player.volume_db = _bgm_base_volume
	_bgm_player.play()

func stop_bgm(fade_out_duration: float = 1.0) -> void:
	if not is_instance_valid(_bgm_player) or not _bgm_player.playing:
		return
		
	if fade_out_duration > 0.0:
		var tween = create_tween()
		# 賦予漸出動畫「抗暫停」特權！
		# 確保在轉場 (tree.paused = true) 或選單暫停時，音樂依然能平滑降落！
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		
		# 讓音量在指定時間內平滑降到 -60 dB (人類聽不見的音量)
		tween.tween_property(_bgm_player, "volume_db", -60.0, fade_out_duration)
		# 漸出完畢後真正停止播放
		tween.tween_callback(_bgm_player.stop)
	else:
		_bgm_player.stop()
# ==========================================
# 💥 全域音效 (Global SFX) 控制 (具備防爆音疊加機制)
# ==========================================
func play_sfx(stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if not stream: return
	
	# 🌟 智能防爆音系統：偵測同幀呼叫次數
	var stream_id = stream.resource_path # 取得該音效的路徑作為唯一識別碼
	var call_count = _frame_sfx_pool.get(stream_id, 0)
	
	# 如果這一幀已經播過 2 次相同的音效了，第 3 次直接丟棄，防止聲音過度飽和！
	if call_count >= 2:
		return 
		
	# 如果是第 2 次呼叫，把音量大幅降低 (-6 dB 大約是音量減半)
	var final_volume = volume_db
	if call_count == 1:
		final_volume -= 6.0 
		
	# 記錄本次呼叫
	_frame_sfx_pool[stream_id] = call_count + 1
	
	# ==========================================
	
	# 動態生成免洗播放器
	var sfx_player = AudioStreamPlayer.new()
	sfx_player.stream = stream
	sfx_player.bus = "SFX" 
	
	# 🌟 套用經過智能降噪處理的最終音量
	sfx_player.volume_db = final_volume
	
	# 動態音調微調
	sfx_player.pitch_scale = pitch_scale + randf_range(-0.06, 0.06)
	
	add_child(sfx_player)
	sfx_player.play()
	
	# 播完自我銷毀
	sfx_player.finished.connect(func(): sfx_player.queue_free())
