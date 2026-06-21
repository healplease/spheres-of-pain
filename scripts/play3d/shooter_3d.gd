class_name Shooter3D
extends Node3D

## 3D shooter: shows the loaded + next sphere meshes at the muzzle and emits
## `fired` on the fire action. Aim/trajectory is computed by LevelController3D
## (it owns the camera and the shot simulation), so this node is presentation +
## input only — mirroring the 2D Shooter.

signal fired
## HOLD scheme only: true while the fire button is held (press -> release), so the
## controller can show the aim ray for the duration of the aim. Never emitted in CLICK.
signal aim_active_changed(active: bool)

const NEXT_SCALE := 0.6  # the queued sphere is shown smaller, off to the side
const RELOAD_TIME := 0.16  # next sphere sliding into the muzzle slot
const APPEAR_TIME := 0.14  # fresh next sphere growing into the side slot

## Whether the gun can fire. Disabled while a shot is in flight; the controller
## flips it back on when the shot resolves. In HOLD, a re-enable that lands while
## the fire button is still physically held re-arms the aim ray — otherwise the
## press that should have shown it was swallowed (it arrived while disabled).
var enabled: bool:
	get:
		return _enabled
	set(value):
		var was := _enabled
		_enabled = value
		if value and not was and hold_to_fire and Input.is_action_pressed("fire"):
			aim_active_changed.emit(true)
## CLICK (false): fire on press. HOLD (true): press begins aiming, release fires.
## Set once by the controller at level build from the player's Gameplay setting.
var hold_to_fire := false
var current_color := 0
var next_color := 1

var _enabled := true  # backing field for `enabled`
var _mesh: Mesh
var _mats: Array  # Array[StandardMaterial3D]
var _loaded: MeshInstance3D
var _next: MeshInstance3D
var _next_home := Vector3.ZERO
var _reload_tween: Tween


func setup(p_mesh: Mesh, p_mats: Array, radius: float) -> void:
	_mesh = p_mesh
	_mats = p_mats
	_loaded = MeshInstance3D.new()
	_loaded.mesh = _mesh
	add_child(_loaded)
	_next = MeshInstance3D.new()
	_next.mesh = _mesh
	_next_home = Vector3(radius * 2.4, 0.0, 0.0)
	add_child(_next)
	refresh_colors()


## The loaded round just left as the projectile: empty the muzzle slot at once,
## slide the queued sphere into it (growing to full size), then grow a fresh
## next sphere into the side slot. Promotes next -> current immediately, so the
## gun shows its true colour during the shot's flight.
func reload(new_next: int) -> void:
	current_color = next_color
	next_color = new_next
	_kill_reload()
	_loaded.visible = false
	_reload_tween = create_tween()
	_reload_tween.set_parallel(true)
	(
		_reload_tween
		. tween_property(_next, "position", Vector3.ZERO, RELOAD_TIME)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	(
		_reload_tween
		. tween_property(_next, "scale", Vector3.ONE, RELOAD_TIME)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	_reload_tween.chain().tween_callback(_settle_reload)


## The promoted sphere reaches the muzzle: hand its place to the loaded mesh and
## refill the side slot from nothing.
func _settle_reload() -> void:
	_apply_slots()
	_next.scale = Vector3.ZERO
	_reload_tween = create_tween()
	(
		_reload_tween
		. tween_property(_next, "scale", Vector3.ONE * NEXT_SCALE, APPEAR_TIME)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)


## Snap both slots to the current colours/transforms. Also cancels a reload
## animation mid-flight — used when the controller re-rolls a slot whose colour
## the resolving shot just wiped off the board.
func refresh_colors() -> void:
	_kill_reload()
	_apply_slots()


func _apply_slots() -> void:
	if _loaded == null:
		return
	_loaded.material_override = _mats[current_color % _mats.size()]
	_loaded.visible = true
	_next.material_override = _mats[next_color % _mats.size()]
	_next.position = _next_home
	_next.scale = Vector3.ONE * NEXT_SCALE


func _kill_reload() -> void:
	if _reload_tween != null and _reload_tween.is_valid():
		_reload_tween.kill()
	_reload_tween = null


func _unhandled_input(event: InputEvent) -> void:
	if hold_to_fire:
		# Press starts the aim (only when we're allowed to fire); release always clears
		# the aim flag — even if firing was disabled mid-hold — so the ray can't stick
		# on, then fires only if still enabled.
		if event.is_action_pressed("fire"):
			if enabled:
				aim_active_changed.emit(true)
		elif event.is_action_released("fire"):
			aim_active_changed.emit(false)
			if enabled:
				fired.emit()
	elif enabled and event.is_action_pressed("fire"):
		fired.emit()
