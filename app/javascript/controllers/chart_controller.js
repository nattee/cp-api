import { Controller } from "@hotwired/stimulus"
import "chart.js" // UMD side-effect import — sets window.Chart

// Dark-theme palette for stacked bar segments
const STACK_COLORS = [
  "rgba(184, 230, 254, 0.7)",  // $light (#b8e6fe)
  "rgba(116, 212, 255, 0.7)",  // $primary (#74d4ff)
  "rgba(253, 165, 213, 0.7)",  // $secondary (#fda5d5)
  "rgba(123, 241, 168, 0.7)",  // $success (#7bf1a8)
  "rgba(253, 199, 0, 0.7)",    // $warning (#fdc700)
]

// Grade colors matching $grade-* Sass variables in application.scss
const GRADE_COLORS = {
  "A":  "rgba(63, 170, 101, 0.7)",   // $grade-green
  "B+": "rgba(63, 165, 170, 0.7)",   // $grade-teal
  "B":  "rgba(63, 165, 170, 0.55)",  // $grade-teal (lighter)
  "C+": "rgba(191, 170, 48, 0.7)",   // $grade-yellow
  "C":  "rgba(191, 170, 48, 0.55)",  // $grade-yellow (lighter)
  "D+": "rgba(212, 138, 46, 0.7)",   // $grade-orange
  "D":  "rgba(212, 138, 46, 0.55)",  // $grade-orange (lighter)
  "F":  "rgba(224, 64, 64, 0.7)",    // $grade-red
  "S":  "rgba(63, 170, 101, 0.5)",   // $grade-green (lighter)
  "U":  "rgba(224, 64, 64, 0.5)",    // $grade-red (lighter)
  "W":  "rgba(150, 150, 150, 0.5)",  // $grade-muted
  "V":  "rgba(150, 150, 150, 0.35)", // $grade-muted (lighter)
  "P":  "rgba(116, 212, 255, 0.5)",  // $primary
  "M":  "rgba(150, 150, 150, 0.25)", // $grade-muted (lightest)
}

const GRID_COLOR = "rgba(255, 255, 255, 0.08)"
const TICK_COLOR = "#ffffff"

export default class extends Controller {
  static targets = ["canvas", "filter"]
  static values = { type: String, data: Object }

  connect() {
    if (!window.Chart) return
    const ctx = this.canvasTarget.getContext("2d")
    let config
    if (this.typeValue === "stacked-bar") config = this.stackedBarConfig("all")
    else if (this.typeValue === "grade-distribution") config = this.gradeDistributionConfig()
    else config = this.histogramConfig()
    this.chart = new window.Chart(ctx, config)
  }

  filterChanged() {
    if (!this.chart || this.typeValue !== "stacked-bar") return
    const status = this.filterTarget.value
    const d = this.dataValue
    const methodData = d.datasets[status]
    this.chart.data.datasets.forEach((ds, i) => {
      ds.data = methodData[d.methods[i]] || d.labels.map(() => 0)
    })
    this.chart.update()
  }

  stackedBarConfig(status) {
    const d = this.dataValue
    const methodData = d.datasets[status]
    const datasets = d.methods.map((method, i) => ({
      label: method,
      data: methodData[method] || d.labels.map(() => 0),
      backgroundColor: STACK_COLORS[i % STACK_COLORS.length],
      borderWidth: 0,
    }))

    return {
      type: "bar",
      data: { labels: d.labels, datasets },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          x: { stacked: true, grid: { color: GRID_COLOR }, ticks: { color: TICK_COLOR } },
          y: { stacked: true, beginAtZero: true, grid: { color: GRID_COLOR }, ticks: { color: TICK_COLOR, stepSize: 1 } },
        },
        plugins: {
          legend: { labels: { color: TICK_COLOR, boxWidth: 14 } },
          tooltip: { mode: "index", intersect: false },
        },
      },
    }
  }

  histogramConfig() {
    const d = this.dataValue
    return {
      type: "bar",
      data: {
        labels: d.labels,
        datasets: [{
          label: "Students",
          data: d.counts,
          backgroundColor: "rgba(116, 212, 255, 0.6)",
          borderColor: "rgba(116, 212, 255, 1)",
          borderWidth: 1,
        }],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          x: { grid: { color: GRID_COLOR }, ticks: { color: TICK_COLOR } },
          y: { beginAtZero: true, grid: { color: GRID_COLOR }, ticks: { color: TICK_COLOR, stepSize: 1 } },
        },
        plugins: {
          legend: { display: false },
          tooltip: { callbacks: { title: (items) => `GPA ${items[0].label}` } },
        },
      },
    }
  }

  gradeDistributionConfig() {
    const d = this.dataValue
    const datasets = d.datasets.map(({ grade, data }) => ({
      label: grade,
      data,
      backgroundColor: GRADE_COLORS[grade] || "rgba(150, 150, 150, 0.4)",
      borderWidth: 0,
    }))

    return {
      type: "bar",
      data: { labels: d.labels, datasets },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          x: { stacked: true, grid: { color: GRID_COLOR }, ticks: { color: TICK_COLOR } },
          y: { stacked: true, beginAtZero: true, grid: { color: GRID_COLOR }, ticks: { color: TICK_COLOR, stepSize: 1 } },
        },
        plugins: {
          legend: { labels: { color: TICK_COLOR, boxWidth: 14 } },
          tooltip: { mode: "index", intersect: false },
        },
      },
    }
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
      this.chart = null
    }
  }
}
