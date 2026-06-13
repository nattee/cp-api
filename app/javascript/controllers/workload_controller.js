import { Controller } from "@hotwired/stimulus"

// Drives the metric toggle on the Staff Workload matrix.
//
// The body cells carry every metric as data attributes
// (data-credits/-sections/-courses/-hours). Toggling a metric:
//   1. swaps each cell's displayed value (and its data-order for sorting),
//   2. recolors the heatmap relative to that metric's max across the table,
//   3. highlights the matching Σ total column,
//   4. re-sorts the DataTable so body-column sorts reflect the active metric.
//
// The Σ total columns are static native DataTable columns and stay sortable
// regardless of the toggle — this controller never touches them except to
// add/remove the active-column highlight. Lives on the same element as the
// `datatable` controller (data-controller="datatable workload") so it can
// reach the DataTable instance to invalidate/redraw.
export default class extends Controller {
  static values = { defaultMetric: { type: String, default: "credits" } }

  static METRICS = ["credits", "sections", "courses", "hours"]

  connect() {
    this.cells = Array.from(this.element.querySelectorAll("[data-wl-cell]"))
    this.maxes = this.computeMaxes()
    this.apply(this.defaultMetricValue)
  }

  // data-action="change->workload#switch"
  switch(event) {
    this.apply(event.target.value)
  }

  apply(metric) {
    if (!this.constructor.METRICS.includes(metric)) return
    const max = this.maxes[metric] || 0

    this.cells.forEach(cell => {
      const empty = cell.hasAttribute("data-wl-empty")
      const value = parseFloat(cell.dataset[metric] || "0")
      const text = empty ? "—" : this.format(value)

      const link = cell.querySelector("a")
      if (link) link.textContent = text
      else cell.textContent = text

      cell.dataset.order = empty ? 0 : value
      cell.classList.toggle("text-muted", empty)

      cell.classList.remove("wl-heat-1", "wl-heat-2", "wl-heat-3", "wl-heat-4", "wl-heat-5")
      if (!empty && value > 0 && max > 0) {
        const bucket = Math.min(5, Math.ceil((value / max) * 5))
        cell.classList.add(`wl-heat-${bucket}`)
      }
    })

    this.highlightTotal(metric)
    this.redraw()
  }

  computeMaxes() {
    const maxes = {}
    this.constructor.METRICS.forEach(key => {
      maxes[key] = this.cells.reduce((max, cell) => {
        return Math.max(max, parseFloat(cell.dataset[key] || "0"))
      }, 0)
    })
    return maxes
  }

  highlightTotal(metric) {
    this.element.querySelectorAll("[data-wl-total]").forEach(el => {
      el.classList.toggle("wl-total-active", el.dataset.wlTotal === metric)
    })
  }

  // Tell the sibling DataTable to re-read cell data so sorting reflects the
  // newly displayed metric. No-op if DataTables hasn't initialized.
  redraw() {
    const datatable = this.application.getControllerForElementAndIdentifier(this.element, "datatable")
    if (datatable && datatable.dataTable) {
      datatable.dataTable.rows().invalidate().draw(false)
    }
  }

  format(value) {
    return Number.isInteger(value) ? String(value) : value.toFixed(1)
  }
}
