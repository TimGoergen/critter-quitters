## FogCloud.gd
## Single-instance AoE visual spawned once each time the Fogger fires.
## Fills the trap's full range with a cloud of green particles that rises
## briefly from the affected area and dissipates.
##
## No damage logic — the Fogger applies damage directly in Trap.gd.
## This node is purely cosmetic, matching the same contract as Projectile.gd.

extends Node3D

const Grid = preload("res://arena/Grid.gd")

const CLOUD_LIFETIME: float = 0.90
const COLOR_CLOUD := Color(0.40, 0.88, 0.40, 0.50)

# Set by initialize(); consumed by _ready() after the node enters the tree.
var _aoe_range: float = 0.0


# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------

## Positions the cloud at from_pos covering aoe_range world units.
## Must be called by Arena immediately after instantiation and before
## adding to the scene tree.
func initialize(from_pos: Vector3, aoe_range: float) -> void:
	global_position = from_pos
	_aoe_range      = aoe_range


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

## _ready fires as soon as the node enters the tree, so get_tree() is safe here.
func _ready() -> void:
	_spawn_cloud(_aoe_range)
	# Self-destruct after the particles have had time to fully dissipate.
	get_tree().create_timer(CLOUD_LIFETIME + 0.20).timeout.connect(queue_free)


# ---------------------------------------------------------------------------
# Private helpers
# ---------------------------------------------------------------------------

## Spawns a CPUParticles3D burst that originates at the trap centre and
## drifts radially outward. Emitting from a point with a near-hemisphere
## spread means every puff starts at the trap and moves away from it in a
## different direction — from above this reads as fog expanding outward.
func _spawn_cloud(_aoe_range: float) -> void:
	var particles                    := CPUParticles3D.new()
	particles.one_shot                = true
	# explosiveness < 1.0 lets a few straggler puffs trail the main burst
	# so the emission feels organic rather than a single instant pop.
	particles.explosiveness           = 0.75
	particles.amount                  = 24
	particles.lifetime                = CLOUD_LIFETIME

	# Point emitter — all puffs originate at the trap centre.
	particles.emission_shape          = CPUParticles3D.EMISSION_SHAPE_POINT

	# Near-hemisphere spread around Vector3.UP: particles travel from directly
	# overhead all the way to nearly horizontal, covering all compass directions.
	# From the top-down camera this produces a radial outward drift.
	particles.direction               = Vector3.UP
	particles.spread                  = 88.0
	particles.initial_velocity_min    = Grid.CELL_SIZE * 1.5
	particles.initial_velocity_max    = Grid.CELL_SIZE * 4.5
	# Zero gravity so puffs float outward rather than arcing back to the floor.
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

	add_child(particles)
	particles.restart()
