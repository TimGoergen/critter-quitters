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

## Wave expansion speed in world units per second. Set to match the slow
## end of the particle velocity range so the visual leads the damage wave.
const EXPAND_SPEED: float = 3.0

const CLOUD_LIFETIME: float = 0.90
const COLOR_CLOUD := Color(0.40, 0.88, 0.40, 0.20)


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
	var particles                    := CPUParticles3D.new()
	particles.one_shot                = true
	particles.explosiveness           = 0.75
	particles.amount                  = 24
	particles.lifetime                = CLOUD_LIFETIME

	particles.emission_shape          = CPUParticles3D.EMISSION_SHAPE_POINT
	particles.direction               = Vector3.UP
	particles.spread                  = 88.0
	particles.initial_velocity_min    = Grid.CELL_SIZE * 1.5
	particles.initial_velocity_max    = Grid.CELL_SIZE * 4.5
	particles.gravity                 = Vector3.ZERO
	particles.scale_amount_min        = 1.4
	particles.scale_amount_max        = 3.2

	var sphere    := SphereMesh.new()
	sphere.radius  = Grid.CELL_SIZE * 0.50
	sphere.height  = Grid.CELL_SIZE * 1.00
	var mat               := StandardMaterial3D.new()
	mat.albedo_color       = COLOR_CLOUD
	mat.shading_mode       = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency       = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere.material        = mat
	particles.mesh         = sphere

	get_parent().add_child(particles)
	particles.global_position = global_position
	particles.restart()
	get_tree().create_timer(CLOUD_LIFETIME + 0.20).timeout.connect(particles.queue_free)


## XZ-plane distance from this cloud's origin to a world position.
func _xz_distance(world_pos: Vector3) -> float:
	var dx := global_position.x - world_pos.x
	var dz := global_position.z - world_pos.z
	return sqrt(dx * dx + dz * dz)
