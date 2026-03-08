import { Controller } from "@hotwired/stimulus"
import flatpickr from "flatpickr"

export default class extends Controller {
  connect() {
    // Thicker stroke-based chevrons to replace flatpickr's thin filled-path arrows
    const prevArrow = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'><path fill='none' stroke='currentColor' stroke-linecap='round' stroke-linejoin='round' stroke-width='2.5' d='m10 2-6 6 6 6'/></svg>"
    const nextArrow = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'><path fill='none' stroke='currentColor' stroke-linecap='round' stroke-linejoin='round' stroke-width='2.5' d='m6 2 6 6-6 6'/></svg>"

    this.picker = flatpickr(this.element, {
      dateFormat: "Y-m-d",
      altInput: true,
      altFormat: "F j, Y",
      allowInput: true,
      disableMobile: true,
      prevArrow,
      nextArrow
    })

    // Ensure alt input works inside Bootstrap input-groups
    if (this.picker.altInput) {
      this.picker.altInput.classList.add("form-control")
      if (this.element.classList.contains("is-invalid")) {
        this.picker.altInput.classList.add("is-invalid")
      }
    }
  }

  disconnect() {
    if (this.picker) {
      this.picker.destroy()
    }
  }
}
