extends Control


@export var padding := Vector2(10, 10)
@export var max_display_ms := 150.0

var frame_times : Array[float] = []

var avg_ms := 0.0
var min_ms := 0.0
var max_ms := 0.0


func set_frame_times(times: Array[float]) -> void:
	frame_times = times
	_recalculate_stats()
	queue_redraw()


func _recalculate_stats() -> void:
	if frame_times.is_empty():
		avg_ms = 0.0
		min_ms = 0.0
		max_ms = 0.0
		return
	
	var sum := 0.0
	min_ms = INF
	max_ms = -INF
	
	for t in frame_times:
		var ms := t * 1000.0
		sum += ms
		min_ms = min(min_ms, ms)
		max_ms = max(max_ms, ms)
	
	avg_ms = sum / frame_times.size()


func _draw() -> void:
	if frame_times.size() < 2:
		return
	
	var origin := padding
	
	draw_rect(Rect2(origin, size), Color(0, 0, 0, 0.4), true)
	draw_rect(Rect2(origin, size), Color(1, 1, 1, 0.2), false)
	
	var scale_max_ms : float = min(max_ms, max_display_ms)
	scale_max_ms = max(scale_max_ms, 1.0)
	
	var step_x := size.x / float(frame_times.size() - 1)
	
	var prev_point: Vector2
	
	for i in range(frame_times.size()):
		var ms := frame_times[i] * 1000.0
		var v : float = clamp(ms / scale_max_ms, 0.0, 1.0)
		
		var x := origin.x + i * step_x
		var y := origin.y + size.y * (1.0 - v)
		var p := Vector2(x, y)
		
		if i > 0:
			draw_line(prev_point, p, Color.GREEN, 2.0)
		
		prev_point = p
	
	var avg_v : float = clamp(avg_ms / scale_max_ms, 0.0, 1.0)
	var avg_y : float = origin.y + size.y * (1.0 - avg_v)
	
	draw_line(
		Vector2(origin.x, avg_y),
		Vector2(origin.x + size.x, avg_y),
		Color.YELLOW,
		1.5
	)
	
	_draw_label(
		Vector2(origin.x + size.x + 6, avg_y),
		"Avg: %d ms" % int(round(avg_ms)),
		Color.YELLOW
	)
	
	var min_i := 0
	var max_i := 0
	for i in range(frame_times.size()):
		var ms := frame_times[i] * 1000.0
		if ms == min_ms:
			min_i = i
		if ms == max_ms:
			max_i = i
	
	_draw_point_label(min_i, min_ms, "Min")
	_draw_point_label(max_i, max_ms, "Max")


func _draw_point_label(i: int, ms: float, prefix: String) -> void:
	var origin := padding
	var step_x := size.x / float(frame_times.size() - 1)
	
	var scale_max_ms : float = min(max_ms, max_display_ms)
	scale_max_ms = max(scale_max_ms, 1.0)
	
	var v : float = clamp(ms / scale_max_ms, 0.0, 1.0)
	var x := origin.x + i * step_x
	var y : float = origin.y + size.y * (1.0 - v)
	
	draw_circle(Vector2(x, y), 3.0, Color.WHITE)
	
	_draw_label(
		Vector2(x + 4, y - 4),
		"%s: %d ms" % [prefix, int(round(ms))],
		Color.WHITE
	)


func _draw_label(pos: Vector2, text: String, color: Color) -> void:
	var font := get_theme_default_font()
	if font:
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
