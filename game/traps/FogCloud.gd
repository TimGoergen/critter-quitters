## FogCloud.gd
## Cosmetic-only effect spawned by the Fogger trap — one instance per enemy
## in range each time the trap fires. Drifts slowly from the trap toward the
## enemy's position at fire time, then releases a green smoke burst and frees.
##
## Damage is already applied by Trap.gd before this node is created; this
## node exists only to give the shot a visible form, matching the same
## contract as Projectile.gd.

extends Node3D

const Grid = preload("res://arena/Grid.gd")

## Drift speed in world units per second — intentionally much slower than the
## Snap Trap bolt so the Fogger reads as a gas cloud, not a hard projectile.
const TRAVEL_SPEED: float = 5.0

## Arrival threshold: how close (world units) before triggering the burst.
const ARRIVAL_THRESHOLD: float = 0.12

## Fog puff color — semi-transparent green, distinct from the Snap Trap yellow.
const COLOR_FOG   := Color(0.45, 0.90, 0.45, 0.55)
const COLOR_BURST := Color(0.50, 0.95, 0.50, 0.75)


# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

var _target_pos: Vector3


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Positions the cloud at from_pos and sends it drifting toward to_pos.
## Must be called by Arena immediately after instantiation and before
## adding to the scene tree.
func initialize(from_pos: Vector3, to_pos: Vector3) -> void:
	position    = from_pos
	# Keep travel flat on the XZ plane so the puff does not bob vertically.
	_target_pos = Vector3(to_pos.x, from_pos.y, to_pos.z)
	_spawn_visual()


# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	var offset   := _target_pos - global_position
	var distance := offset.length()
	if distance <= ARRIVAL_THRESHOLD:
		_spawn_burst()
		queue_free()
		return
	global_position += offset.normalized() * minf(TRAVEL_SPEED * delta, distance)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Creates a semi-transparent green sphere as the travelling fog puff.
func _spawn_visual() -> void:
	var mi     := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	var r      := Grid.CELL_SIZE * 0.55
	sphere.radius = r
	sphere.height = r * 2.0
	mi.mesh    = sphere

	var mat             := StandardMaterial3D.new()
	mat.albedo_color     = COLOR_FOG
	mat.shading_mode     = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency     = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat

	add_child(mi)


## Spawns a small burst of green smoke particles at the arrival position.
func _spawn_burst() -> void:
	var particles                  := CPUParticles3D.new()
	particles.one_shot              = true
	particles.explosiveness         = 1.0
	particles.amount                = 9
	particles.lifetime              = 0.55
	particles.direction             = Vector3.UP
	particles.spread                = 180.0
	particles.initial_velocity_min  = Grid.CELL_SIZE * 0.9
	particles.initial_velocity_max  = Grid.CELL_SIZE * 2.8
	# Low gravity so the puffs linger and float rather than falling quickly.
	particles.gravity               = Vector3(0.0, -Grid.CELL_SIZE * 1.5, 0.0)
	particles.scale_amount_min      = 0.7
	particles.scale_amount_max      = 1.6

	var sphere    := SphereMesh.new()
	sphere.radius  = Grid.CELL_SIZE * 0.20
	sphere.height  = Grid.CELL_SIZE * 0.40
	var mat               := StandardMaterial3D.new()
	mat.albedo_color       = COLOR_BURST
	mat.shading_mode       = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency       = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere.material        = mat
	particles.mesh         = sphere

	# Attach to this node's parent so the particles survive queue_free().
	get_parent().add_child(particles)
	particles.global_position = global_position
	particles.restart()
	get_tree().create_timer(particles.lifetime + 0.15).timeout.connect(particles.queue_free)
