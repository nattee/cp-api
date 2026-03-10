import { Controller } from "@hotwired/stimulus"

// DataTables + jQuery + BS5 integration are loaded via a <script> tag
// (vendor/assets/javascripts/datatables.js) from the DataTables download
// builder. UMD sets window.DataTable as a global.
//
// The data-controller must be on a PARENT element (not the table itself)
// because DataTables wraps the table in a new div, which causes Stimulus
// to fire disconnect/connect in an infinite loop if the controller is on
// the table element directly.

export default class extends Controller {
  static targets = ["table"]

  connect() {
    if (!window.DataTable) return

    // Find the last column index (Actions) to disable sorting/searching on it
    const headerCells = this.tableTarget.querySelectorAll("thead th")
    const lastColIndex = headerCells.length - 1

    this.dataTable = new window.DataTable(this.tableTarget, {
      pageLength: 25,
      lengthMenu: [10, 25, 50, 100],
      columnDefs: [
        { orderable: false, searchable: false, targets: lastColIndex }
      ]
    })
  }

  disconnect() {
    if (this.dataTable) {
      this.dataTable.destroy()
    }
  }
}
