package hw_diagnostics

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import QC "vendor:darwin/QuartzCore"
import devlog "devlog:."
import coretext "ui_framework:coretext"
import draw "ui_framework:draw"
import macos "ui_framework:macos"
import metal "ui_framework:metal"
import ui "ui_framework:core"
import diag "diagnostics:."

WINDOW_WIDTH :: NS.Float(720)
WINDOW_HEIGHT :: NS.Float(480)
WINDOW_MIN_WIDTH :: NS.Float(460)
WINDOW_MIN_HEIGHT :: NS.Float(280)
WINDOW_STYLE :: NS.WindowStyleMask{.Closable, .Miniaturizable, .Resizable}
MINIMIZE_STYLE :: NS.WindowStyleMask{.Titled, .Closable, .Miniaturizable, .Resizable}

CONTROL_MINIMIZE :: 0
CONTROL_ZOOM :: 1
CONTROL_CLOSE :: 2

MESSAGE_MAX :: 96
APP_PREFIX :: "com.halwayland."

Host :: struct {
	app:            ^NS.Application,
	delegate:       ^NS.Object,
	delegate_class: NS.Class,
	view_class:     NS.Class,
	window:         ^NS.Window,
	view:           ^NS.View,
	device:         ^MTL.Device,
	queue:          ^MTL.CommandQueue,
	layer:          ^QC.MetalLayer,
	display_link:   macos.Display_Link,
	text:           coretext.Context,
	renderer:       metal.Renderer,
	list:           draw.List,
	settings:       Settings,
	font_size:      f32,
	row_height:     f32,
	char_advance:   f32,
	view_width:     f32,
	view_height:    f32,
	settings_open:  bool,
	hot_control:    int,
	hot_settings_button: bool,
	hot_settings_hot:    Settings_Hot,
	hot_collect:    bool,
	hot_row:        int,
	apps:           []diag.App_Info,
	selected:       int,
	message:        [MESSAGE_MAX]u8,
	message_len:    int,
	message_error:  bool,
	frames_pending: int,
	initialized:    bool,
}

host: Host

register_mono_font :: proc(text: ^coretext.Context) {
	assert(font_register(), "embedded Iosevka must register; no silent substitute")
	coretext.register_font(text, FONT_MONO, FONT_NAME)
}

measure_char_advance :: proc(text: ^coretext.Context, font_size: f32) -> f32 {
	run := coretext.shape(text, FONT_MONO, "MMMMMMMMMM", font_size, text_tracking, 0, false)
	if run == nil {return font_size*0.6}
	return run.metrics.width/10
}

host_message :: proc(text: string, error: bool) {
	length := min(len(text), MESSAGE_MAX)
	copy(host.message[:length], text[:length])
	host.message_len = length
	host.message_error = error
}

host_failure :: proc(reason: string, severity := devlog.Severity.Error) {
	devlog.failed(devlog.global(), {feature = "presentation", operation = "window_host"}, {
		reason = reason,
		severity = severity,
	})
}

host_add_method :: proc(class: NS.Class, name: cstring, imp: rawptr, types: cstring) -> bool {
	return bool(NS.class_addMethod(class, NS.sel_registerName(name), auto_cast imp, types))
}

host_window_key :: proc "c" (self: NS.id, cmd: NS.SEL) -> bool {return true}

host_window_class :: proc() -> NS.Class {
	class := NS.objc_allocateClassPair(intrinsics.objc_find_class("NSWindow"), "DiagnosticsWindow", 0)
	if class == nil {return nil}
	if !host_add_method(class, "canBecomeKeyWindow", rawptr(host_window_key), "B@:") {return nil}
	if !host_add_method(class, "canBecomeMainWindow", rawptr(host_window_key), "B@:") {return nil}
	NS.objc_registerClassPair(class)
	return class
}

host_register_classes :: proc() -> (delegate_class, view_class: NS.Class, ok: bool) {
	delegate_class = NS.objc_allocateClassPair(intrinsics.objc_find_class("NSObject"), "DiagnosticsDelegate", 0)
	if delegate_class == nil {return nil, nil, false}
	if !host_add_method(delegate_class, "diagnosticsFrame:", rawptr(host_on_frame), "v@:@") {return nil, nil, false}
	if !host_add_method(delegate_class, "applicationShouldTerminateAfterLastWindowClosed:", rawptr(host_should_terminate), "B@:@") {return nil, nil, false}
	if !host_add_method(delegate_class, "applicationWillTerminate:", rawptr(host_persist_state), "v@:@") {return nil, nil, false}
	if !host_add_method(delegate_class, "diagnosticsUpdateReady:", rawptr(host_update_ready), "v@:@") {return nil, nil, false}
	if !host_add_method(delegate_class, "windowDidResize:", rawptr(host_surface_changed), "v@:@") {return nil, nil, false}
	if !host_add_method(delegate_class, "windowDidChangeBackingProperties:", rawptr(host_surface_changed), "v@:@") {return nil, nil, false}
	if !host_add_method(delegate_class, "windowDidChangeScreen:", rawptr(host_surface_changed), "v@:@") {return nil, nil, false}
	NS.objc_registerClassPair(delegate_class)

	view_class = NS.objc_allocateClassPair(intrinsics.objc_find_class("NSView"), "DiagnosticsView", 0)
	if view_class == nil {return delegate_class, nil, false}
	if !host_add_method(view_class, "acceptsFirstResponder", rawptr(host_accepts_first), "B@:") {return delegate_class, view_class, false}
	if !host_add_method(view_class, "mouseDown:", rawptr(host_mouse_down), "v@:@") {return delegate_class, view_class, false}
	if !host_add_method(view_class, "mouseMoved:", rawptr(host_mouse_moved), "v@:@") {return delegate_class, view_class, false}
	if !host_add_method(view_class, "keyDown:", rawptr(host_key_down), "v@:@") {return delegate_class, view_class, false}
	NS.objc_registerClassPair(view_class)
	return delegate_class, view_class, true
}

host_initialize :: proc() -> bool {
	coretext.context_init(&host.text)
	draw.list_init(&host.list, pixel_ratio = 2)
	register_mono_font(&host.text)

	delegate_class, view_class, ok := host_register_classes()
	if !ok {
		fmt.eprintln("[hw_diagnostics] could not register the Cocoa classes")
		host_failure("Cocoa classes could not be registered", .Critical)
		return false
	}
	host.delegate_class = delegate_class
	host.view_class = view_class
	delegate := NS.class_createInstance(delegate_class, 0)
	host.delegate = NS.init((^NS.Object)(delegate))

	host.app = NS.Application.sharedApplication()
	host.app->setActivationPolicy(.Regular)
	host.app->setDelegate((^NS.ApplicationDelegate)(host.delegate))

	host.settings = settings_defaults()
	_ = settings_load(settings_path(context.temp_allocator), &host.settings)
	host.font_size = f32(host.settings.font_size)
	host.row_height = row_height_for(host.font_size, ROW_HEIGHT_RATIO)
	host.selected = 0
	host.hot_row = -1

	frame := NS.Rect{{200, 200}, {WINDOW_WIDTH, WINDOW_HEIGHT}}
	restored := false
	if saved := host.settings.window; NS.Float(saved.w) >= WINDOW_MIN_WIDTH && NS.Float(saved.h) >= WINDOW_MIN_HEIGHT && saved.w < 10000 && saved.h < 10000 {
		frame = {{NS.Float(saved.x), NS.Float(saved.y)}, {NS.Float(saved.w), NS.Float(saved.h)}}
		restored = true
	}
	window_class := host_window_class()
	if window_class == nil {
		host_failure("window class could not be registered", .Critical)
		return false
	}
	host.window = (^NS.Window)(NS.class_createInstance(window_class, 0))
	host.window = host.window->initWithContentRect(frame, WINDOW_STYLE, .Buffered, false)
	if host.window == nil {
		host_failure("window could not be created", .Critical)
		return false
	}
	host.window->setMinSize({WINDOW_MIN_WIDTH, WINDOW_MIN_HEIGHT})
	host.window->setAcceptsMouseMovedEvents(true)
	host.window->setDelegate((^NS.WindowDelegate)(host.delegate))
	if !restored {host.window->center()}

	host.view = (^NS.View)(NS.class_createInstance(view_class, 0))
	host.view = host.view->initWithFrame({{0, 0}, frame.size})
	host.window->setContentView(host.view)

	host.device = MTL.CreateSystemDefaultDevice()
	if host.device == nil {
		host_failure("Metal device is unavailable", .Critical)
		return false
	}
	host.queue = host.device->newCommandQueue()
	host.layer = QC.MetalLayer.layer()
	host.layer->setDevice(host.device)
	host.layer->setPixelFormat(.BGRA8Unorm)
	host.layer->setFramebufferOnly(true)
	host.view->setWantsLayer(true)
	host.view->setLayer((^NS.Layer)(host.layer))

	if !metal.renderer_init(
		&host.renderer,
		rawptr(host.device),
		pixel_format = uint(MTL.PixelFormat.BGRA8Unorm),
		metallib_data = UI_METALLIB,
	) {
		host_failure("Metal renderer initialization failed", .Critical)
		return false
	}
	if !macos.display_link_start(
		&host.display_link,
		rawptr(host.view),
		rawptr(host.delegate),
		"diagnosticsFrame:",
	) {
		host_failure("the macOS 14 display link API is unavailable", .Critical)
		return false
	}
	_ = host.window->makeFirstResponder((^NS.Responder)(host.view))

	host.apps = diag.app_scan(APP_PREFIX)
	update_start()
	host.initialized = true
	host.window->makeKeyAndOrderFront(nil)
	host.app->activateIgnoringOtherApps(true)
	host_request_frames(3)
	return true
}

host_shutdown :: proc() {
	if !host.initialized {return}
	diag.app_info_destroy(host.apps)
	host.apps = nil
	macos.display_link_stop(&host.display_link)
	metal.renderer_destroy(&host.renderer)
	draw.list_destroy(&host.list)
	coretext.context_destroy(&host.text)
	if host.view != nil {NS.release(host.view)}
	if host.window != nil {NS.release(host.window)}
	if host.delegate != nil {NS.release(host.delegate)}
	host = {}
}

host_request_frames :: proc(count: int) {
	if !host.initialized {return}
	host.frames_pending = max(host.frames_pending, count)
	if host.display_link.paused {macos.display_link_set_paused(&host.display_link, false)}
}

host_capture_window_frame :: proc() {
	if host.window == nil {return}
	frame := host.window->frame()
	host.settings.window = {f32(frame.origin.x), f32(frame.origin.y), f32(frame.size.width), f32(frame.size.height)}
}

host_view_state :: proc() -> View_State {
	return View_State{
		settings = host.settings,
		settings_open = host.settings_open,
		hot = {
			control = host.hot_control,
			settings_button = host.hot_settings_button,
			settings_hot = host.hot_settings_hot,
			collect = host.hot_collect,
			row = host.hot_row,
		},
		apps = host.apps,
		selected = host.selected,
		message = host_status_message(),
		message_error = host.message_error,
	}
}

host_status_message :: proc() -> string {
	if host.message_len > 0 {return string(host.message[:host.message_len])}
	if update_ready() {return "an update will install when you quit"}
	return ""
}

host_render :: proc() {
	if host.window == nil || host.view == nil || host.layer == nil {return}
	pool := NS.scoped_autoreleasepool()
	_ = pool
	bounds := host.view->bounds()
	width := f32(bounds.size.width)
	height := f32(bounds.size.height)
	if width < 1 || height < 1 {return}
	host.view_width = width
	host.view_height = height
	scale := f32(host.window->backingScaleFactor())
	if scale < 1 {scale = 1}
	host.layer->setContentsScale(NS.Float(scale))
	host.layer->setDrawableSize({NS.Float(width)*NS.Float(scale), NS.Float(height)*NS.Float(scale)})

	drawable := host.layer->nextDrawable()
	if drawable == nil {return}
	texture := drawable->texture()
	command_buffer := host.queue->commandBuffer()

	metal.begin_texture_frame(&host.renderer)
	coretext.begin_frame(&host.text, scale, metal.atlas_io(&host.renderer))
	draw.list_reset(&host.list)
	host.char_advance = measure_char_advance(&host.text, host.font_size)
	metrics := View_Metrics{width = width, height = height, char_advance = host.char_advance, row_height = host.row_height}
	view_draw(&host.list, &host.text, metrics, host_view_state(), host.font_size)
	coretext.flush(&host.text)
	if !metal.encode_to_drawable(&host.renderer, rawptr(command_buffer), rawptr(texture), &host.list, {width, height}, scale, COLOR_BACKGROUND) {
		devlog.failed(devlog.global(), {feature = "presentation", operation = "frame"}, {reason = "Metal rendering failed", severity = .Critical})
		return
	}
	command_buffer->presentDrawable((^MTL.Drawable)(drawable))
	command_buffer->commit()
}

host_pointer_from_event :: proc(event: ^NS.Event) -> ui.Vec2 {
	point := host.view->convertPointFromView(event->locationInWindow(), nil)
	return {f32(point.x), host.view_height-f32(point.y)}
}

host_update_hover :: proc(point: ui.Vec2) {
	if host.view_width < 1 || host.view_height < 1 {return}
	metrics := View_Metrics{width = host.view_width, height = host.view_height, char_advance = host.char_advance, row_height = host.row_height}
	control := -1
	settings_button := false
	settings_hot := Settings_Hot.None
	collect := false
	row := -1
	if host.settings_open {
		settings_hot, _ = view_settings_hot(view_settings_layout(metrics, host.row_height), point)
	} else {
		control = view_control_at(point, metrics)
		if control < 0 {settings_button = view_settings_at(point, metrics)}
		if control < 0 && !settings_button {collect = view_collect_at(point, metrics)}
		if control < 0 && !settings_button && !collect {row = view_row_at(point, metrics, len(host.apps))}
	}
	if control == host.hot_control && settings_button == host.hot_settings_button && settings_hot == host.hot_settings_hot && collect == host.hot_collect && row == host.hot_row {return}
	host.hot_control = control
	host.hot_settings_button = settings_button
	host.hot_settings_hot = settings_hot
	host.hot_collect = collect
	host.hot_row = row
	host_request_frames(1)
}

host_apply_control :: proc(index: int) {
	switch index {
	case CONTROL_CLOSE:   host.window->close()
	case CONTROL_ZOOM:    intrinsics.objc_send(nil, host.window, "zoom:", NS.id(nil))
	case CONTROL_MINIMIZE:
		host.window->setStyleMask(MINIMIZE_STYLE)
		intrinsics.objc_send(nil, host.window, "miniaturize:", NS.id(nil))
		host.window->setStyleMask(WINDOW_STYLE)
	}
}

host_settings_adjust :: proc(delta: int) {
	next := settings_font_size_clamped(host.settings.font_size+delta)
	if next == host.settings.font_size {return}
	host.settings.font_size = next
	host.font_size = f32(next)
	host.row_height = row_height_for(host.font_size, ROW_HEIGHT_RATIO)
	_ = settings_save(settings_path(context.temp_allocator), host.settings)
	host_request_frames(2)
}

// host_collect writes the selected app's report and reveals it.
host_collect :: proc() {
	if host.selected < 0 || host.selected >= len(host.apps) {
		host_message("select an application first", true)
		host_request_frames(2)
		return
	}
	app := host.apps[host.selected]
	site := devlog.Site{feature = "diagnostics", operation = "collect"}
	devlog.started(devlog.global(), site, {file_id = app.name})
	config := diag.Config{app_name = app.name, display_name = app.display, bundle_id = app.bundle_id, version = app.version}
	path := diag.report_default_path(config, context.allocator)
	defer delete(path, context.allocator)
	if diag.report_write_file(config, path) {
		diag.reveal_path(path)
		devlog.succeeded(devlog.global(), site, {file_id = app.name})
		host_message("report written to your Desktop", false)
	} else {
		devlog.failed(devlog.global(), site, {reason = "report could not be written"}, {file_id = app.name})
		host_message("the report could not be written", true)
	}
	host_request_frames(2)
}

host_open_settings :: proc() {
	host.settings_open = true
	host_request_frames(2)
}

host_close_settings :: proc() {
	host.settings_open = false
	host_request_frames(1)
}

host_persist_state :: proc "c" (self: NS.id, cmd: NS.SEL, notification: ^NS.Notification) {
	context = runtime.default_context()
	host_capture_window_frame()
	_ = settings_save(settings_path(context.temp_allocator), host.settings)
	update_finish()
}

host_update_ready :: proc "c" (self: NS.id, cmd: NS.SEL, object: NS.id) {
	context = runtime.default_context()
	host_request_frames(2)
}

host_on_frame :: proc "c" (self: NS.id, cmd: NS.SEL, timer: NS.id) {
	context = runtime.default_context()
	if host.frames_pending <= 0 {
		macos.display_link_set_paused(&host.display_link, true)
		return
	}
	host.frames_pending -= 1
	host_render()
	free_all(context.temp_allocator)
	if host.frames_pending <= 0 {macos.display_link_set_paused(&host.display_link, true)}
}

host_surface_changed :: proc "c" (self: NS.id, cmd: NS.SEL, notification: ^NS.Notification) {
	context = runtime.default_context()
	host_request_frames(2)
}

host_accepts_first :: proc "c" (self: NS.id, cmd: NS.SEL) -> bool {return true}

host_should_terminate :: proc "c" (self: NS.id, cmd: NS.SEL, sender: ^NS.Application) -> bool {return true}

host_mouse_down :: proc "c" (self: NS.id, cmd: NS.SEL, event: ^NS.Event) {
	context = runtime.default_context()
	if host.view_width < 1 || host.view_height < 1 {return}
	point := host_pointer_from_event(event)
	metrics := View_Metrics{width = host.view_width, height = host.view_height, char_advance = host.char_advance, row_height = host.row_height}
	if host.settings_open {
		hot, inside := view_settings_hot(view_settings_layout(metrics, host.row_height), point)
		if !inside {
			host_close_settings()
		} else if hot == .Minus {
			host_settings_adjust(-1)
		} else if hot == .Plus {
			host_settings_adjust(1)
		}
		return
	}
	if control := view_control_at(point, metrics); control >= 0 {
		host_apply_control(control)
		return
	}
	if view_settings_at(point, metrics) {
		host_open_settings()
		return
	}
	if view_collect_at(point, metrics) {
		host_collect()
		return
	}
	if row := view_row_at(point, metrics, len(host.apps)); row >= 0 {
		host.selected = row
		host_request_frames(2)
	}
}

host_mouse_moved :: proc "c" (self: NS.id, cmd: NS.SEL, event: ^NS.Event) {
	context = runtime.default_context()
	host_update_hover(host_pointer_from_event(event))
}

host_key_down :: proc "c" (self: NS.id, cmd: NS.SEL, event: ^NS.Event) {
	context = runtime.default_context()
	command := .Command in event->modifierFlags()
	key := uint(event->keyCode())
	if command && key == 13 {host.window->close(); return}
	if command && key == 12 {host.app->terminate(nil); return}
	if command && key == 43 {
		if host.settings_open {host_close_settings()} else {host_open_settings()}
		return
	}
	if host.settings_open {
		if key == 53 {host_close_settings()}
		return
	}
	switch {
	case key == 53:
		return
	case key == 126:
		if len(host.apps) > 0 {host.selected = clamp(host.selected-1, 0, len(host.apps)-1)}
	case key == 125:
		if len(host.apps) > 0 {host.selected = clamp(host.selected+1, 0, len(host.apps)-1)}
	case key == 36, key == 76:
		host_collect()
		return
	}
	host_request_frames(2)
}

host_run :: proc() -> bool {
	if !host_initialize() {return false}
	defer host_shutdown()
	devlog.started(devlog.global(), {feature = "app", operation = "presentation"})
	host.app->run()
	devlog.stopped(devlog.global(), {feature = "app", operation = "presentation"})
	return true
}
