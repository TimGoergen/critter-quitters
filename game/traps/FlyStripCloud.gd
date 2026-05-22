## FlyStripCloud.gd
## Persistent AoE hazard spawned by the Fly Strip Launcher.
## The cloud lingers for a configurable duration, slowing flying enemies that
## pass through it and ticking damage on a fixed interval.
##
## Only flying enemies (enemy.get_is_flying() == true) are affected —
## ground pests walk underneath with no interaction.
##
## Slow sources are managed per-tick: enemies entering the cloud's radius
## receive add_slow_source(); enemies leaving (or still in range when the
## cloud expires) receive remove_slow_source() so they return to normal speed.
##
## Usage: Arena instantiates this in response to Trap.fly_strip_fired.
## Call initialize() before adding to the scene tree.

extends Node3D

const Grid = preload("res://arena/Grid.gd")

## How often (in seconds) the cloud deals damage to in-range flying enemies.
const DAMAGE_TICK_INTERVAL: float = 0.75

const COLOR_FLY_STRIP_CLOUD := Color(0.95, 0.45, 0.85, 0.025)   # pink/magenta sticky cloud
const COLOR_FLY_STRIP_HIT   := Color(0.95, 0.30, 0.75)           # hit flash color


# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

var _aoe_range:      float = 0.0
var _damage:         float = 0.0
var _adhesion:       float = 0.0
var _duration:       float = 0.0
var _active_enemies: Array = []

var _time_alive: float = 0.0
# Pre-set to interval so the first tick fires immediately on _ready,
# catching enemies already standing in the cloud.
var _tick_timer: float = DAMAGE_TICK_INTERVAL

# Flying enemies currently inside this cloud's radius.
# Maintained so remove_slow_source() can be called precisely on expiry or exit.
var _affected_enemies: Array = []


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Positions the cloud and stores combat parameters.
## Must be called by Arena immediately after instantiation and before
## adding to the scene tree.
func initialize(from_pos: Vector3, aoe_range: float, damage: float,
		adhesion: float, cloud_duration: float, active_enemies: Array) -> void:
	global_position = from_pos
	_aoe_range      = aoe_range
	_damage         = damage
	_adhesion       = adhesion
	_duration       = cloud_duration
	_active_enemies = active_enemies


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	_spawn_cloud_visual(_aoe_range)


# ---------------------------------------------------------------------------
# Tick loop
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time_alive += delta
	if _time_alive >= _duration:
		_release_all_slow()
		queue_free()
		return

	_tick_timer += delta
	if _tick_timer >= DAMAGE_TICK_INTERVAL:
		_tick_timer -= DAMAGE_TICK_INTERVAL
		_apply_tick()


## Applies slow + damage to flying enemies in range and releases those that left.
## Called on a fixed interval for as long as the cloud is alive.
func _apply_tick() -> void:
	# Build the set of flying enemies currently inside the radius.
	var in_range: Array = []
	for enemy in _active_enemies:
		if not is_instance_valid(enemy) or not enemy.get_is_flying():
			continue
		if _xz_distance(enemy.global_position) <= _aoe_range:
			in_range.append(enemy)

	# Apply slow to newly-entered enemies.
	for enemy in in_range:
		if not _affected_enemies.has(enemy):
			enemy.add_slow_source(self, _adhesion)
			_affected_enemies.append(enemy)

	# Release enemies that have flown out of range.
	var to_release: Array = []
	for enemy in _affected_enemies:
		if not is_instance_valid(enemy) or not in_range.has(enemy):
			to_release.append(enemy)
	for enemy in to_release:
		if is_instance_valid(enemy):
			enemy.remove_slow_source(self)
		_affected_enemies.erase(enemy)

	# Apply damage to all currently in range.
	for enemy in in_range:
		if is_instance_valid(enemy):
			enemy.take_damage(_damage, COLOR_FLY_STRIP_HIT)


## Removes slow from every enemy still in the cloud when it expires.
func _release_all_slow() -> void:
	for enemy in _affected_enemies:
		if is_instance_valid(enemy):
			enemy.remove_slow_source(self)
	_affected_enemies.clear()


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Spawns the particle cloud under the parent (Arena) so it survives this node freeing.
## Visual is a flat pink haze to evoke sticky fly paper hanging in the air.
func _spawn_cloud_visual(aoe_range: float) -> void:
	var particles           := CPUParticles3D.new()
	particles.one_shot       = true
	particles.explosiveness  = 0.85
	particles.amount         = 30
	particles.lifetime       = _duration

	# Flat box emission — keeps the cloud at ground level so it reads as a zone.
	particles.emission_shape       = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(aoe_range * 0.50, Grid.CELL_SIZE * 0.04, aoe_range * 0.50)

	# Barely-there drift — same subtle movement as FogCloud.
	particles.direction            = Vector3.UP
	particles.spread               = 90.0
	particles.initial_velocity_min = Grid.CELL_SIZE * 0.03
	particles.initial_velocity_max = Grid.CELL_SIZE * 0.09
	particles.gravity              = Vector3.ZERO
	particles.damping_min          = 1.0
	particles.damping_max          = 2.0

	particles.scale_amount_min = 3.5
	particles.scale_amount_max = 8.0

	# Bloom in, hold, dissolve — same timing ratios as FogCloud.
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0,  0.0))
	scale_curve.add_point(Vector2(0.09, 1.0))
	scale_curve.add_point(Vector2(0.45, 1.0))
	scale_curve.add_point(Vector2(1.0,  0.0))
	particles.scale_amount_curve = scale_curve

	# Sphere mesh puffs for the same overlapping-blob look as FogCloud.
	var sphere    := SphereMesh.new()
	sphere.radius  = Grid.CELL_SIZE * 0.50
	sphere.height  = Grid.CELL_SIZE * 1.00
	var mat                       := StandardMaterial3D.new()
	mat.albedo_color               = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere.material                = mat
	particles.mesh                 = sphere

	# Color ramp: fully transparent edges fading into the pink cloud color at density.
	var peak     := COLOR_FLY_STRIP_CLOUD
	var gradient := Gradient.new()
	gradient.set_color(0, Color(peak.r, peak.g, peak.b, 0.0))
	gradient.set_color(1, Color(peak.r, peak.g, peak.b, 0.0))
	gradient.add_point(0.09, peak)
	gradient.add_point(0.45, peak)
	particles.color_ramp = gradient

	get_parent().add_child(particles)
	particles.global_position = global_position
	particles.restart()
	get_tree().create_timer(particles.lifetime * 2.0 + 0.20).timeout.connect(particles.queue_free)


## XZ-plane distance from this cloud's origin to a world position.
func _xz_distance(world_pos: Vector3) -> float:
	var dx := global_position.x - world_pos.x
	var dz := global_position.z - world_pos.z
	return sqrt(dx * dx + dz * dz)
