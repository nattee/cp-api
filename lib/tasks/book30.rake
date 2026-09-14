namespace :book30 do
  desc "Reconcile the 30th-anniversary book's alumni directory against students " \
       "(REPORT ONLY, no DB writes). PDF=<path>, CSVs -> tmp/book30_report/. Requires mutool."
  task report: :environment do
    pdf = ENV.fetch("PDF", Book30::Directory::DEFAULT_PDF)
    abort "PDF not found: #{pdf} (pass PDF=<path>)" unless File.exist?(pdf)
    Book30Reconciler.new(pdf_path: pdf).run
  end

  desc "Import the book: one book30_entries row per printed line, placeholders for names " \
       "with no student. DRY-RUN by default (reports in tmp/book30_import/<ts>/); COMMIT=1 writes. PDF=<path>."
  task import: :environment do
    pdf = ENV.fetch("PDF", Book30::Directory::DEFAULT_PDF)
    abort "PDF not found: #{pdf} (pass PDF=<path>)" unless File.exist?(pdf)
    Book30::Importer.new(pdf_path: pdf, commit: ENV["COMMIT"] == "1").run
  end

  desc "Delete every book30_entries row and every source=book30 placeholder student. DRY-RUN by default; COMMIT=1 deletes."
  task rollback: :environment do
    Book30::Rollback.new(commit: ENV["COMMIT"] == "1").run
  end
end
