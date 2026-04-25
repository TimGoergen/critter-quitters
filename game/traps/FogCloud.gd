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
const COLOR_CLOUD := Color(0.40, 0.88, 0.40, 0.10)
# Exposed so Trap.gd can compute the batch visual lifetime for the cloud cap timer.
const PARTICLE_LIFETIME: float = 4.8


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
			enemy.take_damage(_damage)
			_hit_enemies.append(enemy)

	# Free once the wave has swept the full range — all possible hits are done.
	if _cloud_radius >= _aoe_range:
		queue_free()


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Spawns the particle cloud under the parent (Arena) so it survives this
## node freeing. Particles are already a one-shot burst and need no owner
## after they have started.
func _spawn_cloud_visual(aoe_range: float) -> void:
	var particles          := CPUParticles3D.new()
	particles.one_shot      = true
	# Low explosiveness: puffs appear gradually over the lifetime rather than
	# all at once, so the space fills incrementally.
	particles.explosiveness = 0.10
	particles.amount        = randi_range(3, 4)
	particles.lifetime      = PARTICLE_LIFETIME

	# Puffs spawn in a tight cluster around the trap then drift slowly outward.
	particles.emission_shape         = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = aoe_range * 0.04

	# direction=UP + spread=90 gives random horizontal XZ velocity in all directions
	# (Godot rotates UP by a random angle up to spread° around a random horizontal axis,
	# producing the full XZ circle). Velocity must significantly exceed particle radius
	# (0.5–1.25 units) so drift is visible, and damping must stay near zero so particles
	# carry that velocity across their full lifetime rather than stopping early.
	particles.direction            = Vector3.UP
	particles.spread               = 90.0
	particles.initial_velocity_min = Grid.CELL_SIZE * 0.36
	particles.initial_velocity_max = Grid.CELL_SIZE * 0.80
	particles.gravity              = Vector3.ZERO
	particles.damping_min          = 0.0
	particles.damping_max          = 0.15

	# Wide size variance so puffs are visibly different from each other.
	# Reduced from 3–7 to 2–5 for smaller individual puffs.
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 5.0

	# Slow bloom-in then a long plateau before gently shrinking — gas expands
	# into the space rather than popping out.
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0,  0.03))
	scale_curve.add_point(Vector2(0.35, 1.0))
	scale_curve.add_point(Vector2(0.70, 1.0))
	scale_curve.add_point(Vector2(1.0,  0.85))
	particles.scale_amount_curve = scale_curve

	# Mesh: vertex_color_use_as_albedo lets color_ramp drive the final tint.
	var sphere   := SphereMesh.new()
	sphere.radius = Grid.CELL_SIZE * 0.50
	sphere.height = Grid.CELL_SIZE * 1.00
	var mat                       := StandardMaterial3D.new()
	mat.albedo_color               = Color.WHITE
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency               = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere.material                = mat
	particles.mesh                 = sphere

	# Puffs materialise and dissolve at half the previous rate.
	# Fade-in runs 0→0.36, plateau 0.36→0.64, fade-out 0.64→1.0
	# (previously 0→0.18 and 0.72→1.0 — both transition windows doubled).
	var gradient := Gradient.new()
	gradient.set_color(0, Color(COLOR_CLOUD.r, COLOR_CLOUD.g, COLOR_CLOUD.b, 0.0))
	gradient.set_color(1, Color(COLOR_CLOUD.r, COLOR_CLOUD.g, COLOR_CLOUD.b, 0.0))
	gradient.add_point(0.36, COLOR_CLOUD)
	gradient.add_point(0.64, COLOR_CLOUD)
	particles.color_ramp = gradient

	get_parent().add_child(particles)
	particles.global_position = global_position
	particles.restart()
	# Puffs emit over ~(lifetime * (1 - explosiveness)) seconds then each lives
	# lifetime longer — budget both phases plus a small buffer for cleanup.
	get_tree().create_timer(particles.lifetime * 2.0 + 0.20).timeout.connect(particles.queue_free)


## XZ-plane distance from this cloud's origin to a world position.
func _xz_distance(world_pos: Vector3) -> float:
	var dx := global_position.x - world_pos.x
	var dz := global_position.z - world_pos.z
	return sqrt(dx * dx + dz * dz)
