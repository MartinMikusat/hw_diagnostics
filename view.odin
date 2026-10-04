package hw_diagnostics

import "core:fmt"
import coretext "ui_framework:coretext"
import ui "ui_framework:core"
import draw "ui_framework:draw"
import diag "diagnostics:."

SETTINGS_LABEL :: "[Settings]"
COLLECT_LABEL :: "[Collect report]"
MINUS_LABEL :: "[-]"
PLUS_LABEL :: "[+]"
SETTINGS_TITLE :: "Settings"
SETTINGS_HINT :: "the report is written to your Desktop · esc closes"

View_Metrics :: struct {
	width:        f32,
	height:       f32,
	char_advance: f32,
	row_height:   f32,
}

Settings_Hot :: enum {
	None,
	Minus,
	Plus,
}

Hot_State :: struct {
	control:         int,
	settings_button: bool,
	settings_hot:    Settings_Hot,
	collect:         bool,
	row:             int,
}

View_State :: struct {
	settings:      Settings,
	settings_open: bool,
	hot:           Hot_State,
	apps:          []diag.App_Info,
	selected:      int,
	message:       string,
	message_error: bool,
}

Settings_Layout :: struct {
	panel: draw.Rect,
	minus: draw.Rect,
	plus:  draw.Rect,
}

view_rect_draw :: proc(rect: draw.Rect, metrics: View_Metrics) -> draw.Rect {
	return {rect.x, metrics.height-rect.y-rect.h, rect.w, rect.h}
}

// The semaphore strip sits flush with the top-right corner, three cells each.
view_control_rect :: proc(index: int, metrics: View_Metrics) -> draw.Rect {
	height := min(metrics.row_height, CHROME_HEIGHT)
	cell := CONTROL_CELLS*metrics.char_advance
	x := metrics.width-(CONTROL_INSET_CELLS+f32(3-index)*CONTROL_CELLS)*metrics.char_advance
	return {x, (CHROME_HEIGHT-height)/2, cell, height}
}

view_control_at :: proc(point: ui.Vec2, metrics: View_Metrics) -> int {
	if point.y >= CHROME_HEIGHT {return -1}
	for index in 0 ..< 3 {
		rect := view_control_rect(index, metrics)
		if point.x >= rect.x && point.x < rect.x+rect.w && point.y >= rect.y && point.y < rect.y+rect.h {return index}
	}
	return -1
}

view_settings_rect :: proc(metrics: View_Metrics) -> draw.Rect {
	height := min(metrics.row_height, CHROME_HEIGHT)
	width := f32(len(SETTINGS_LABEL))*metrics.char_advance
	strip := (CONTROL_INSET_CELLS+3*CONTROL_CELLS)*metrics.char_advance
	x := metrics.width-strip-metrics.char_advance-width
	return {x, (CHROME_HEIGHT-height)/2, width, height}
}

view_settings_at :: proc(point: ui.Vec2, metrics: View_Metrics) -> bool {
	if point.y >= CHROME_HEIGHT {return false}
	rect := view_settings_rect(metrics)
	return point.x >= rect.x && point.x < rect.x+rect.w && point.y >= rect.y && point.y < rect.y+rect.h
}

view_list_top :: proc() -> f32 {
	return CHROME_HEIGHT+CHROME_HEIGHT/2
}

view_row_rect :: proc(index: int, metrics: View_Metrics) -> draw.Rect {
	return {0, view_list_top()+f32(index)*metrics.row_height, metrics.width, metrics.row_height}
}

view_row_at :: proc(point: ui.Vec2, metrics: View_Metrics, count: int) -> int {
	index := int((point.y-view_list_top())/metrics.row_height)
	if point.y < view_list_top() || index < 0 || index >= count {return -1}
	return index
}

view_collect_rect :: proc(metrics: View_Metrics) -> draw.Rect {
	width := f32(len(COLLECT_LABEL))*metrics.char_advance
	return {metrics.width-2*metrics.char_advance-width, metrics.height-2*metrics.row_height, width, metrics.row_height}
}

view_collect_at :: proc(point: ui.Vec2, metrics: View_Metrics) -> bool {
	rect := view_collect_rect(metrics)
	return point.x >= rect.x && point.x < rect.x+rect.w && point.y >= rect.y && point.y < rect.y+rect.h
}

view_settings_layout :: proc(metrics: View_Metrics, row_height: f32) -> Settings_Layout {
	ch := metrics.char_advance
	row := row_height
	pad := 2*ch
	width := min(f32(44)*ch, max(metrics.width-4*ch, 0))
	height := 5*row+2*pad
	panel := draw.Rect{(metrics.width-width)/2, (metrics.height-height)/2, width, height}
	right := panel.x+panel.w-pad
	button := 3*ch
	return {
		panel = panel,
		plus = {right-button, panel.y+2*pad+row, button, row},
		minus = {right-2*button-ch, panel.y+2*pad+row, button, row},
	}
}

view_rect_contains :: proc(rect: draw.Rect, point: ui.Vec2) -> bool {
	return point.x >= rect.x && point.x < rect.x+rect.w && point.y >= rect.y && point.y < rect.y+rect.h
}

view_settings_hot :: proc(layout: Settings_Layout, point: ui.Vec2) -> (Settings_Hot, bool) {
	if view_rect_contains(layout.minus, point) {return .Minus, true}
	if view_rect_contains(layout.plus, point) {return .Plus, true}
	if view_rect_contains(layout.panel, point) {return .None, true}
	return .None, false
}

view_draw_text :: proc(
	text: ^coretext.Context,
	list: ^draw.List,
	value: string,
	x, top, height: f32,
	size: f32,
	color: draw.Color,
	viewport_height: f32,
) {
	run := coretext.shape(text, FONT_MONO, value, size, text_tracking, 0, false)
	if run == nil {return}
	text_top := top+(height-(run.metrics.ascent+run.metrics.descent))/2
	origin := ui.Vec2{x, viewport_height-(text_top+run.metrics.ascent)}
	coretext.emit_shaped_run(text, list, run, origin, color, "")
}

view_draw_chrome :: proc(list: ^draw.List, text: ^coretext.Context, metrics: View_Metrics, state: View_State, font_size: f32) {
	settings := view_settings_rect(metrics)
	if state.hot.settings_button {draw.solid(list, view_rect_draw(settings, metrics), COLOR_TEXT, edge_softness = 0)}
	view_draw_text(text, list, SETTINGS_LABEL, settings.x, settings.y, settings.h, font_size, state.hot.settings_button ? COLOR_BACKGROUND : COLOR_TEXT, metrics.height)

	labels := [3]string{"_", "+", "x"}
	for index in 0 ..< 3 {
		rect := view_control_rect(index, metrics)
		inverted := index == state.hot.control
		if inverted {draw.solid(list, view_rect_draw(rect, metrics), COLOR_TEXT, edge_softness = 0)}
		color := inverted ? COLOR_BACKGROUND : COLOR_TEXT
		cell := rect.w/3
		view_draw_text(text, list, "[", rect.x, rect.y, rect.h, font_size, color, metrics.height)
		view_draw_text(text, list, labels[index], rect.x+cell, rect.y, rect.h, font_size, color, metrics.height)
		view_draw_text(text, list, "]", rect.x+2*cell, rect.y, rect.h, font_size, color, metrics.height)
	}

	title := "hw_diagnostics " + APP_VERSION
	view_draw_text(text, list, title, CONTROL_INSET_CELLS*metrics.char_advance, 0, CHROME_HEIGHT, font_size, COLOR_DIM, metrics.height)
}

view_draw_rows :: proc(list: ^draw.List, text: ^coretext.Context, metrics: View_Metrics, state: View_State, font_size: f32) {
	for app, index in state.apps {
		rect := view_row_rect(index, metrics)
		if rect.y > metrics.height-metrics.row_height*2 {break}
		selected := index == state.selected
		if selected || index == state.hot.row {
			draw.solid(list, view_rect_draw(rect, metrics), selected ? COLOR_SELECTED_ROW : COLOR_SELECTED_ROW, edge_softness = 0)
		}
		name := app.display
		label := app.version
		status := app.has_journal ? "logs" : "no logs"
		if len(name) == 0 {name = app.name}
		view_draw_text(text, list, name, metrics.char_advance, rect.y, rect.h, font_size, selected ? COLOR_SELECTED : COLOR_TEXT, metrics.height)
		status_x := metrics.width-metrics.char_advance-f32(len(status))*metrics.char_advance
		view_draw_text(text, list, status, status_x, rect.y, rect.h, font_size, app.has_journal ? COLOR_DIM : COLOR_RED, metrics.height)
		version_x := status_x-2*metrics.char_advance-f32(len(label))*metrics.char_advance
		view_draw_text(text, list, label, version_x, rect.y, rect.h, font_size, COLOR_DIM, metrics.height)
	}
	if len(state.apps) == 0 {
		view_draw_text(text, list, "no hw applications found in /Applications", metrics.char_advance, view_list_top(), metrics.row_height, font_size, COLOR_DIM, metrics.height)
	}
}

view_draw_bar :: proc(list: ^draw.List, text: ^coretext.Context, metrics: View_Metrics, state: View_State, font_size: f32) {
	collect := view_collect_rect(metrics)
	if state.hot.collect {draw.solid(list, view_rect_draw(collect, metrics), COLOR_TEXT, edge_softness = 0)}
	view_draw_text(text, list, COLLECT_LABEL, collect.x, collect.y, collect.h, font_size, state.hot.collect ? COLOR_BACKGROUND : COLOR_TEXT, metrics.height)
	if len(state.message) > 0 {
		view_draw_text(text, list, state.message, metrics.char_advance, metrics.height-metrics.row_height, metrics.row_height, font_size, state.message_error ? COLOR_RED : COLOR_DIM, metrics.height)
	}
}

view_draw_settings :: proc(list: ^draw.List, text: ^coretext.Context, metrics: View_Metrics, state: View_State, font_size: f32) {
	if !state.settings_open {return}
	layout := view_settings_layout(metrics, metrics.row_height)
	draw.solid(list, {0, 0, metrics.width, metrics.height}, COLOR_MODAL_BACKDROP, edge_softness = 0)
	draw.solid(list, view_rect_draw(layout.panel, metrics), COLOR_BACKGROUND, edge_softness = 0)
	pad := 2*metrics.char_advance
	view_draw_text(text, list, SETTINGS_TITLE, layout.panel.x+pad, layout.panel.y+pad, metrics.row_height, font_size, COLOR_TEXT, metrics.height)
	view_draw_text(text, list, fmt.tprintf("Font size: %d", state.settings.font_size), layout.panel.x+pad, layout.panel.y+pad+metrics.row_height, metrics.row_height, font_size, COLOR_TEXT, metrics.height)
	view_draw_text(text, list, SETTINGS_HINT, layout.panel.x+pad, layout.panel.y+pad+3*metrics.row_height, metrics.row_height, font_size, COLOR_DIM, metrics.height)
	for rect, index in ([2]draw.Rect{layout.minus, layout.plus}) {
		hot := state.hot.settings_hot == (index == 0 ? Settings_Hot.Minus : Settings_Hot.Plus)
		if hot {draw.solid(list, view_rect_draw(rect, metrics), COLOR_TEXT, edge_softness = 0)}
		label := index == 0 ? MINUS_LABEL : PLUS_LABEL
		view_draw_text(text, list, label, rect.x, rect.y, rect.h, font_size, hot ? COLOR_BACKGROUND : COLOR_TEXT, metrics.height)
	}
}

view_draw :: proc(
	list: ^draw.List,
	text: ^coretext.Context,
	metrics: View_Metrics,
	state: View_State,
	font_size: f32,
) {
	view_draw_chrome(list, text, metrics, state, font_size)
	view_draw_rows(list, text, metrics, state, font_size)
	view_draw_bar(list, text, metrics, state, font_size)
	view_draw_settings(list, text, metrics, state, font_size)
}
