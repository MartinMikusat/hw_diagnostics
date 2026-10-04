package hw_diagnostics

import ui "ui_framework:core"
import draw "ui_framework:draw"

FONT_MONO :: ui.Font_Handle(1)

DEFAULT_FONT_SIZE :: 14
FONT_SIZE_MIN :: 12
FONT_SIZE_MAX :: 24
ROW_HEIGHT_RATIO :: f32(22.0/14.0)
CHROME_HEIGHT :: f32(28)
CONTROL_INSET_CELLS :: f32(1)
CONTROL_CELLS :: f32(3)

COLOR_BACKGROUND     :: draw.Color{0.043, 0.043, 0.051, 1.0}
COLOR_TEXT           :: draw.Color{0.855, 0.855, 0.871, 1.0}
COLOR_DIM            :: draw.Color{0.510, 0.510, 0.541, 1.0}
COLOR_SELECTED       :: draw.Color{1.0, 1.0, 1.0, 1.0}
COLOR_SELECTED_ROW   :: draw.Color{0.102, 0.125, 0.180, 1.0}
COLOR_MODAL_BACKDROP :: draw.Color{0.0, 0.0, 0.0, 0.35}
COLOR_RED            :: draw.Color{1.0, 0.230, 0.230, 1.0}

row_height_for :: proc(font_size, ratio: f32) -> f32 {
	return font_size*ratio
}

// text_tracking is the letter spacing the cell width is measured with, so
// columns stay aligned.
text_tracking: f32
