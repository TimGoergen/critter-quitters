## AudioManager.gd
## Autoload singleton — routes all game audio through named buses.
##
## Every sound slot is an exported AudioStream variable. If the variable is
## null (no file assigned yet) the corresponding play method returns immediately
## without error, so the game runs silently until real assets are available.
##
## Buses: Music, SFX, UI — all route to Master.
## Music  : single looping player; volume controlled independently.
## SFX    : pool of players for overlapping in-game sounds.
## Footsteps: separate sub-pool; per-enemy rate-limiting prevents flooding.
## UI     : small pool for interface sounds, always audible.
##
## Usage:
##   AudioManager.play_trap_fire(Trap.TrapType.SNAP_TRAP)
##   AudioManager.play_enemy_death(Enemy.EnemyType.ANT)
##   AudioManager.play_ui("wave_clear")
##
## Adding a real audio file:
##   1. Drop it into game/assets/audio/<category>/
##   2. Replace null with preload("res://assets/audio/...") below.
##   No changes to Enemy.gd, Trap.gd, Arena.gd, or HUD.gd are needed.

extends Node


# ---------------------------------------------------------------------------
# Audio stream slots — replace null with preload() when the file is ready
# ---------------------------------------------------------------------------

# Background music
var music_bgm_arena:       AudioStream = null

# Trap fire sounds (one per trap type; index matches Trap.TrapType enum)
var sfx_trap_snap_fire:    AudioStream = preload("res://assets/audio/sfx/traps/snap_fire.wav")
var sfx_trap_zapper_fire:  AudioStream = preload("res://assets/audio/sfx/traps/zapper_fire.wav")
var sfx_trap_fogger_fire:  AudioStream = preload("res://assets/audio/sfx/traps/fogger_fire.wav")
var sfx_trap_glue_apply:   AudioStream = preload("res://assets/audio/sfx/traps/glue_apply.wav")

# Enemy hit sounds (one per trap type — what hit them, not who was hit)
var sfx_hit_snap:          AudioStream = null
var sfx_hit_zapper:        AudioStream = null
var sfx_hit_fogger:        AudioStream = null
var sfx_hit_glue:          AudioStream = null

# Enemy death sounds (keyed by tier rather than individual type)
var sfx_death_small:       AudioStream = null   # Ant, Gnat
var sfx_death_medium:      AudioStream = null   # Cricket, Beetle
var sfx_death_large:       AudioStream = null   # Cockroach
var sfx_death_rat:         AudioStream = null   # Rat boss

# Enemy footstep sounds (one per enemy type; index matches Enemy.EnemyType enum)
var sfx_step_ant:          AudioStream = null
var sfx_step_gnat:         AudioStream = null
var sfx_step_cricket:      AudioStream = null
var sfx_step_beetle:       AudioStream = null
var sfx_step_cockroach:    AudioStream = null
var sfx_step_rat:          AudioStream = null

# UI sounds (keyed by string name)
var sfx_ui_button:         AudioStream = null
var sfx_ui_wave_start:     AudioStream = null
var sfx_ui_wave_clear:     AudioStream = null
var sfx_ui_run_end:        AudioStream = null
var sfx_ui_bucks_earn:     AudioStream = null
var sfx_ui_upgrade:        AudioStream = null


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Minimum seconds between footstep sounds for the same enemy instance.
## Prevents the SFX pool from flooding when many enemies are on screen.
const FOOTSTEP_MIN_INTERVAL: float = 0.10

## Minimum seconds between bucks-earned chime plays, regardless of how many
## kills fire in rapid succession.
const BUCKS_CHIME_MIN_INTERVAL: float = 0.15

## Number of AudioStreamPlayers in the shared SFX pool (overlapping sounds).
const SFX_POOL_SIZE: int = 8

## Number of players in the footstep sub-pool (separate so volume is tunable).
const FOOTSTEP_POOL_SIZE: int = 4

## Number of players in the UI pool.
const UI_POOL_SIZE: int = 3


# ---------------------------------------------------------------------------
# Player pools
# ---------------------------------------------------------------------------

var _music_player:      AudioStreamPlayer
var _sfx_pool:          Array[AudioStreamPlayer] = []
var _footstep_pool:     Array[AudioStreamPlayer] = []
var _ui_pool:           Array[AudioStreamPlayer] = []

# Tracks the last time a footstep was played for each enemy node.
# Key = enemy Node3D, value = Time.get_ticks_msec() / 1000.0
var _last_footstep_time: Dictionary = {}

# Tracks the last time the bucks chime played.
var _last_bucks_chime_time: float = -999.0


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_music_player = _make_player("Music")
	_music_player.name = "MusicPlayer"
	add_child(_music_player)

	for i in range(SFX_POOL_SIZE):
		var p := _make_player("SFX")
		p.name = "SFX_%d" % i
		add_child(p)
		_sfx_pool.append(p)

	for i in range(FOOTSTEP_POOL_SIZE):
		var p := _make_player("SFX")
		p.name = "Step_%d" % i
		add_child(p)
		_footstep_pool.append(p)

	for i in range(UI_POOL_SIZE):
		var p := _make_player("UI")
		p.name = "UI_%d" % i
		add_child(p)
		_ui_pool.append(p)


# ---------------------------------------------------------------------------
# Music
# ---------------------------------------------------------------------------

## Starts the arena background music loop. Called when a run begins.
func start_music() -> void:
	if music_bgm_arena == null:
		return
	_music_player.stream = music_bgm_arena
	_music_player.play()


## Stops the background music. Called when a run ends.
func stop_music() -> void:
	_music_player.stop()


# ---------------------------------------------------------------------------
# Trap audio
# ---------------------------------------------------------------------------

## Play the fire sound for the given trap type. Called by Trap.gd at the
## start of each fire animation. trap_type is a Trap.TrapType int value.
func play_trap_fire(trap_type: int) -> void:
	var stream: AudioStream = _trap_fire_stream(trap_type)
	_play_sfx(stream)


# ---------------------------------------------------------------------------
# Enemy audio
# ---------------------------------------------------------------------------

## Play the hit sound determined by which trap hit the enemy.
## enemy_type is unused for hit sounds (the trap type picks the sound).
## trap_type is a Trap.TrapType int value; -1 means unknown/no trap.
func play_enemy_hit(trap_type: int) -> void:
	var stream: AudioStream = _hit_stream(trap_type)
	_play_sfx(stream)


## Play the death sound scaled to the enemy's tier.
## enemy_type is an Enemy.EnemyType int value.
func play_enemy_death(enemy_type: int) -> void:
	var stream: AudioStream = _death_stream(enemy_type)
	_play_sfx(stream)


## Play a footstep for the given enemy, rate-limited per enemy instance.
## enemy_node is passed as the rate-limit key. enemy_type is Enemy.EnemyType int.
func play_enemy_footstep(enemy_node: Node3D, enemy_type: int) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var last: float = _last_footstep_time.get(enemy_node, -999.0)
	if now - last < FOOTSTEP_MIN_INTERVAL:
		return
	_last_footstep_time[enemy_node] = now

	var stream: AudioStream = _step_stream(enemy_type)
	_play_on_pool(stream, _footstep_pool)


## Called when an enemy node is freed so its rate-limit entry is cleaned up.
func unregister_enemy(enemy_node: Node3D) -> void:
	_last_footstep_time.erase(enemy_node)


# ---------------------------------------------------------------------------
# UI audio
# ---------------------------------------------------------------------------

## Play a named UI sound. sound_name must match one of the sfx_ui_* variable
## names without the "sfx_ui_" prefix (e.g. "button", "wave_start").
func play_ui(sound_name: String) -> void:
	if sound_name == "bucks_earn":
		var now := Time.get_ticks_msec() / 1000.0
		if now - _last_bucks_chime_time < BUCKS_CHIME_MIN_INTERVAL:
			return
		_last_bucks_chime_time = now

	var stream: AudioStream = _ui_stream(sound_name)
	_play_on_pool(stream, _ui_pool)


# ---------------------------------------------------------------------------
# Volume control — called by HUD sliders
# ---------------------------------------------------------------------------

## Set the Music bus volume (0.0 = silent, 1.0 = full).
func set_music_volume(linear: float) -> void:
	AudioServer.set_bus_volume_db(
		AudioServer.get_bus_index("Music"),
		linear_to_db(maxf(linear, 0.0001))
	)


## Set the SFX bus volume (0.0 = silent, 1.0 = full). Affects both SFX and
## footstep pools since both route to the SFX bus.
func set_sfx_volume(linear: float) -> void:
	AudioServer.set_bus_volume_db(
		AudioServer.get_bus_index("SFX"),
		linear_to_db(maxf(linear, 0.0001))
	)


# ---------------------------------------------------------------------------
# Private — stream lookups
# ---------------------------------------------------------------------------

func _trap_fire_stream(trap_type: int) -> AudioStream:
	match trap_type:
		0: return sfx_trap_snap_fire     # SNAP_TRAP
		1: return sfx_trap_zapper_fire   # ZAPPER
		2: return sfx_trap_fogger_fire   # FOGGER
		3: return sfx_trap_glue_apply    # GLUE_BOARD
	return null


func _hit_stream(trap_type: int) -> AudioStream:
	match trap_type:
		0: return sfx_hit_snap
		1: return sfx_hit_zapper
		2: return sfx_hit_fogger
		3: return sfx_hit_glue
	return null


func _death_stream(enemy_type: int) -> AudioStream:
	# Enemy.EnemyType: ANT=0, GNAT=1, CRICKET=2, BEETLE=3, COCKROACH=4, RAT=5
	match enemy_type:
		0, 1: return sfx_death_small    # Ant, Gnat
		2, 3: return sfx_death_medium   # Cricket, Beetle
		4:    return sfx_death_large    # Cockroach
		5:    return sfx_death_rat      # Rat
	return null


func _step_stream(enemy_type: int) -> AudioStream:
	match enemy_type:
		0: return sfx_step_ant
		1: return sfx_step_gnat
		2: return sfx_step_cricket
		3: return sfx_step_beetle
		4: return sfx_step_cockroach
		5: return sfx_step_rat
	return null


func _ui_stream(sound_name: String) -> AudioStream:
	match sound_name:
		"button":     return sfx_ui_button
		"wave_start": return sfx_ui_wave_start
		"wave_clear": return sfx_ui_wave_clear
		"run_end":    return sfx_ui_run_end
		"bucks_earn": return sfx_ui_bucks_earn
		"upgrade":    return sfx_ui_upgrade
	return null


# ---------------------------------------------------------------------------
# Private — playback helpers
# ---------------------------------------------------------------------------

func _play_sfx(stream: AudioStream) -> void:
	_play_on_pool(stream, _sfx_pool)


## Finds the first idle player in the pool and plays the stream.
## If all players are busy, the oldest one is interrupted.
func _play_on_pool(stream: AudioStream, pool: Array[AudioStreamPlayer]) -> void:
	if stream == null:
		return
	# Prefer an idle player.
	for p: AudioStreamPlayer in pool:
		if not p.playing:
			p.stream = stream
			p.play()
			return
	# All busy — use the first player (oldest, most likely near its end).
	pool[0].stream = stream
	pool[0].play()


## Creates an AudioStreamPlayer assigned to the named bus.
func _make_player(bus_name: String) -> AudioStreamPlayer:
	var p         := AudioStreamPlayer.new()
	p.bus          = bus_name
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	return p
