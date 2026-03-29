import { Controller } from "@hotwired/stimulus"

// Generic controller for dynamic add/remove of accepts_nested_attributes_for
// field groups. A <template> element holds the HTML for one nested row.
// "Add" clones it, replacing a placeholder string in all name attributes
// with a unique timestamp index. "Remove" toggles a _destroy hidden field
// and hides the row.
//
// Supports multiple nesting levels: section uses placeholder "NEW_RECORD",
// time_slots inside a section use "NEW_TIME_SLOT", teachings use
// "NEW_TEACHING". Each level has its own controller instance with a
// different placeholderValue.

export default class extends Controller {
  static targets = ["container", "template", "wrapper", "destroyField"]
  static values = {
    wrapperSelector: { type: String, default: ".nested-fields" },
    placeholder: { type: String, default: "NEW_RECORD" }
  }

  add() {
    const content = this.templateTarget.innerHTML
    const index = new Date().getTime()
    const regex = new RegExp(this.placeholderValue, "g")
    const html = content.replace(regex, index)
    this.containerTarget.insertAdjacentHTML("beforeend", html)
  }

  remove(event) {
    const wrapper = event.target.closest(this.wrapperSelectorValue)
    if (!wrapper) return

    const destroyField = wrapper.querySelector("input[name*='_destroy']")
    if (destroyField) {
      // Existing persisted record — mark for destruction, hide
      destroyField.value = "1"
      wrapper.style.display = "none"
    } else {
      // New unsaved record — remove from DOM entirely
      wrapper.remove()
    }
  }
}
