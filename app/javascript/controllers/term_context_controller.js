import { Controller } from "@hotwired/stimulus"

// Submits the term-context form as soon as either dropdown changes, so setting a
// working term takes effect without a separate button. The controller is on the
// <form> element; requestSubmit() fires the PATCH and the controller redirects back.
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
