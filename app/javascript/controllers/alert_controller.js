import { Controller } from "@hotwired/stimulus"

// Replaces Bootstrap JS Alert dismiss (which doesn't work with importmap
// since Bootstrap JS is UMD). Handles the close button click, fades out
// with the .fade/.show classes, then removes the element from the DOM.
export default class extends Controller {
  dismiss() {
    this.element.classList.remove("show")
    this.element.addEventListener("transitionend", () => {
      this.element.remove()
    }, { once: true })
  }
}
