package hw_diagnostics

// build.sh and test.sh compile the shared UI shaders into this library before
// compiling the app; the renderer never compiles shader source at runtime.
UI_METALLIB :: #load("build/ui.metallib")
