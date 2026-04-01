# shadcn Color Mapping

Color palette is generated with [shadcn themes](https://shadcnthemes.app/generator) and mapped to Bootstrap Sass variables in `application.scss`.

## How to update the palette

1. Export the `.dark { ... }` block from the shadcn generator
2. Convert oklch values to hex using the Ruby script at the bottom of this doc
3. Update the Sass variables in `application.scss` (lines 1-40). Pay attention to:
   - **`$dark`** and **`$body-bg-dark`**: both must be set to the `--background` value. Bootstrap uses `$body-bg-dark` (not `$body-bg`) in dark mode — without it, the page background falls back to Bootstrap's default `#212529`.
   - **`$card-bg`**: if `--card` has an alpha (e.g. `/ 0.6`), use `rgba(<hex>, 0.6)`. If no alpha, use the hex directly.
   - **`$popover-bg`**: always the opaque hex from `--popover` (same base color as card, no alpha).
   - **`$body-tertiary-bg-dark`**: set from `--sidebar`. If sidebar = background, the sidebar border (`#sidebar { border-right }`) provides visual separation.
4. Update hardcoded RGB values in `chart_controller.js` and `_week_calendar.html.haml`
5. Run `bin/rails dartsass:build` and verify at `/dev/styleguide`

## Variable mapping

### Direct from palette (update these when switching palettes)

| shadcn variable | Sass variable | Usage |
|---|---|---|
| `--background` | `$dark`, `$body-bg-dark`, `$body-bg` | Page background. `$body-bg-dark` is what Bootstrap actually uses in dark mode. |
| `--foreground` | `$body-color-dark` | Body text color |
| `--card` | `$card-bg` | Card surfaces. Extract alpha if present (e.g. `/ 0.6` → `rgba(hex, 0.6)`) |
| `--popover` | `$popover-bg` | Opaque card color for floating surfaces |
| `--primary` | `$primary` | Main accent color |
| `--primary-light` | `$light` | Card titles, Flatpickr headers, accents |
| `--destructive` | `$danger` | Error/delete states |
| `--chart-1` | `$secondary` | Pink — badges, buttons |
| `--chart-2` | `$info` | Purple — badges, buttons |
| `--chart-3` | `$success` | Green — badges, flash messages |
| `--chart-4` | `$warning` | Gold — badges, flash messages |
| `--sidebar` | `$body-tertiary-bg-dark` | Sidebar background (Bootstrap's `.bg-body-tertiary`) |
| `--sidebar-border` | `#sidebar { border-right }` | Sidebar right border (especially when sidebar = background) |

### Where `$popover-bg` is used

| Location | Selector | Why opaque |
|---|---|---|
| Select2 dropdown | `.select2-container--bootstrap-5 .select2-dropdown` | Dropdown floats over content |
| Help popovers | `.help-popover-content` | Popover floats over form fields |
| Flatpickr calendar | `.flatpickr-calendar` | Calendar floats over page |

### Not mapped (shadcn-specific, no Bootstrap equivalent)

| shadcn variable | Reason |
|---|---|
| `--secondary` | White@10% subtle highlight — not our `$secondary` |
| `--muted` / `--accent` | No direct Sass var; Bootstrap uses `var(--bs-secondary-color)` |
| `--ring` | Same as primary; Bootstrap handles focus rings |
| `--input` | Input **border** in shadcn, not background. Our `$input-bg` is `lighten($dark, 2%)` |
| `--*-foreground` | Text-on-color pairs — Bootstrap's contrast system handles this |
| `--chart-5` | Used in chart/calendar palette arrays, not a theme color variable |
| `--radius`, `--font-*` | We use Bootstrap defaults for these |

### Derived (auto-cascade when `$dark` changes)

| Sass variable | Derivation |
|---|---|
| `$input-bg` | `lighten($dark, 2%)` |
| `$input-group-addon-bg` | `lighten($dark, 1%)` |
| `$input-icon-color` | `darken($light, 5%)` |
| Flatpickr hover bg | `lighten($dark, 14%)` |

### Hardcoded colors (update separately)

| File | What | Uses |
|---|---|---|
| `chart_controller.js` | `STACK_COLORS` | RGB of `$light`, `$primary`, `$secondary`, `$success`, `$warning` |
| `chart_controller.js` | `TICK_COLOR` | Same as `$body-color-dark` |
| `chart_controller.js` | Histogram colors | RGB of `$primary` |
| `_week_calendar.html.haml` | `palette` array | RGB of theme colors + chart-5 |

### Badge text colors

Badges use theme colors directly (e.g. `color: $primary`) without `lighten()` or `saturate()`, since the shadcn palette colors are bright enough for text on `rgba($color, 0.2)` backgrounds. Grade badges use their own independent `$grade-*` variables.

## Bootstrap dark mode gotcha

Bootstrap 5.3 has separate Sass variables for dark mode (suffixed `-dark`). In `[data-bs-theme="dark"]`, Bootstrap sets CSS variables from the `-dark` variants, ignoring the base variants:

| What you'd expect | What Bootstrap actually uses in dark mode |
|---|---|
| `$body-bg` | `$body-bg-dark` |
| `$body-color` | `$body-color-dark` |
| `$body-tertiary-bg` | `$body-tertiary-bg-dark` |

Always override the `-dark` variant. Setting `$body-bg` alone has no effect in dark mode.

## oklch to hex conversion script

```ruby
def oklch_to_hex(l, c, h)
  h_rad = h * Math::PI / 180.0
  a = c * Math.cos(h_rad)
  b = c * Math.sin(h_rad)
  l_ = l + 0.3963377774 * a + 0.2158037573 * b
  m_ = l - 0.1055613458 * a - 0.0638541728 * b
  s_ = l - 0.0894841775 * a - 1.2914855480 * b
  l3 = l_ ** 3; m3 = m_ ** 3; s3 = s_ ** 3
  r_lin =  4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3
  g_lin = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3
  b_lin = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3
  [r_lin, g_lin, b_lin].map { |c_lin|
    c_lin = c_lin.clamp(0.0, 1.0)
    c_lin <= 0.0031308 ? (12.92 * c_lin * 255).round : ((1.055 * (c_lin ** (1.0/2.4)) - 0.055) * 255).round
  }.then { |r, g, b| "#%02x%02x%02x" % [r, g, b] }
end
```

Usage: `ruby -e "... puts oklch_to_hex(0.828, 0.111, 230.318)"`
