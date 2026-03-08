import { Controller } from "@hotwired/stimulus"
import flatpickr from "flatpickr"

export default class extends Controller {
  connect() {
    this.picker = flatpickr(this.element, {
      dateFormat: "Y-m-d",
      altInput: true,
      altFormat: "F j, Y",
      allowInput: true,
      disableMobile: true,
      // Replace flatpickr's default filled-path SVG arrows with Material
      // Symbols icons, matching the icon language used across the app.
      // Color is controlled by CSS ($flatpickr-header-color).
      prevArrow: "<span class='material-symbols'>chevron_left</span>",
      nextArrow: "<span class='material-symbols'>chevron_right</span>"
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
