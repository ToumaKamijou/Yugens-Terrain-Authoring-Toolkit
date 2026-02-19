extends Object
class_name MarchingSquaresThreadPool

var max_threads: int = 4
var job_queue: Array = []

var task_id := -1

func _init(p_max_threads := 4):
	max_threads = p_max_threads


func start():
	if task_id != -1:
		push_error("Already running")
		return
	task_id = WorkerThreadPool.add_group_task(_worker_loop, job_queue.size())


func wait():
	WorkerThreadPool.wait_for_group_task_completion(task_id)

func enqueue(job: Callable):
	if task_id != -1:
		push_error("Can't enque on running pool")
		return
	job_queue.append(job)

func _worker_loop(i: int):
	job_queue[i].call()
