# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "bootstrap", to: "bootstrap.js"
pin "datatables.net", to: "datatables.net.js"
pin "datatables.net-bs5", to: "datatables.net-bs5.js"
pin "chart.js", to: "chart.js"
pin "tom-select", to: "tom-select.js"
pin "flatpickr", to: "flatpickr.js"
