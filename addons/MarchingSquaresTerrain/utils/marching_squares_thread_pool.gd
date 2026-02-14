extends Object
class_name MarchingSquaresThreadPool

var max_threads: int = 4
var threads: Array = []
var job_queue: Array = []

var queue_mutex := Mutex.new()
var running := false


func _init(p_max_threads := 4):
	max_threads = p_max_threads


func start():
	running = true
	for i in range(max_threads):
		var t := Thread.new()
		threads.append(t)
		t.start(_worker_loop)

func wait():
	for t in threads:
		if t.is_started():
			t.wait_to_finish()


func enqueue(job: Callable):
	if running:
		push_error("Can't enque on running pool")
		return
	queue_mutex.lock()
	job_queue.append(job)
	queue_mutex.unlock()


func _worker_loop():
	while running:
		queue_mutex.lock()
		if job_queue.size() == 0:
			running = false
			queue_mutex.unlock()
			break
		else:
			var job : Callable = job_queue.pop_front()
			queue_mutex.unlock()
			job.call()	
		
