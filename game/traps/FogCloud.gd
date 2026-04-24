## FogCloud.gd
## Single-instance AoE visual spawned once each time the Fogger fires.
## Fills the trap's full range with a cloud of green particles that rises
## briefly from the affected area and dissipates.
##
## No damage logic — the Fogger applies damage directly in Trap.gd.
## This node is purely cosmetic, matching the same contract as Projectile.gd.

extends Node3D

const Grid = preload("res://arena/Grid.gd")

const CLOUD_LIFETIME: float = 0.70
const COLOR_CLOUD := Color(0.40, 0.88, 0.40, 0.60)

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

## Spawns a CPUParticles3D burst distributed flat across the AoE footprint.
## Using a thin box emitter keeps all particles at floor level so the cloud
## reads clearly from the top-down camera.
func _spawn_cloud(aoe_range: float) -> void:
	var particles                    := CPUParticles3D.new()
	particles.one_shot                = true
	# explosiveness < 1.0 gives a few straggler puffs that trail the main burst,
	# making the cloud feel organic rather than an instant snap.
	particles.explosiveness           = 0.75
	particles.amount                  = 48
	particles.lifetime                = CLOUD_LIFETIME

	# Flat box emission — thin in Y so all particles start at ground level and
	# rise, rather than scattering through a sphere volume above and below.
	particles.emission_shape          = CPUParticles3D.EMISSION_SHAPE_BOX
	particles.emission_box_extents    = Vector3(aoe_range, 0.05, aoe_range)

	# Slow upward drift — the cloud rises gently and hangs in the air.
	particles.direction               = Vector3.UP
	particles.spread                  = 15.0   # tight cone; no lateral scatter
	particles.initial_velocity_min    = Grid.CELL_SIZE * 0.4
	particles.initial_velocity_max    = Grid.CELL_SIZE * 1.1
	# Zero gravity so puffs float rather than arcing back down.
	particles.gravity                 = Vector3.ZERO
	particles.scale_amount_min        = 1.2
	particles.scale_amount_max        = 2.8

	var sphere    := SphereMesh.new()
	sphere.radius  = Grid.CELL_SIZE * 0.30
	sphere.height  = Grid.CELL_SIZE * 0.60
	var mat               := StandardMaterial3D.new()
	mat.albedo_color       = COLOR_CLOUD
	mat.shading_mode       = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency       = BaseMaterial3D.TRANSPARENCY_ALPHA
	sphere.material        = mat
	particles.mesh         = sphere

	add_child(particles)
	particles.restart()
