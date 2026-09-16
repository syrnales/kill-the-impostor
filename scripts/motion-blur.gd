extends Camera3D
@export_range(0.0, 1.0) var strength: float = .3
@export_range(4, 32) var blur_samples: int = 16
@export_range(0.0, 1.0) var smoothing: float = .9
var prev_pos := Vector3.ZERO
var prev_basis := Basis()
var current_blur := Vector2.ZERO  
var blur_overlay: ColorRect

func _ready() -> void:
	blur_overlay = ColorRect.new()
	blur_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blur_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	var mat = ShaderMaterial.new()
	mat.shader = load("res://motionblur.gdshader")
	mat.set_shader_parameter("samples", blur_samples)
	blur_overlay.material = mat
	
	var canvas = CanvasLayer.new()
	add_child(canvas)
	canvas.add_child(blur_overlay)
	
	prev_pos = global_position
	prev_basis = global_transform.basis

func _physics_process(delta) -> void:
	if delta <= 0: return
	
	var linear_vel = (global_position - prev_pos) / delta
	
	var delta_basis = prev_basis.inverse() * global_transform.basis
	var delta_quat = Quaternion(delta_basis)
	
	var angular_vel := Vector3.ZERO
	if abs(delta_quat.w) < 1.0:
		var half_angle = acos(clamp(delta_quat.w, -1.0, 1.0))
		if half_angle > 0.0001:
			var sin_half = sin(half_angle)
			angular_vel = Vector3(delta_quat.x, delta_quat.y, delta_quat.z) / sin_half * (2.0 * half_angle / delta)
	
	var local_vel = global_transform.basis.inverse() * linear_vel
	
	var raw_blur = Vector2(
		-angular_vel.y - local_vel.x,
		angular_vel.x + local_vel.y
	) * strength * delta
	

	var t = 1.0 - pow(smoothing, delta * 60.0)
	current_blur = current_blur.lerp(raw_blur, t)
	
	var mat = blur_overlay.material as ShaderMaterial
	mat.set_shader_parameter("blur_direction", current_blur)
	
	prev_pos = global_position
	prev_basis = global_transform.basis
