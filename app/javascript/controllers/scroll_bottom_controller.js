import { Controller } from "@hotwired/stimulus"

// Scrolls the element to the bottom on connect (page load / Turbo navigation).
// Usage: data-controller="scroll-bottom"
export default class extends Controller {
  connect() {
    this.element.scrollTop = this.element.scrollHeight
  }
}
