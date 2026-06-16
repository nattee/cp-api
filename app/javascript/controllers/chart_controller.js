import { Controller } from "@hotwired/stimulus"
import "chart.js" // UMD side-effect import — sets window.Chart

// Dark-theme palette for stacked bar segments — mapped to shadcn theme colors
const STACK_COLORS = [
  "rgba(116, 212, 255, 0.7)",  // $primary (#74d4ff)
  "rgba(253, 165, 213, 0.7)",  // $secondary (#fda5d5)
  "rgba(142, 81, 255, 0.7)",   // $info (#8e51ff)
  "rgba(123, 241, 168, 0.7)",  // $success (#7bf1a8)
  "rgba(253, 199, 0, 0.7)",    // $warning (#fdc700)
  "rgba(184, 230, 254, 0.7)",  // $light (#b8e6fe)
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

// Distinct line colors for the GPA-trend chart (one per subject). Bright hues
// that read on the dark theme; cycles if there are more lines than colors.
const LINE_COLORS = [
  "#74d4ff", "#fda5d5", "#8e51ff", "#7bf1a8", "#fdc700",
  "#ff8904", "#b8e6fe", "#fb64b6", "#00d3f2", "#a684ff",
]

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
    else if (this.typeValue === "horizontal-stacked-bar") config = this.horizontalStackedBarConfig()
    else if (this.typeValue === "grade-distribution") config = this.gradeDistributionConfig()
    else if (this.typeValue === "gpa-trend") config = this.gpaTrendConfig()
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

  horizontalStackedBarConfig() {
    const d = this.dataValue
    const datasets = d.datasets.map((ds, i) => ({
      label: ds.code,
      data: ds.data,
      backgroundColor: STACK_COLORS[i % STACK_COLORS.length],
      borderWidth: 0,
    }))

    return {
      type: "bar",
      data: { labels: d.labels, datasets },
      options: {
        indexAxis: "y",
        responsive: true,
        maintainAspectRatio: false,
        scales: {
          x: { stacked: true, beginAtZero: true, grid: { color: GRID_COLOR }, ticks: { color: TICK_COLOR } },
          y: { stacked: true, grid: { color: GRID_COLOR }, ticks: { color: TICK_COLOR } },
        },
        plugins: {
          legend: { labels: { color: TICK_COLOR, boxWidth: 14 } },
          tooltip: { mode: "nearest", axis: "y", intersect: false },
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

  // Multi-line GPA trend: x = term, y = class GPA (0–4), one line per subject.
  // data = { labels: [terms], datasets: [{ label: course_no, data: [gpa|null] }] }
  gpaTrendConfig() {
    const d = this.dataValue
    const datasets = d.datasets.map((ds, i) => ({
      label: ds.label,
      data: ds.data,
      borderColor: LINE_COLORS[i % LINE_COLORS.length],
      backgroundColor: LINE_COLORS[i % LINE_COLORS.length],
      spanGaps: true, // connect across terms a subject wasn't offered
      tension: 0.3,
      borderWidth: 2,
      pointRadius: 3,
      pointHoverRadius: 5,
    }))

    return {
      type: "line",
      data: { labels: d.labels, datasets },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        interaction: { mode: "nearest", axis: "x", intersect: false },
        scales: {
          x: { grid: { color: GRID_COLOR }, ticks: { color: TICK_COLOR } },
          // GPA is always on the 0–4 scale, so fix the axis for honest comparison.
          y: { min: 0, max: 4, grid: { color: GRID_COLOR }, ticks: { color: TICK_COLOR, stepSize: 1 } },
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
