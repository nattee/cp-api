import { Controller } from "@hotwired/stimulus"

// DataTables + jQuery + BS5 integration are loaded via a <script> tag
// (vendor/assets/javascripts/datatables.js) from the DataTables download
// builder. UMD sets window.DataTable as a global.
//
// The data-controller must be on a PARENT element (not the table itself)
// because DataTables wraps the table in a new div, which causes Stimulus
// to fire disconnect/connect in an infinite loop if the controller is on
// the table element directly.
//
// Supports two modes:
//
// 1. Client-side (default): All data is in the HTML <tbody>. DataTables
//    handles pagination/search on the existing rows. Optional column
//    filters via "filter" targets apply column().search() calls.
//
// 2. Server-side: Enabled by setting data-datatable-server-side-url-value
//    to a JSON endpoint URL. DataTables sends draw/start/length/search/order
//    params and the server returns { draw, recordsTotal, recordsFiltered,
//    data: [[col1, ...], ...] }.

export default class extends Controller {
  static targets = ["table", "filter"]
  static values = { serverSideUrl: String, exportUrl: String, pageLength: { type: Number, default: 25 }, order: String, disableLastColumn: { type: Boolean, default: true } }

  connect() {
    if (!window.DataTable) return

    // Find the last column index (Actions) to disable sorting/searching on it
    const headerCells = this.tableTarget.querySelectorAll("thead th")
    const lastColIndex = headerCells.length - 1

    // Parse order value: "colIndex:dir" e.g. "4:desc". Default: first column asc.
    let order = [[0, "asc"]]
    if (this.hasOrderValue && this.orderValue) {
      const [col, dir] = this.orderValue.split(":")
      order = [[parseInt(col, 10), dir || "asc"]]
    }

    // Tables ending in an Actions column disable sorting/searching on it
    // (the default). Tables whose last column IS data (e.g. the workload
    // matrix's last total column) opt out via data-datatable-disable-last-column-value="false".
    const columnDefs = []
    if (this.disableLastColumnValue) {
      columnDefs.push({ orderable: false, searchable: false, targets: lastColIndex })
    }

    const opts = {
      pageLength: this.pageLengthValue,
      lengthMenu: [10, 25, 50, 100],
      order,
      columnDefs
    }

    // Server-side mode: DataTables fetches data via AJAX
    if (this.hasServerSideUrlValue && this.serverSideUrlValue) {
      Object.assign(opts, {
        serverSide: true,
        ajax: this.serverSideUrlValue
      })
    }

    this.dataTable = new window.DataTable(this.tableTarget, opts)

    // Apply default filter values (e.g. staff status "Active" on load).
    // Only meaningful for client-side mode.
    this.filterTargets.forEach(el => {
      const defaultVal = el.dataset.datatableDefaultValue
      if (defaultVal !== undefined && defaultVal !== "") {
        this._applyFilter(el, defaultVal)
      }
    })
  }

  // Stimulus action: data-action="change->datatable#filter"
  // Works with both <select> and <input type="radio"> elements.
  filter(event) {
    const el = event.currentTarget
    this._applyFilter(el, el.value)
  }

  // Stimulus action: data-action="datatable#export"
  // Downloads the current view as a file. In server-side mode the visible
  // <tbody> holds only one page, so we forward the exact DataTables request
  // params (search/column filters/order) to the export URL — the server then
  // returns the full filtered result set, not just the current page. jQuery
  // (bundled with the DataTables UMD) serializes the nested params object.
  export(event) {
    if (event) event.preventDefault()
    if (!this.hasExportUrlValue || !this.exportUrlValue) return

    let url = this.exportUrlValue
    if (this.dataTable && this.hasServerSideUrlValue && window.jQuery) {
      const query = window.jQuery.param(this.dataTable.ajax.params())
      if (query) url += (url.includes("?") ? "&" : "?") + query
    }
    window.location = url
  }

  _applyFilter(el, value) {
    if (!this.dataTable) return
    const colIndex = parseInt(el.dataset.datatableColumnIndex, 10)
    const useRegex = el.dataset.datatableRegex === "true"
    // column().search(term, isRegex, isSmart) — disable smart search
    // when using regex to prevent DataTables from escaping the pattern
    this.dataTable.column(colIndex).search(value, useRegex, !useRegex).draw()
  }

  disconnect() {
    if (this.dataTable) {
      this.dataTable.destroy()
    }
  }
}
