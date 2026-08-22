namespace :book30 do
  desc "Reconcile the 30th-anniversary book's alumni directory against students " \
       "(REPORT ONLY, no DB writes). PDF=<path> (default: dae's copy), CSVs -> tmp/book30_report/. " \
       "Requires mutool (mupdf-tools)."
  task report: :environment do
    pdf = ENV.fetch("PDF", "/home/dae/ครบรอบ 30 ปี.pdf")
    abort "PDF not found: #{pdf} (pass PDF=<path>)" unless File.exist?(pdf)
    Book30Reconciler.new(pdf_path: pdf).run
  end
end
