extends Camera3D
## Free-fly spectator camera (editor/Unreal-style).
##  - Hold RIGHT mouse button to look around (mouse captured while held).
##  - WASD move, Q/E (or Space/Ctrl) down/up, relative to where you look.
##  - SHIFT = boost, mouse wheel = change base speed.

const LOOK_SENS := 0.0025      # radians per pixel of mouse motion
const PITCH_LIMIT := 1.5       # ~86 deg, just under straight up/down
const BASE_SPEED := 8.0        # m/s
const BOOST_MULT := 4.0
const SPEED_STEP := 1.2        # mouse-wheel speed increment factor
const SPEED_MIN := 1.0
const SPEED_MAX := 80.0
const ACCEL := 12.0            # velocity smoothing

var _yaw := 0.0
var _pitch := 0.0
var _speed := BASE_SPEED
var _looking := false
var _velocity := Vector3.ZERO


func _ready() -> void:
	_yaw = rotation.y
	_pitch = rotation.x


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_looking = event.pressed
			Input.mouse_mode = (Input.MOUSE_MODE_CAPTURED if _looking
				else Input.MOUSE_MODE_VISIBLE)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_speed = clampf(_speed * SPEED_STEP, SPEED_MIN, SPEED_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_speed = clampf(_speed / SPEED_STEP, SPEED_MIN, SPEED_MAX)
	elif event is InputEventMouseMotion and _looking:
		_yaw -= event.relative.x * LOOK_SENS
		_pitch = clampf(_pitch - event.relative.y * LOOK_SENS, -PITCH_LIMIT, PITCH_LIMIT)


func _process(delta: float) -> void:
	rotation = Vector3(_pitch, _yaw, 0.0)

	var dir := Vector3.ZERO
	if _looking:
		# Use physical keys so layout doesn't matter; only steer while looking.
		if Input.is_physical_key_pressed(KEY_W): dir -= transform.basis.z
		if Input.is_physical_key_pressed(KEY_S): dir += transform.basis.z
		if Input.is_physical_key_pressed(KEY_A): dir -= transform.basis.x
		if Input.is_physical_key_pressed(KEY_D): dir += transform.basis.x
		if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_SPACE):
			dir += Vector3.UP
		if Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_CTRL):
			dir -= Vector3.UP

	var target_speed := _speed
	if Input.is_physical_key_pressed(KEY_SHIFT):
		target_speed *= BOOST_MULT
	var target_vel := dir.normalized() * target_speed
	_velocity = _velocity.lerp(target_vel, 1.0 - exp(-ACCEL * delta))
	global_position += _velocity * delta
