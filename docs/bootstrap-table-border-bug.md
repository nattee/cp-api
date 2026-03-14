# Bootstrap $table-border-color has no effect on cell borders

## The bug

Setting `$table-border-color` in Bootstrap 5 compiles into `--bs-table-border-color` on `.table`, but cells never read that variable. CSS `border-color` is **not an inherited property**, so cells default to `currentColor` (text color), ignoring the table-level variable entirely.

## Workaround

Define custom Sass variables and apply them directly to cells in post-import CSS rules:

```scss
$table-row-border-color:  rgba(white, 0.08);
$table-head-border-color: rgba(white, 0.2);
$table-head-border-width: 2px;

.card .table > :not(caption) > * > * { border-color: $table-row-border-color; }
.card .table > thead > tr > * { border-bottom-color: $table-head-border-color; border-bottom-width: $table-head-border-width; }
```

This also gives us distinct header vs row borders, which Bootstrap doesn't support natively.
