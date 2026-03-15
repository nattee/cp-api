import { Controller } from "@hotwired/stimulus"

// Auto-fills grade weight when a grade is selected in the enrollment form.
// Standard Thai university grade-to-weight mapping.
// User can still override the auto-filled value.
export default class extends Controller {
  static targets = ["gradeSelect", "weightInput"]

  static values = {
    weights: { type: Object, default: {
      "A": 4.0, "B+": 3.5, "B": 3.0, "C+": 2.5,
      "C": 2.0, "D+": 1.5, "D": 1.0, "F": 0.0
    }}
  }

  update() {
    const grade = this.gradeSelectTarget.value
    const weight = this.weightsValue[grade]
    if (weight !== undefined) {
      this.weightInputTarget.value = weight
    } else {
      this.weightInputTarget.value = ""
    }
  }
}
