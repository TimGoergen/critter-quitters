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
		if is_instance_valid(_target):
			_target.take_damage(_damage)
		queue_free()
		return
	global_position += offset.normalized() * minf(TRAVEL_SPEED * delta, distance)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

func _spawn_visual() -> void:
	var mi  := MeshInstance3D.new()
	var box := BoxMesh.new()
	# 10% of the enemy cylinder: diameter = CELL_SIZE * 1.35, height = CELL_SIZE * 0.5
	var s   := Grid.CELL_SIZE * 0.1
	box.size = Vector3(s * 1.35, s * 0.5, s * 1.35)
	mi.mesh  = box

	var mat           := StandardMaterial3D.new()
	mat.albedo_color   = COLOR_PROJECTILE
	mat.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat

	add_child(mi)
