import { Controller } from "@hotwired/stimulus"

// Shared course-list filter bar. Composes up to three criteria:
//
//   • Scope   — All courses vs department only (course_no starts with "2110")
//   • Program — restrict to courses paired with a chosen program
//   • Type    — within that program, Compulsory (-C) vs Elective (-ELEC*)
//
// Compulsory/elective is a property of the (course, program) PAIRING, not of the
// course itself, so Type is meaningless until a Program is chosen — the control
// disables itself until then. Each course row is tagged with a token string, one
// "<program_code>-<TYPE>" token per pairing (e.g. "4784-C 3736-ELEC"), so ONE
// regex per criterion decides membership. Keeping program+type coupled per token
// means a course compulsory in one program and elective in another filters right.
//
// Two rendering modes:
//   • "datatable" — stacked on the `datatable` controller (data-controller=
//                   "datatable course-filter"). Drives filtering through
//                   DataTables column search so pagination and the row count
//                   stay correct. Scope searches the Course No column; Program+
//                   Type search a hidden token column.
//   • "rows"      — plain grouped tables with no DataTable (e.g. a program's
//                   curriculum). Toggles each tagged <tr> hidden directly.
//
// The bar's controls live in the shared _course_filters partial. The column
// indices and mode live as values on the card element in each view.
export default class extends Controller {
  static targets = ["scope", "program", "type", "typeWrapper", "row", "groupRow"]
  static values = {
    mode: { type: String, default: "datatable" },
    courseCol: { type: Number, default: 0 },   // datatable: Course No column index
    tokenCol: { type: Number, default: -1 },    // datatable: hidden token column index (-1 = none)
    fixedProgram: String                        // rows mode: the page's fixed program_code
  }

  connect() {
    // Apply the default scope (2110) on load. In datatable mode the sibling
    // `datatable` controller may connect after us, so its DataTable instance
    // isn't guaranteed to exist yet — wait for it before applying.
    this.applyWhenReady()
  }

  applyWhenReady(attempts = 0) {
    if (!this.element.isConnected) return   // navigated away mid-retry
    if (this.modeValue !== "rows" && !this.dataTable) {
      if (attempts < 30) requestAnimationFrame(() => this.applyWhenReady(attempts + 1))
      return
    }
    this.apply()
  }

  // data-action="change->course-filter#apply"
  apply() {
    const scope = this.currentScope()
    const program = this.currentProgram()
    const type = this.currentType()

    this.syncTypeAvailability(program)

    if (this.modeValue === "rows") {
      this.applyRows(scope, program, type)
    } else {
      this.applyDatatable(scope, program, type)
    }
  }

  currentScope() {
    const el = this.scopeTargets.find(r => r.checked)
    return el ? el.value : ""   // "2110" or ""
  }

  currentProgram() {
    if (this.hasFixedProgramValue && this.fixedProgramValue) return this.fixedProgramValue
    if (!this.hasProgramTarget) return ""
    return this.programTarget.value || ""
  }

  currentType() {
    const el = this.typeTargets.find(r => r.checked && !r.disabled)
    return el ? el.value : ""   // "", "compulsory", "elective"
  }

  // Type needs a program to be compulsory/elective *of*. When "All programs" is
  // selected, dim and disable the Type control (and treat it as "All").
  syncTypeAvailability(program) {
    if (!this.hasTypeWrapperTarget) return
    if (this.hasFixedProgramValue && this.fixedProgramValue) return  // program is fixed: always on
    const enabled = !!program
    this.typeWrapperTarget.classList.toggle("opacity-50", !enabled)
    this.typeTargets.forEach(r => { r.disabled = !enabled })
  }

  // Regex over a row's space-separated token string. Each token is
  // "<program_code>-<TYPE>" (TYPE ∈ C | ELEC | OTHER), e.g. "4784-C 3736-ELEC".
  tokenRegex(program, type) {
    if (!program) return null
    if (type === "compulsory") return `(?:^| )${program}-C(?: |$)`
    if (type === "elective")   return `(?:^| )${program}-ELEC(?: |$)`
    return `(?:^| )${program}-`   // any pairing with this program
  }

  applyDatatable(scope, program, type) {
    const dt = this.dataTable
    if (!dt) return

    // Scope → Course No column (regex, smart search off so ^ anchors).
    dt.column(this.courseColValue).search(scope === "2110" ? "^2110" : "", true, false)

    // Program + Type → hidden token column.
    if (this.tokenColValue >= 0) {
      const re = this.tokenRegex(program, type)
      dt.column(this.tokenColValue).search(re || "", !!re, false)
    }

    dt.draw()
  }

  applyRows(scope, program, type) {
    const scopeRe = scope === "2110" ? new RegExp(`^${this.deptPrefix}`) : null
    const tokPattern = this.tokenRegex(program, type)
    const tokRe = tokPattern ? new RegExp(tokPattern) : null

    // Toggle course rows, tallying how many stay visible per group.
    const visibleByGroup = {}
    this.rowTargets.forEach(row => {
      const no = row.dataset.courseNo || ""
      const tokens = row.dataset.courseTokens || ""
      const show = (!scopeRe || scopeRe.test(no)) && (!tokRe || tokRe.test(tokens))
      row.classList.toggle("d-none", !show)
      const g = row.dataset.courseGroup
      if (g !== undefined) visibleByGroup[g] = (visibleByGroup[g] || 0) + (show ? 1 : 0)
    })

    // Hide a group's header/spacer rows when the whole group filtered away.
    this.groupRowTargets.forEach(gr => {
      const g = gr.dataset.courseGroup
      gr.classList.toggle("d-none", (visibleByGroup[g] || 0) === 0)
    })
  }

  get deptPrefix() {
    return "2110"
  }

  get dataTable() {
    const c = this.application.getControllerForElementAndIdentifier(this.element, "datatable")
    return c && c.dataTable ? c.dataTable : null
  }
}
