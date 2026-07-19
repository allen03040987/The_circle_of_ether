extends Node
## 全域音訊管理器 (Autoload)

# ==========================================
# 💥 受擊音效庫 (Hit SFX Bank)
# ==========================================
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
# 🌟 hit/hit_2~hit_7 這幾支已經在上面的 hit_sfx_bank 裡了，這裡不再重複 preload 同一個檔案兩次——
# play_action_sfx() 找不到 key 時會自動 fallback 去查 hit_sfx_bank，所以動畫軌道呼叫 trigger_swing_sfx("hit_4")
# 這種寫法完全不用改，一樣能正常播放。hit_8/hit_9 是動作音效庫獨有（hit_sfx_bank 沒有），所以留在這裡。
var action_sfx_bank: Dictionary = {
	# --- 揮砍/波動 (Swing & Wave) ---
	"wave": preload("res://sound/SFX/attack/wave.wav"),
	"wave_2": preload("res://sound/SFX/attack/wave_2.wav"),
	"wave_3": preload("res://sound/SFX/attack/wave_3.wav"),
	"wave_4": preload("res://sound/SFX/attack/wave_4.wav"),
	"cut": preload("res://sound/SFX/attack/cut.wav"),
	"cut_2": preload("res://sound/SFX/attack/cut_2.wav"),
	"cut_3": preload("res://sound/SFX/attack/cut_3.wav"),
	"cut_4": preload("res://sound/SFX/attack/cut_4.wav"),
	"cut_5": preload("res://sound/SFX/attack/cut_5.wav"),
	"wind": preload("res://sound/SFX/attack/wind.wav"),
	"wind_2": preload("res://sound/SFX/attack/wind_2.wav"),
	"wind_3": preload("res://sound/SFX/attack/wind_3.wav"),

	# --- 重擊/地震 (Heavy Impact) ---
	"Earthquake": preload("res://sound/SFX/attack/Earthquake.wav"),
	"Earthquake_2": preload("res://sound/SFX/attack/Earthquake_2.wav"),
	"hit_8": preload("res://sound/SFX/hit/hit_8.wav"),
	"hit_9": preload("res://sound/SFX/hit/hit_9.wav"),

	# --- 大招/能量系 (Ultimate & Energy) ---
	"ult": preload("res://sound/SFX/attack/ult.wav"),
	"laser": preload("res://sound/SFX/attack/laser.wav"),
	"beam": preload("res://sound/SFX/attack/beam.wav"),
	"beam_2": preload("res://sound/SFX/attack/beam_2.wav"),
	"lightsaber": preload("res://sound/SFX/attack/lightsaber.wav"),
	"Energy Beam": preload("res://sound/SFX/attack/Energy Beam.wav"),
	"Explosive bass": preload("res://sound/SFX/attack/Explosive bass.wav"),
	"accumulating_power": preload("res://sound/SFX/accumulating power.wav"),

	# --- 格擋/彈反回饋 (Guard & Counter Feedback) ---
	"Guard": preload("res://sound/SFX/Guard.wav"),
	"Counterattack_successful": preload("res://sound/SFX/Counterattack successful.wav"),
	"Successfully_dodged": preload("res://sound/SFX/Successfully_dodged.wav"),
	# --- 武器收招/位移 (Sheath & Movement) ---
	"Sheath": preload("res://sound/SFX/attack/Sheath.wav"),
	"sprint": preload("res://sound/SFX/sprint.wav"),
	"move_1": preload("res://sound/SFX/move_1.wav"),
	"move_2": preload("res://sound/SFX/move_2.wav"),

	# --- UI/場景提示音 (UI & Scene Cues，非戰鬥用) ---
	"Prompt_tone": preload("res://sound/SFX/Prompt tone.wav"),
	"ding": preload("res://sound/Scene sound/ding.wav"),
	"elevator": preload("res://sound/Scene sound/elevator.wav"),
	"Get_notification": preload("res://sound/Scene sound/Get notification sound.wav"),
	"christmas_bells": preload("res://sound/SFX/christmas bells.wav"),
}
 
# ==========================================
# 🧠 核心控制與滑動時間防爆池
# ==========================================
var _sfx_history_pool: Dictionary = {}
const SFX_TIME_WINDOW_MS: int = 50 

var _bgm_player: AudioStreamPlayer
var _bgm_base_volume: float = 0.0 

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "BGM"
	add_child(_bgm_player)

func _process(_delta: float) -> void:
	var current_time = Time.get_ticks_msec()
	var dead_keys = []
	
	for stream_id in _sfx_history_pool.keys():
		var history: Array = _sfx_history_pool[stream_id]
		while history.size() > 0 and current_time - history[0] > SFX_TIME_WINDOW_MS:
			history.remove_at(0)
		if history.is_empty():
			dead_keys.append(stream_id)
			
	for key in dead_keys:
		_sfx_history_pool.erase(key)

# ==========================================
# 📡 路由分流調度
# ==========================================
func play_action_sfx(sfx_key: String, volume_db: float = -8.0) -> void:
	if sfx_key == "": return
	if action_sfx_bank.has(sfx_key):
		play_sfx(action_sfx_bank[sfx_key], volume_db)
	elif hit_sfx_bank.has(sfx_key):
		play_sfx(hit_sfx_bank[sfx_key], volume_db)
	else:
		printerr("⚠️ [AudioManager] 找不到動作音效標籤: ", sfx_key)
	
func play_hit_sfx(sfx_key: String, volume_db: float = -2.0) -> void:
	if sfx_key == "" or not hit_sfx_bank.has(sfx_key): return
	play_sfx(hit_sfx_bank[sfx_key], volume_db)
	
# ==========================================
# 🎵 背景音樂 (BGM) 控制
# ==========================================
func play_bgm(stream: AudioStream, volume_db: float = 0.0) -> void:
	if not stream: return
	_bgm_base_volume = volume_db
	
	if _bgm_player.stream == stream and _bgm_player.playing:
		if _bgm_player.volume_db != _bgm_base_volume:
			var tween = create_tween()
			tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS) 
			tween.tween_property(_bgm_player, "volume_db", _bgm_base_volume, 0.5)
		return 
		
	_bgm_player.stream = stream
	_bgm_player.volume_db = _bgm_base_volume
	_bgm_player.play()

func stop_bgm(fade_out_duration: float = 1.0) -> void:
	if not is_instance_valid(_bgm_player) or not _bgm_player.playing: return
	if fade_out_duration > 0.0:
		var tween = create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_property(_bgm_player, "volume_db", -60.0, fade_out_duration)
		tween.tween_callback(_bgm_player.stop)
	else:
		_bgm_player.stop()

# ==========================================
# 💥 全域音效 (Global SFX) 控制 (滑動時間窗口防爆)
# ==========================================
func play_sfx(stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if not stream: return
	
	var stream_id = stream.resource_path 
	var current_time = Time.get_ticks_msec()
	
	if not _sfx_history_pool.has(stream_id):
		_sfx_history_pool[stream_id] = []
		
	var history: Array = _sfx_history_pool[stream_id]
	
	while history.size() > 0 and current_time - history[0] > SFX_TIME_WINDOW_MS:
		history.remove_at(0)
		
	var call_count = history.size()
	
	if call_count >= 2:
		return 
		
	var final_volume = volume_db
	if call_count == 1:
		final_volume -= 6.0 
		
	history.append(current_time)
	
	var sfx_player = AudioStreamPlayer.new()
	sfx_player.stream = stream
	sfx_player.bus = "SFX" 
	sfx_player.volume_db = final_volume
	sfx_player.pitch_scale = pitch_scale + randf_range(-0.06, 0.06)
	
	add_child(sfx_player)
	sfx_player.play()
	sfx_player.finished.connect(func(): sfx_player.queue_free())
