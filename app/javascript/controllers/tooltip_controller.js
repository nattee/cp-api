import { Controller } from "@hotwired/stimulus"

// Styled replacement for native title tooltips on informational hover text.
// Native titles have a fixed ~1s hover delay and a tiny unstylable OS font;
// Bootstrap Tooltip needs Bootstrap JS, which is unusable here (UMD, no
// exports — see CLAUDE.md Asset Pipeline). Attached once to <body>; event
// delegation picks up any [data-tooltip] element, including rows DataTables
// re-renders. The tooltip div is position:fixed so .table-responsive's
// overflow can't clip it (which is why this isn't a pure-CSS ::after).
const SHOW_DELAY_MS = 100
const GAP_PX = 6
const VIEWPORT_MARGIN_PX = 8

export default class extends Controller {
  connect() {
    this.tip = null
    this.trigger = null
    this.timer = null
    this.element.addEventListener("mouseover", this.show)
    this.element.addEventListener("mouseout", this.hide)
    this.element.addEventListener("focusin", this.show)
    this.element.addEventListener("focusout", this.hide)
    this.element.addEventListener("keydown", this.onKeydown)
    // capture — scroll events don't bubble out of .table-responsive, and a
    // fixed-position tooltip goes stale the moment anything scrolls
    // Known accepted limitation: if the table re-renders (DataTables search/
    // sort) while the pointer is parked on a cell, no mouseout fires and the
    // tooltip lingers until the next scroll, Escape, or hover.
    window.addEventListener("scroll", this.hideNow, { capture: true, passive: true })
    window.addEventListener("resize", this.hideNow)
    document.addEventListener("turbo:before-cache", this.teardown)
  }

  disconnect() {
    this.teardown()
    this.element.removeEventListener("mouseover", this.show)
    this.element.removeEventListener("mouseout", this.hide)
    this.element.removeEventListener("focusin", this.show)
    this.element.removeEventListener("focusout", this.hide)
    this.element.removeEventListener("keydown", this.onKeydown)
    window.removeEventListener("scroll", this.hideNow, { capture: true })
    window.removeEventListener("resize", this.hideNow)
    document.removeEventListener("turbo:before-cache", this.teardown)
  }

  show = (event) => {
    const trigger = event.target.closest?.("[data-tooltip]")
    if (!trigger || trigger === this.trigger) return
    this.hideNow()
    this.trigger = trigger
    this.timer = setTimeout(() => this.display(trigger), SHOW_DELAY_MS)
  }

  hide = (event) => {
    const trigger = event.target.closest?.("[data-tooltip]")
    if (!trigger || trigger !== this.trigger) return
    // moving between descendants of the same trigger is not a real leave
    if (event.relatedTarget && trigger.contains(event.relatedTarget)) return
    this.hideNow()
  }

  onKeydown = (event) => {
    if (event.key === "Escape") this.hideNow()
  }

  hideNow = () => {
    clearTimeout(this.timer)
    this.timer = null
    this.trigger?.removeAttribute("aria-describedby")
    this.trigger = null
    if (this.tip) this.tip.style.display = "none"
  }

  // Removing (not just hiding) keeps Turbo's page snapshot free of the div,
  // so restored pages don't accumulate orphans across visits.
  teardown = () => {
    this.hideNow()
    this.tip?.remove()
    this.tip = null
  }

  display(trigger) {
    const text = trigger.dataset.tooltip
    if (!trigger.isConnected || !text) { this.hideNow(); return } // Turbo replaced it mid-delay
    const tip = this.tipElement()
    tip.textContent = text
    tip.style.display = "block"
    tip.style.visibility = "hidden" // measure first, place before revealing
    tip.style.left = "0px" // reset before measuring — a leftover right-edge `left` shrinks the measured width
    const r = trigger.getBoundingClientRect()
    const t = tip.getBoundingClientRect()
    let left = r.left + r.width / 2 - t.width / 2
    left = Math.max(VIEWPORT_MARGIN_PX, Math.min(left, window.innerWidth - t.width - VIEWPORT_MARGIN_PX))
    let top = r.top - t.height - GAP_PX
    if (top < VIEWPORT_MARGIN_PX) top = r.bottom + GAP_PX // flip below near viewport top
    tip.style.left = `${Math.round(left)}px`
    tip.style.top = `${Math.round(top)}px`
    tip.style.visibility = "visible"
    trigger.setAttribute("aria-describedby", "app-tooltip")
  }

  tipElement() {
    if (!this.tip) {
      this.tip = document.createElement("div")
      this.tip.className = "app-tooltip"
      this.tip.setAttribute("role", "tooltip")
      this.tip.id = "app-tooltip"
      document.body.appendChild(this.tip)
    }
    return this.tip
  }
}
