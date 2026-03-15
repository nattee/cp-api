import { Controller } from "@hotwired/stimulus"

// Generic tab switcher — toggles active class on tab buttons and d-none on panels.
// Usage:
//   div[data-controller="tabs"]
//     button[data-tabs-target="tab" data-action="click->tabs#switch" data-index="0"]
//     button[data-tabs-target="tab" data-action="click->tabs#switch" data-index="1"]
//     div[data-tabs-target="panel"]  ← index 0
//     div[data-tabs-target="panel"]  ← index 1
export default class extends Controller {
  static targets = ["tab", "panel"]

  switch(event) {
    const index = parseInt(event.currentTarget.dataset.index)
    this.tabTargets.forEach((tab, i) => {
      tab.classList.toggle("active", i === index)
    })
    this.panelTargets.forEach((panel, i) => {
      panel.classList.toggle("d-none", i !== index)
    })
  }
}
