extends Node3D


@onready var _camera : Camera3D = $Camera3D

@export var _auto_rotate : bool = true

const ROTATION_DEG : float = 45
const MOVE_SPEED : float = 50.0

var _is_rotating : bool = false
var _tween : Tween


func _process(delta: float) -> void:
	if _auto_rotate:
		rotate_y(deg_to_rad(15) * delta)


func _physics_process(delta: float) -> void:
	if _auto_rotate:
		return
	
	# Handle camera movement
	var movement_input := Input.get_vector(
		"move_left",
		"move_right",
		"move_backward",
		"move_forward"
	)
	
	var forward := -_camera.global_transform.basis.z
	var right := _camera.global_transform.basis.x
	
	forward.y = 0
	right.y = 0
	
	forward = forward.normalized()
	right = right.normalized()
	
	forward = forward.normalized()
	right = right.normalized()
	
	var direction := right * movement_input.x + forward * movement_input.y
	
	if Input.is_action_pressed("move_up"):
		direction += Vector3.UP
	if Input.is_action_pressed("move_down"):
		direction += Vector3.DOWN
	
	if direction != Vector3.ZERO:
		global_position += direction.normalized() * MOVE_SPEED * delta


func _input(event: InputEvent) -> void:
	# Handle camera rotation
	if _is_rotating:
		return
	
	if event.is_action_pressed("rotate_camera_left"):
		_is_rotating = true
		await _rotate_camera(-ROTATION_DEG)
		_is_rotating = false
	elif event.is_action_pressed("rotate_camera_right"):
		_is_rotating = true
		await _rotate_camera(ROTATION_DEG)
		_is_rotating = false


func _rotate_camera(degrees: float) -> Signal:
	if _tween and _tween.is_running():
		_tween.kill()
	_tween = create_tween()
	var new_rotation_y := rotation.y + deg_to_rad(degrees)
	_tween.tween_property(self, "rotation:y", new_rotation_y, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	return _tween.finished
