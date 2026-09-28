extends Node
## Chooses a graphics preset by trying presets on the title's station
## backdrop, which uses the dive's renderer, lights and station. It starts at
## High and steps up while a preset keeps sixty frames a second with room to
## spare, or down until one does. Low is the floor; Classic is a look, not a
## fallback, and is never chosen here.
##
## The host applies each preset it is asked to try (trying) and stores the
## result (finished). Driven by _process, so freeing it stops it cleanly.
signal trying(preset: int)
signal finished(preset: int)

const Quality = preload("res://native/presentation/graphics_quality.gd")
## Time for pipelines to compile and the picture to settle after a change.
const SETTLE := 1.0
const MEASURE := 1.5
## A frame this long is a shader compiling, not a steady cost.
const HITCH := 0.12
const STEP_LIMIT := 8.0
## The dive adds the submarine, its lamps and beams, wildlife and the
## interface to what the title draws. Keep that much in hand.
const FRAME_BUDGET := 1.0/60.0
const RENDER_BUDGET_MS := 11.5

var preset := Quality.HIGH
var results := {}
var settled := 0.0
var spent := 0.0
var frames: Array=[]
var gpu: Array=[]
var cpu: Array=[]
var running := false

func begin() -> void:
	running=true;results.clear()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	start(Quality.HIGH)

func stop() -> void:
	running=false
	if is_inside_tree():RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),false)

func start(next: int) -> void:
	preset=next;settled=0.0;spent=0.0;frames.clear();gpu.clear();cpu.clear()
	trying.emit(preset)

func _process(delta: float) -> void:
	if not running:return
	spent+=delta
	if settled<SETTLE:
		# A hitch restarts the wait, up to the step's limit.
		settled=0.0 if delta>HITCH and spent<STEP_LIMIT*.5 else settled+delta
		return
	frames.append(delta)
	var viewport := get_viewport().get_viewport_rid()
	gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
	cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport))
	var measured := 0.0
	for value in frames:measured+=value
	if measured<MEASURE and spent<STEP_LIMIT:return
	var passed := fast_enough(frames,gpu,cpu)
	results[preset]=passed
	var next := preset+1 if passed else preset-1
	if next<Quality.LOW or next>Quality.VERY_HIGH or results.has(next):
		stop();finished.emit(best());return
	start(next)

func best() -> int:
	var found := Quality.LOW
	for level in results:
		if results[level]:found=maxi(found,level)
	return found

static func median(values: Array) -> float:
	if values.is_empty():return 0.0
	var sorted := values.duplicate();sorted.sort()
	return float(sorted[sorted.size()/2])

static func fast_enough(deltas: Array, gpu_ms: Array, cpu_ms: Array) -> bool:
	"""Sixty frames a second, and with the render-time queries a device has,
	room for the dive's own work on top. Where the GPU cannot report its
	time (some browsers), a steady sixty is the test."""
	if deltas.is_empty():return false
	var sorted := deltas.duplicate();sorted.sort()
	var typical: float=sorted[sorted.size()/2]
	var slow: float=sorted[int(sorted.size()*.9)]
	if typical>FRAME_BUDGET*1.06 or slow>FRAME_BUDGET*1.5:return false
	var render := maxf(median(gpu_ms),median(cpu_ms))
	return render<=RENDER_BUDGET_MS
