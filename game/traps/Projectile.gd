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

## Placeholder colour. Replaced by ASCII billboard in Phase 3.
const COLOR_PROJECTILE := Color(1.0, 0.90, 0.25)   # bright yellow

const COLOR_IMPACT     := Color(1.0, 0.80, 0.15)   # golden burst


# ---------------------------------------------------------------------------
# Private state
# ---------------------------------------------------------------------------

var _target_pos: Vector3
var _target: Node3D = null
var _damage: float  = 0.0


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Positions the projectile at from_pos and sends it toward to_pos.
## Applies damage to target on arrival rather than at fire time, so the
## enemy's hit flash coincides with the visual impact.
## Must be called by Arena immediately after instantiation and before
## adding to the scene tree.
func initialize(from_pos: Vector3, to_pos: Vector3, target: Node3D, damage: float) -> void:
	position    = from_pos
	_target_pos = Vector3(to_pos.x, from_pos.y, to_pos.z)   # travel flat on XZ plane
	_target     = target
	_damage     = damage
	_spawn_visual()


# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	var offset   := _target_pos - global_position
	var distance := offset.length()
	if distance < 0.05:
		var killed := false
		if is_instance_valid(_target):
			_target.take_damage(_damage)
			killed = _target.get_hp_fraction() == 0.0
		_spawn_impact_effect(killed)
		queue_free()
		return
	global_position += offset.normalized() * minf(TRAVEL_SPEED * delta, distance)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _spawn_visual() -> void:
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


func _spawn_impact_effect(killed: bool) -> void:
	var scale := 1.0 if killed else 0.5

	var particles := CPUParticles3D.new()
	particles.one_shot              = true
	particles.explosiveness         = 1.0
	particles.amount                = 21 if killed else 6
	particles.lifetime              = 0.4
	particles.direction             = Vector3.UP
	particles.spread                = 180.0
	particles.initial_velocity_min  = Grid.CELL_SIZE * 2.0 * scale
	particles.initial_velocity_max  = Grid.CELL_SIZE * 5.0 * scale
	particles.gravity               = Vector3(0.0, -Grid.CELL_SIZE * 10.0, 0.0)
	particles.scale_amount_min      = 0.8 * scale
	particles.scale_amount_max      = 1.4 * scale

	var spark_mesh := BoxMesh.new()
	var spark_size := Grid.CELL_SIZE * 0.18 if killed else Grid.CELL_SIZE * 0.45
	spark_mesh.size = Vector3(spark_size, spark_size * 0.5, spark_size)


	var spark_mat           := StandardMaterial3D.new()
	spark_mat.albedo_color   = COLOR_IMPACT
	spark_mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	spark_mesh.material      = spark_mat
	particles.mesh           = spark_mesh

	# Add to parent so the effect outlives the projectile node.
	get_parent().add_child(particles)
	particles.global_position = global_position
	particles.restart()
	get_tree().create_timer(particles.lifetime + 0.15).timeout.connect(particles.queue_free)
