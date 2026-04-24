## Projectile.gd
## Cosmetic-only projectile that travels from a trap to where a pest was
## when the trap fired. Damage is already applied by the time this spawns —
## this node exists solely to give the shot a visible arc.
##
## Usage: instantiate via Arena, call initialize(), then add to scene tree.

extends Node3D

const Grid = preload("res://arena/Grid.gd")

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Travel speed in world units per second.
const TRAVEL_SPEED: float = 20.0

## Fallback colour for generic projectiles (non-snap-trap types).
const COLOR_PROJECTILE := Color(1.0, 0.90, 0.25)   # bright yellow
const COLOR_IMPACT     := Color(1.0, 0.80, 0.15)   # golden burst

# Mirrors Trap.TrapType.SNAP_TRAP (int 0). Avoid preloading Trap.gd here to
# prevent a circular dependency — update this if the enum order ever changes.
const _SNAP_TRAP_TYPE: int = 0


# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

var _target_pos: Vector3
var _target:     Node3D = null
var _damage:     float  = 0.0
var _trap_type:  int    = -1
var _visual:     Node3D = null   # visual mesh child; rotated each frame for tumble


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Positions the projectile at from_pos and sends it toward to_pos.
## Applies damage to target on arrival rather than at fire time, so the
## enemy's hit flash coincides with the visual impact.
## Must be called by Arena immediately after instantiation and before
## adding to the scene tree.
func initialize(from_pos: Vector3, to_pos: Vector3, target: Node3D, damage: float, trap_type: int = -1) -> void:
	position    = from_pos
	_target_pos = Vector3(to_pos.x, from_pos.y, to_pos.z)   # travel flat on XZ plane
	_target     = target
	_damage     = damage
	_trap_type  = trap_type
	_spawn_visual()


# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _visual != null:
		_visual.rotation_degrees.x += delta * 380.0   # tumble forward as it travels

	var offset   := _target_pos - global_position
	var distance := offset.length()
	if distance < 0.05:
		var killed       := false
		var enemy_color  := Color.WHITE
		if is_instance_valid(_target):
			enemy_color = _target.get_color()
			_target.take_damage(_damage)
			killed = _target.get_hp_fraction() == 0.0
		_spawn_impact_effect(killed, enemy_color)
		queue_free()
		return
	global_position += offset.normalized() * minf(TRAVEL_SPEED * delta, distance)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _spawn_visual() -> void:
	if _trap_type == _SNAP_TRAP_TYPE:
		_spawn_cheese_visual()
		return

	var mi  := MeshInstance3D.new()
	var box := BoxMesh.new()
	# 50% of the enemy cylinder: diameter = CELL_SIZE * 1.35, height = CELL_SIZE * 0.5
	var s   := Grid.CELL_SIZE * 0.5
	box.size = Vector3(s * 1.35, s * 0.5, s * 1.35)
	mi.mesh  = box

	var mat           := StandardMaterial3D.new()
	mat.albedo_color   = COLOR_PROJECTILE
	mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat

	add_child(mi)


## Cheese wedge projectile — a 3-segment cylinder (triangular prism) in cheese
## yellow. Stored in _visual so _process can tumble it each frame.
func _spawn_cheese_visual() -> void:
	var mi             := MeshInstance3D.new()
	var mesh           := CylinderMesh.new()
	mesh.radial_segments = 3
	mesh.top_radius      = Grid.CELL_SIZE * 0.18
	mesh.bottom_radius   = Grid.CELL_SIZE * 0.18
	mesh.height          = Grid.CELL_SIZE * 0.22

	var mat           := StandardMaterial3D.new()
	mat.albedo_color   = Color(0.95, 0.82, 0.15)
	mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.mesh              = mesh
	mi.material_override = mat

	_visual = mi
	add_child(mi)


func _spawn_impact_effect(killed: bool, enemy_color: Color) -> void:
	if _trap_type == _SNAP_TRAP_TYPE:
		_spawn_cheese_splat(killed, enemy_color)
		return

	_spawn_particles(8, 0.4, Grid.CELL_SIZE * 1.15, Grid.CELL_SIZE * 2.875, 0.4, 0.7,
			Grid.CELL_SIZE * 0.28, COLOR_IMPACT)

	if killed:
		_spawn_particles(9, 0.33, Grid.CELL_SIZE * 5.6, Grid.CELL_SIZE * 16.8, 0.64, 1.68,
				Grid.CELL_SIZE * 0.495, enemy_color, true)


## Impact effect for a cheese projectile: a flat spray of yellow chunks and a
## few pale highlight flecks. Keeps the kill burst on enemy color so it reads
## as a death moment rather than just a cheese hit.
func _spawn_cheese_splat(killed: bool, enemy_color: Color) -> void:
	_spawn_particles(7, 0.35, Grid.CELL_SIZE * 0.8, Grid.CELL_SIZE * 2.2, 0.35, 0.65,
			Grid.CELL_SIZE * 0.22, Color(0.95, 0.82, 0.15))
	_spawn_particles(3, 0.28, Grid.CELL_SIZE * 0.6, Grid.CELL_SIZE * 1.6, 0.20, 0.45,
			Grid.CELL_SIZE * 0.14, Color(1.0, 0.95, 0.70))

	if killed:
		_spawn_particles(9, 0.33, Grid.CELL_SIZE * 5.6, Grid.CELL_SIZE * 16.8, 0.64, 1.68,
				Grid.CELL_SIZE * 0.495, enemy_color, true)


func _spawn_particles(amount: int, lifetime: float, vel_min: float, vel_max: float,
		scale_min: float, scale_max: float, spark_size: float, color: Color,
		round_mesh: bool = false) -> void:
	var particles := CPUParticles3D.new()
	particles.one_shot             = true
	particles.explosiveness        = 1.0
	particles.amount               = amount
	particles.lifetime             = lifetime
	particles.direction            = Vector3.UP
	particles.spread               = 180.0
	particles.initial_velocity_min = vel_min
	particles.initial_velocity_max = vel_max
	particles.gravity              = Vector3(0.0, -Grid.CELL_SIZE * 10.0, 0.0)
	particles.scale_amount_min     = scale_min
	particles.scale_amount_max     = scale_max

	var spark_mesh: Mesh
	if round_mesh:
		var sphere := SphereMesh.new()
		sphere.radius = spark_size * 0.5
		sphere.height = spark_size
		spark_mesh = sphere
	else:
		var box := BoxMesh.new()
		box.size = Vector3(spark_size, spark_size * 0.5, spark_size)
		spark_mesh = box
	var spark_mat           := StandardMaterial3D.new()
	spark_mat.albedo_color   = color
	spark_mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mesh.material      = spark_mat
	particles.mesh           = spark_mesh

	get_parent().add_child(particles)
	particles.global_position = global_position
	particles.restart()
	get_tree().create_timer(lifetime + 0.15).timeout.connect(particles.queue_free)
