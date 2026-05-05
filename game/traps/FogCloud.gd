## FogCloud.gd
## Single-instance AoE effect spawned once each time the Fogger fires.
## Owns the damage logic: an invisible wave expands outward from the trap
## at EXPAND_SPEED and applies damage to each enemy the first time the
## wave radius reaches that enemy's current distance.
##
## The particle visual is spawned under the parent (Arena) so it can
## outlive this node — FogCloud frees itself once the wave has covered
## the full range and all in-range enemies have been checked.

extends Node3D

const Grid = preload("res://arena/Grid.gd")

## Wave expansion speed in world units per second.
## Chosen so the wave crosses the full range (~6.4 units) in approximately
## CLOUD_LIFETIME seconds — damage and visual dissipate together.
const EXPAND_SPEED: float = 4.44

const CLOUD_LIFETIME: float = 0.90
const COLOR_CLOUD      := Color(0.68, 0.95, 0.22, 0.02)
const COLOR_FOGGER_KILL := Color(0.40, 0.95, 0.25)   # bright green — fogger kill burst
# Exposed so Trap.gd can compute the batch visual lifetime for the cloud cap timer.
const PARTICLE_LIFETIME: float = 2.80


# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

var _aoe_range:     float        = 0.0
var _damage:        float        = 0.0
var _active_enemies: Array       = []

# Grows each frame; enemies are hit the first time this reaches their distance.
var _cloud_radius:  float        = 0.0

# Tracks which enemies have already been damaged this cycle (one hit each).
var _hit_enemies:   Array[Node3D] = []


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Positions the cloud and stores combat parameters.
## Must be called by Arena immediately after instantiation and before
## adding to the scene tree.
func initialize(from_pos: Vector3, aoe_range: float, damage: float, active_enemies: Array) -> void:
	global_position  = from_pos
	_aoe_range       = aoe_range
	_damage          = damage
	_active_enemies  = active_enemies


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Spawn particles under Arena so they continue playing after this node
	# frees itself. get_parent() is safe here because _ready fires after add_child.
	_spawn_cloud_visual(_aoe_range)


# ---------------------------------------------------------------------------
# Wave expansion
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_cloud_radius += EXPAND_SPEED * delta

	for enemy in _active_enemies:
		if not is_instance_valid(enemy):
			continue
		var already_hit: bool = enemy in _hit_enemies
		if already_hit:
			continue
		var dist: float = _xz_distance(enemy.global_position)
		# Hit the enemy when the wave reaches them, but only if they are still
		# within the original range (enemies that fled the area are not hit).
		if dist <= _aoe_range and dist <= _cloud_radius:
			var hit_pos: Vector3 = enemy.global_position
			enemy.take_damage(_damage, COLOR_FOGGER_KILL)
			_hit_enemies.append(enemy)
			if enemy.get_hp_fraction() == 0.0:
				_spawn_kill_burst(hit_pos)
			else:
				_spawn_hit_particles(hit_pos)

	# Free once the wave has swept the full range — all possible hits are done.
	if _cloud_radius >= _aoe_range:
		queue_free()


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Spawns the particle cloud under the parent (Arena) so it survives this
## node freeing. Particles are already a one-shot burst and need no owner
## after they have started.
##
## Cloud appearance relies on density, not count: 30 large overlapping puffs
## spawned nearly simultaneously across the full range area create a single
## cohesive mass. Where many puffs overlap the centre reads as solid; at the
## edges fewer puffs overlap so the boundary naturally looks fluffy.
func _spawn_cloud_visual(aoe_range: float) -> void:
	var particles           := CPUParticles3D.new()
	particles.one_shot       = true
	# High explosiveness: all puffs appear at once so the cloud snaps into
	# view rather than trickling out one circle at a time.
	particles.explosiveness  = 0.85
	particles.amount         = 30
	particles.lifetime       = PARTICLE_LIFETIME

	# Flat box emission across the full range area; tiny Y extent keeps every
	# puff at the same ground level so they all overlap when seen top-down.
	particles.emission_shape       = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents = Vector3(aoe_range * 0.50, Grid.CELL_SIZE * 0.04, aoe_range * 0.50)

	# Barely-there drift — the cloud breathes without the puffs flying apart.
	particles.direction            = Vector3.UP
	particles.spread               = 90.0
	particles.initial_velocity_min = Grid.CELL_SIZE * 0.03
	particles.initial_velocity_max = Grid.CELL_SIZE * 0.09
	particles.gravity              = Vector3.ZERO
	particles.damping_min          = 1.0
	particles.damping_max          = 2.0

	# Large size range — big puffs overlap and merge; small ones add texture
	# to the cloud edge without reading as individual circles.
	particles.scale_amount_min = 3.5
	particles.scale_amount_max = 8.0

	# Bloom in quickly, hold at full size, then dissolve slowly.
	# Absolute timings at PARTICLE_LIFETIME = 2.80 s:
	#   bloom  0.09 × 2.80 = 0.25 s  (unchanged — appears just as fast)
	#   hold   0.36 × 2.80 = 1.00 s  (reduced from 1.95 s — dissipation starts sooner)
	#   fade   0.55 × 2.80 = 1.54 s  (extended from 0.55 s — dissipation is slower)
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0,  0.0))
	scale_curve.add_point(Vector2(0.09, 1.0))
	scale_curve.add_point(Vector2(0.45, 1.0))
	scale_curve.add_point(Vector2(1.0,  0.0))
	particles.scale_amount_curve = scale_curve

	# Sphere mesh — top-down, spheres project as circles; packed together they
	# read as a single blob rather than identifiable shapes.
	var sphere    := SphereMesh.new()
	sphere.radius  = Grid.CELL_SIZE * 0.50
	sphere.height  = Grid.CELL_SIZE * 1.00
	var mat                        := StandardMaterial3D.new()
	mat.albedo_color                = Color.WHITE
	mat.vertex_color_use_as_albedo  = true
	mat.shading_mode                = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency                = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere.material                 = mat
	particles.mesh                  = sphere

	# Alpha 0.02 per puff: a single puff is barely visible, but 8–10 overlapping
	# in the dense centre stack to ~0.18 effective opacity — subtle, wispy cloud.
	var peak := Color(COLOR_CLOUD.r, COLOR_CLOUD.g, COLOR_CLOUD.b, COLOR_CLOUD.a)
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


## Spawns a small green hit burst at pos when the fog wave damages but does not kill.
func _spawn_hit_particles(pos: Vector3) -> void:
	var particles              := CPUParticles3D.new()
	particles.one_shot          = true
	particles.explosiveness     = 1.0
	particles.amount            = 5
	particles.lifetime          = 0.22
	particles.direction         = Vector3.UP
	particles.spread            = 180.0
	particles.initial_velocity_min = Grid.CELL_SIZE * 1.5
	particles.initial_velocity_max = Grid.CELL_SIZE * 4.5
	particles.gravity           = Vector3(0.0, -Grid.CELL_SIZE * 10.0, 0.0)
	particles.scale_amount_min  = 0.30
	particles.scale_amount_max  = 0.65

	var box    := BoxMesh.new()
	box.size    = Vector3(Grid.CELL_SIZE * 0.18, Grid.CELL_SIZE * 0.09, Grid.CELL_SIZE * 0.18)
	var mat                   := StandardMaterial3D.new()
	mat.albedo_color           = COLOR_FOGGER_KILL
	mat.shading_mode           = BaseMaterial3D.SHADING_MODE_UNSHADED
	box.material               = mat
	particles.mesh             = box

	get_parent().add_child(particles)
	particles.global_position  = pos
	particles.restart()
	get_tree().create_timer(particles.lifetime + 0.15).timeout.connect(particles.queue_free)


## Spawns a green explosion burst at pos when the fog wave kills an enemy.
## Mirrors the kill-burst pattern in Projectile._spawn_particles (round_mesh = true).
func _spawn_kill_burst(pos: Vector3) -> void:
	var particles              := CPUParticles3D.new()
	particles.one_shot          = true
	particles.explosiveness     = 1.0
	particles.amount            = 9
	particles.lifetime          = 0.33
	particles.direction         = Vector3.UP
	particles.spread            = 180.0
	particles.initial_velocity_min = Grid.CELL_SIZE * 5.6
	particles.initial_velocity_max = Grid.CELL_SIZE * 16.8
	particles.gravity           = Vector3(0.0, -Grid.CELL_SIZE * 10.0, 0.0)
	particles.scale_amount_min  = 0.64
	particles.scale_amount_max  = 1.68

	var sphere    := SphereMesh.new()
	sphere.radius  = Grid.CELL_SIZE * 0.495 * 0.5
	sphere.height  = Grid.CELL_SIZE * 0.495
	var mat                   := StandardMaterial3D.new()
	mat.albedo_color           = COLOR_FOGGER_KILL
	mat.shading_mode           = BaseMaterial3D.SHADING_MODE_UNSHADED
	sphere.material            = mat
	particles.mesh             = sphere

	get_parent().add_child(particles)
	particles.global_position  = pos
	particles.restart()
	get_tree().create_timer(particles.lifetime + 0.15).timeout.connect(particles.queue_free)


## XZ-plane distance from this cloud's origin to a world position.
func _xz_distance(world_pos: Vector3) -> float:
	var dx := global_position.x - world_pos.x
	var dz := global_position.z - world_pos.z
	return sqrt(dx * dx + dz * dz)
