import { Controller } from "@hotwired/stimulus"

// Auto-refreshes the current page at a fixed interval.
// Disconnects cleanly when Turbo navigates away, preventing stale refreshes.
// Stops automatically when the server stops rendering the controller element
// (e.g. when a scrape finishes and is no longer "running").
export default class extends Controller {
  static values = { interval: { type: Number, default: 3000 } }

  connect() {
    this.timer = setInterval(() => {
      Turbo.visit(window.location.href, { action: "replace" })
    }, this.intervalValue)
  }

  disconnect() {
    if (this.timer) {
      clearInterval(this.timer)
    }
  }
}
