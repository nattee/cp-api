import { Controller } from "@hotwired/stimulus"

// Updates the "Preview" column in the column-mapping table when the user
// changes a file-column dropdown or types a fixed value.
//
// Expected data attributes on the controller element:
//   data-mapping-preview-headers-value  — JSON array of file header strings
//   data-mapping-preview-row-value      — JSON array of preview row values
//
// Each mapping row has:
//   select[data-mapping-attr]           — source selector (column header, "__constant__", or "")
//   [data-mapping-preview-text]         — span showing column preview text
//   [data-mapping-constant]             — fixed value input or select (in preview cell, hidden unless active)

const CONSTANT_VALUE = "__constant__"

export default class extends Controller {
  static values = {
    headers: Array,
    row: Array
  }

  connect() {
    this.element.addEventListener("change", this.handleChange)
  }

  disconnect() {
    this.element.removeEventListener("change", this.handleChange)
  }

  handleChange = (event) => {
    const select = event.target
    if (!select.matches("select[data-mapping-attr]")) return

    const attr = select.dataset.mappingAttr
    const previewText = this.element.querySelector(`[data-mapping-preview-text="${attr}"]`)
    const constantInput = this.element.querySelector(`[data-mapping-constant="${attr}"]`)

    if (select.value === CONSTANT_VALUE) {
      previewText.hidden = true
      constantInput.hidden = false
      constantInput.focus()
    } else {
      constantInput.hidden = true
      previewText.hidden = false
      this.setPreviewText(previewText, select.value)
    }
  }

  setPreviewText(span, headerValue) {
    if (!headerValue) {
      span.textContent = "--"
      return
    }

    const idx = this.headersValue.indexOf(headerValue)
    if (idx === -1) {
      span.textContent = "--"
      return
    }

    const value = this.rowValue[idx]
    span.textContent = value != null ? String(value) : "--"
  }
}
