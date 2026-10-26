extends CanvasLayer
## Autoload as "Transition".
## Drives the Universal Transition Shader (CC0, godotshaders.com) on a full-screen black rectangle.
##
##   await Transition.cover()    # screen closes to black
##   Transition.reveal()         # screen opens again
##
## Styles: "iris" (circle), "diamond", "clock", "fade"

const SHADER_PATH := "res://resources/shaders/transition.gdshader"   # change to where you saved the shader
const OPEN := 2.0    # shader `progress` value at which the screen is fully visible

var is_covered := false
var _rect: ColorRect
var _mat: ShaderMaterial
var _tween: Tween


func _ready() -> void:
	layer = 110   # above your UI and the NetSim overlay
	process_mode = Node.PROCESS_MODE_ALWAYS
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER_PATH)
	_rect = ColorRect.new()
	_rect.color = Color.BLACK
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.material = _mat
	_rect.hide()
	add_child(_rect)


func cover(style := "iris", duration := 0.5) -> void:
	if is_covered:
		return
	await _run(style, 1.0, 0.0, duration)
	is_covered = true


func reveal(style := "iris", duration := 0.5) -> void:
	is_covered = false
	await _run(style, 0.0, 1.0, duration)
	_rect.hide()


# t = 1.0 means "screen fully visible", t = 0.0 means "fully covered"
func _run(style: String, from_t: float, to_t: float, duration: float) -> void:
	if _tween and _tween.is_running():
		await _tween.finished
	_apply_style(style)
	_set_amount(from_t, style)
	_rect.show()   # while visible it also blocks mouse clicks on the UI below
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_method(_set_amount.bind(style), from_t, to_t, duration)
	await _tween.finished


func _set_amount(t: float, style: String) -> void:
	if style == "fade":
		_mat.set_shader_parameter("progress", 0.0)
		_rect.color = Color(0, 0, 0, 1.0 - t)
	else:
		_rect.color = Color.BLACK
		_mat.set_shader_parameter("progress", t * OPEN)


func _apply_style(style: String) -> void:
	_mat.set_shader_parameter("position", Vector2(0.5, 0.5))   # start from the screen centre
	_mat.set_shader_parameter("invert", style == "clock")      # the clock sweeps the other way
	match style:
		"iris":
			_mat.set_shader_parameter("transition_type", 2)    # Shape
			_mat.set_shader_parameter("edges", 64)             # many edges = a circle
			_mat.set_shader_parameter("shape_feather", 0.15)
		"diamond":
			_mat.set_shader_parameter("transition_type", 2)
			_mat.set_shader_parameter("edges", 4)
			_mat.set_shader_parameter("shape_feather", 0.15)
		"clock":
			_mat.set_shader_parameter("transition_type", 3)    # Clock
			_mat.set_shader_parameter("sectors", 1)
			_mat.set_shader_parameter("clock_feather", 0.4)
		_:  # "fade"
			_mat.set_shader_parameter("transition_type", 0)    # Basic
