import { Controller } from "@hotwired/stimulus"
import TomSelect from "tom-select"

// Generic Tom Select controller. Renders Material Symbols icons when
// <option data-icon="icon_name"> attributes are present; otherwise
// renders plain text. No icon-specific logic is hardcoded here — the
// icon mapping lives in the model (e.g. Student::STATUS_ICONS).
export default class extends Controller {
  connect() {
    const hasIcons = this.element.querySelector("option[data-icon]") !== null

    this.select = new TomSelect(this.element, {
      allowEmptyOption: false,
      controlInput: null,
      ...(hasIcons ? this.iconRenderConfig() : {})
    })
  }

  disconnect() {
    if (this.select) {
      this.select.destroy()
    }
  }

  iconRenderConfig() {
    const iconHtml = (data, escape) => {
      const icon = data.icon
        ? `<span class="material-symbols" style="font-size: 18px; vertical-align: middle; margin-right: 6px;">${escape(data.icon)}</span>`
        : ""
      return `<div>${icon}${escape(data.text)}</div>`
    }

    return {
      render: {
        option: iconHtml,
        item: iconHtml
      }
    }
  }
}
