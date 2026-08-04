extends Node
## Push-to-talk microphone capture. GDD Part 3 §1 Tier IV, Part 10 §4.
##
## Hold Space to speak; release to submit. Azure wants <=6s of 16kHz mono WAV,
## so capture is capped rather than trimmed after the fact.
##
## Quiet mode is a first-class path, not an error state: if there is no mic, no
## permission, or the player has chosen silence, every prompt still resolves.
## The game must be completable mute (Part 3 §1).

signal recording_started()
signal recording_stopped(duration: float)

const MAX_SECONDS := 6.0
const SAMPLE_RATE := 16000

var is_recording: bool = false
var quiet_mode: bool = false

var _effect: AudioEffectCapture = null
var _bus_index: int = -1
var _elapsed: float = 0.0
var _frames: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	quiet_mode = bool(GameState.quiet_mode)
	_bus_index = AudioServer.get_bus_index("Record")
	if _bus_index == -1:
		# No record bus configured — quiet mode is the graceful answer, not a crash.
		print("[mic] no Record bus; quiet mode available")
		return
	for i in AudioServer.get_bus_effect_count(_bus_index):
		var effect := AudioServer.get_bus_effect(_bus_index, i)
		if effect is AudioEffectCapture:
			_effect = effect
			break


## Can we actually record right now?
func is_available() -> bool:
	return _effect != null and not quiet_mode


func set_quiet_mode(enabled: bool) -> void:
	quiet_mode = enabled
	GameState.quiet_mode = enabled
	GameState.save_state()
	print("[mic] quiet mode %s" % ("on" if enabled else "off"))


func start_recording() -> void:
	if is_recording or not is_available():
		return
	is_recording = true
	_elapsed = 0.0
	_frames = PackedVector2Array()
	if _effect != null:
		_effect.clear_buffer()
	recording_started.emit()


func stop_recording() -> void:
	if not is_recording:
		return
	is_recording = false
	recording_stopped.emit(_elapsed)


func _process(delta: float) -> void:
	if not is_recording:
		return
	_elapsed += delta
	if _effect != null:
		var available := _effect.get_frames_available()
		if available > 0:
			_frames.append_array(_effect.get_buffer(available))
	if _elapsed >= MAX_SECONDS:
		stop_recording()


## The captured utterance as 16kHz mono PCM WAV, or empty if there is nothing.
func take_wav() -> PackedByteArray:
	if _frames.is_empty():
		return PackedByteArray()
	var pcm := _to_mono_pcm16(_frames)
	_frames = PackedVector2Array()
	return _wrap_wav(pcm)


func _to_mono_pcm16(frames: PackedVector2Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(frames.size() * 2)
	for i in frames.size():
		var mono := clampf((frames[i].x + frames[i].y) * 0.5, -1.0, 1.0)
		var value := int(mono * 32767.0)
		out.encode_s16(i * 2, value)
	return out


func _wrap_wav(pcm: PackedByteArray) -> PackedByteArray:
	var header := PackedByteArray()
	header.resize(44)
	var data_size := pcm.size()
	header.encode_u32(0, 0x46464952)             # "RIFF"
	header.encode_u32(4, 36 + data_size)
	header.encode_u32(8, 0x45564157)             # "WAVE"
	header.encode_u32(12, 0x20746D66)            # "fmt "
	header.encode_u32(16, 16)                    # PCM chunk size
	header.encode_u16(20, 1)                     # PCM
	header.encode_u16(22, 1)                     # mono
	header.encode_u32(24, SAMPLE_RATE)
	header.encode_u32(28, SAMPLE_RATE * 2)       # byte rate
	header.encode_u16(32, 2)                     # block align
	header.encode_u16(34, 16)                    # bits per sample
	header.encode_u32(36, 0x61746164)            # "data"
	header.encode_u32(40, data_size)
	return header + pcm
