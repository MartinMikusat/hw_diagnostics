package hw_diagnostics

import "core:os"
import "core:testing"

SETTINGS_TEST_PATH :: "/tmp/hw_diagnostics-settings-test.json"

@(test)
settings_font_size_clamps_and_round_trips :: proc(t: ^testing.T) {
	testing.expect_value(t, settings_font_size_clamped(0), FONT_SIZE_MIN)
	testing.expect_value(t, settings_font_size_clamped(99), FONT_SIZE_MAX)
	testing.expect_value(t, settings_font_size_clamped(16), 16)

	_ = os.remove(SETTINGS_TEST_PATH)
	defer os.remove(SETTINGS_TEST_PATH)
	testing.expect(t, settings_save(SETTINGS_TEST_PATH, {font_size = 18, window = {10, 20, 600, 400}}))
	loaded := settings_defaults()
	testing.expect(t, settings_load(SETTINGS_TEST_PATH, &loaded))
	testing.expect_value(t, loaded.font_size, 18)
	testing.expect_value(t, loaded.window, Window_Frame{10, 20, 600, 400})
}

@(test)
settings_panel_hit_testing_separates_backdrop_from_controls :: proc(t: ^testing.T) {
	metrics := View_Metrics{width = 720, height = 480, char_advance = 8, row_height = 22}
	layout := view_settings_layout(metrics, metrics.row_height)

	hot, inside := view_settings_hot(layout, {layout.minus.x+1, layout.minus.y+1})
	testing.expect(t, inside)
	testing.expect_value(t, hot, Settings_Hot.Minus)

	hot, inside = view_settings_hot(layout, {layout.plus.x+1, layout.plus.y+1})
	testing.expect(t, inside)
	testing.expect_value(t, hot, Settings_Hot.Plus)

	_, inside = view_settings_hot(layout, {layout.panel.x+1, layout.panel.y+1})
	testing.expect(t, inside)

	_, inside = view_settings_hot(layout, {1, 1})
	testing.expect(t, !inside)
}
