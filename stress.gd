extends Node3D
# Reproduces the hang of godotengine/godot#125309.
#
# Four threads create materials and ask for their RIDs. With the RenderingDevice renderers Godot creates the material
# on the calling thread and adds it to the material update list, under the list's mutex.
# Each frame the main thread creates a batch of materials, sets a parameter on each and drops them in the same frame,
# so the render thread frees materials that are still in that list.
#
# User arguments, after "--":
#   --rate=<n>  Each thread and the main thread create n materials a second. Without it they create up to 300 a frame,
#               and a run that does not hang fills the render command queue past 4 GiB in about 18 s.
#   --control   The threads create no material.
#   --hold      Every material is kept until two process frames have passed since its last change, so its free
#               reaches the render thread after a draw that followed that change.

const SECONDS := 120.0
const WARM_SECONDS := 5.0
const PER_FRAME := 300
const PER_THREAD_FRAME := 300
const THREADS := 4

var _threads: Array[Thread] = []
var _stop := false
var _threads_make := true
var _made: PackedInt64Array
var _frames := 0
var _started := 0
var _beat_at := 0
var _beat_frames := 0
var _busy_usec := 0
var _churning := false
var _hold := false
var _rate := 0
var _main_budget := 0.0
# The materials --hold keeps, each as [frame of its last change, material].
var _held: Array = []
var _held_mutex := Mutex.new()


func _ready() -> void:
	_threads_make = not OS.get_cmdline_user_args().has("--control")
	_hold = OS.get_cmdline_user_args().has("--hold")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rate="):
			_rate = int(arg.trim_prefix("--rate="))
	_made.resize(THREADS)
	_started = Time.get_ticks_msec()
	_beat_at = _started
	var first := StandardMaterial3D.new()
	first.albedo_color = Color.RED
	($Box as MeshInstance3D).material_override = first
	print("stress warm threads_make=%s hold=%s rate=%d thread_model=%s" % [_threads_make, _hold, _rate,
			ProjectSettings.get_setting("rendering/driver/threads/thread_model")])


func _start() -> void:
	_churning = true
	for i in THREADS:
		var thread := Thread.new()
		thread.start(_loop.bind(i))
		_threads.append(thread)
	print("stress start t=%.1f" % ((Time.get_ticks_msec() - _started) / 1000.0))


func _loop(i: int) -> void:
	var x := 0.0
	var frame := -1
	var this_frame := 0
	var next_usec := Time.get_ticks_usec()
	while not _stop:
		if _rate > 0:
			var now := Time.get_ticks_usec()
			if now < next_usec:
				OS.delay_usec(mini(next_usec - now, 1000))
				continue
			next_usec = maxi(next_usec + 1000000 / _rate, now - 100000)
		else:
			if _frames != frame:
				frame = _frames
				this_frame = 0
			if this_frame >= PER_THREAD_FRAME:
				OS.delay_usec(100)
				continue
			this_frame += 1
		if _threads_make:
			var material := StandardMaterial3D.new()
			material.get_rid()
			material.albedo_color = Color(randf(), 0.5, 0.5)
			if _hold:
				_held_mutex.lock()
				_held.append([_frames, material])
				_held_mutex.unlock()
		else:
			for k in 200:
				x += sin(k)
		_made[i] += 1


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	if _churning:
		var made: Array[StandardMaterial3D] = []
		var count := PER_FRAME
		if _rate > 0:
			_main_budget += _rate * delta
			count = int(_main_budget)
			_main_budget -= count
		for k in count:
			var material := StandardMaterial3D.new()
			material.get_rid()
			material.albedo_color = Color(randf(), randf(), randf())
			made.append(material)
		if _hold:
			_held_mutex.lock()
			for material in made:
				_held.append([_frames, material])
			_held_mutex.unlock()
		made.clear()
	if _hold:
		_held_mutex.lock()
		var kept := []
		for entry: Array in _held:
			if _frames + 1 < entry[0] + 2:
				kept.append(entry)
		_held = kept
		_held_mutex.unlock()
	_busy_usec += Time.get_ticks_usec() - t0
	_frames += 1
	var now := Time.get_ticks_msec()
	if now - _beat_at >= 1000:
		var count := _frames - _beat_frames
		print("beat t=%.1f frames=%d fps=%.1f ms=%.2f main_make_ms=%.2f thread_made=%s" % [(now - _started) / 1000.0,
				_frames, count * 1000.0 / (now - _beat_at), (now - _beat_at) / float(count),
				_busy_usec / 1000.0 / count, _made])
		_beat_at = now
		_beat_frames = _frames
		_busy_usec = 0
	if not _churning and now - _started > WARM_SECONDS * 1000.0:
		_start()
	if now - _started > (WARM_SECONDS + SECONDS) * 1000.0:
		_stop = true
		for thread in _threads:
			thread.wait_to_finish()
		print("stress end frames=%d" % _frames)
		get_tree().quit()
