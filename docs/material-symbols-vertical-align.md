# Material Symbols icons need vertical-align

Material Symbols (`span.material-symbols`) icons are a font-based icon set. When placed inline next to text, they sit on the text baseline and appear misaligned (shifted up or down).

## Why

The Material Symbols font has different metrics than the body text font. Without explicit alignment, the icon's baseline doesn't match the text's visual center.

## Rule

Whenever placing a `.material-symbols` icon inline with text, ensure `vertical-align: middle` is set — either via a shared class (like `.resource-icon`) or directly.

If using **flexbox** with `align-items: center`, `vertical-align` isn't needed — flex alignment handles it. Examples: `.card-title` uses flex (`.d-flex.align-items-center`), so icons there are fine without it.

Check alignment visually after adding icons to any new context (dl lists, badges, card titles, table cells, etc.).
