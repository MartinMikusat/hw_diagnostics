package hw_diagnostics

import "core:fmt"
import "core:os"
import devlog "devlog:."

app_exit :: proc(status: int) {
	devlog.global_destroy()
	os.exit(status)
}

main :: proc() {
	config := devlog.DEFAULT_CONFIG
	config.profile = devlog.profile_from_env()
	if devlog.global_start(devlog.default_directory("hw_diagnostics", "app", context.temp_allocator), config) {
		context.assertion_failure_proc = devlog.fatal_hook()
	} else {
		fmt.eprintln("[hw_diagnostics] could not initialize the operation journal")
	}
	defer devlog.global_destroy()
	devlog.started(devlog.global(), {feature = "app", operation = "startup"}, {
		stage = config.profile == .Dev ? "profile_dev" : "profile_prod",
	})

	if len(os.args) > 1 && os.args[1] == "--offscreen" {
		if !run_offscreen(os.args[2:]) {
			devlog.failed(devlog.global(), {feature = "app", operation = "render_offscreen"}, {
				reason = "offscreen render failed",
			})
			fmt.eprintln("usage: hw_diagnostics --offscreen <path.ppm> [--width=N] [--height=N] [--scale=N] [--font-size=N] [--settings]")
			app_exit(2)
		}
		devlog.succeeded(devlog.global(), {feature = "app", operation = "render_offscreen"})
		return
	}
	if !host_run() {
		devlog.failed(devlog.global(), {feature = "app", operation = "presentation"}, {
			reason = "window host initialization failed",
			severity = .Critical,
		})
		fmt.eprintln("[hw_diagnostics] startup failed")
		app_exit(1)
	}
}
