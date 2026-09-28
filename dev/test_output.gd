class_name TestOutput
extends RefCounted

## How loud the test suites are.
##
## `-- --brief` after any suite: passing checks print nothing, reports print
## only when something fails, and each suite ends with its one-line total. The
## full run of every suite then reads in a few dozen lines instead of a few
## thousand -- which is what the person (or the model) reading it can afford.
##
## `dev/run_tests.sh` runs everything this way, in parallel.

static var brief: bool = OS.get_cmdline_user_args().has("--brief")


## A check's line: always for a failure, and for a pass unless brief.
static func check_line(ok: bool, message: String) -> void:
	if ok and brief:
		return
	print("%s: %s" % ["PASS" if ok else "FAIL", message])


## Detail worth reading only when not brief.
static func detail(text: String) -> void:
	if not brief:
		print(text)
