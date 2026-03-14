import { Controller } from "@hotwired/stimulus"

// Select2 + jQuery are loaded via <script> tags (UMD globals).
// jQuery is bundled inside datatables.js, Select2 via select2.min.js.
//
// The data-controller can be on the <select> element directly — Select2
// hides the original and creates a sibling container, unlike Tom Select
// which wraps in place.

export default class extends Controller {
  static [Symbol.for("stimulusMorphMode")] = "reconnect"

  connect() {
    if (!window.jQuery || !window.jQuery.fn.select2) return

    const $el = window.jQuery(this.element)
    const hasIcons = this.element.querySelector("option[data-icon]") !== null
    const allowClear = this.element.dataset.select2AllowClear !== undefined

    const opts = {
      theme: "bootstrap-5",
      width: "100%",
      minimumResultsForSearch: 6,
      ...(allowClear ? { allowClear: true, placeholder: "" } : {}),
      ...(hasIcons ? this.iconTemplateConfig() : {})
    }

    $el.select2(opts)
  }

  disconnect() {
    if (window.jQuery && window.jQuery.fn.select2) {
      const $el = window.jQuery(this.element)
      if ($el.data("select2")) {
        $el.select2("destroy")
      }
    }
  }

  iconTemplateConfig() {
    const renderWithIcon = (state) => {
      if (!state.element) return state.text
      const icon = state.element.getAttribute("data-icon")
      if (!icon) return state.text
      const span = document.createElement("span")
      span.style.display = "flex"
      span.style.alignItems = "center"
      span.style.gap = "6px"
      const iconSpan = document.createElement("span")
      iconSpan.className = "material-symbols"
      iconSpan.style.fontSize = "16px"
      iconSpan.style.opacity = "0.5"
      iconSpan.textContent = icon
      span.appendChild(iconSpan)
      span.appendChild(document.createTextNode(state.text))
      return span
    }

    return {
      templateResult: renderWithIcon,
      templateSelection: renderWithIcon
    }
  }
}
