namespace :book30 do
  desc "Reconcile the 30th-anniversary book's alumni directory against students " \
       "(REPORT ONLY, no DB writes). PDF=<path>, CSVs -> tmp/book30_report/. Requires mutool."
  task report: :environment do
    pdf = ENV.fetch("PDF", Book30::Directory::DEFAULT_PDF)
    abort "PDF not found: #{pdf} (pass PDF=<path>)" unless File.exist?(pdf)
    Book30Reconciler.new(pdf_path: pdf).run
  end

  desc "Import the book: one book30_entries row per printed line, new student rows for names " \
       "with no student. DRY-RUN by default (reports in tmp/book30_import/<ts>/); COMMIT=1 writes. PDF=<path>."
  task import: :environment do
    pdf = ENV.fetch("PDF", Book30::Directory::DEFAULT_PDF)
    abort "PDF not found: #{pdf} (pass PDF=<path>)" unless File.exist?(pdf)
    result = Book30::Importer.new(pdf_path: pdf, commit: ENV["COMMIT"] == "1").run
    abort "book30:import did not run (see the message above)" if result.nil?
  end

  desc "Delete every book30_entries row and every source=book30 student recorded from the book. DRY-RUN by default; COMMIT=1 deletes."
  task rollback: :environment do
    ok = Book30::Rollback.new(commit: ENV["COMMIT"] == "1").run
    abort "book30:rollback refused (see the message above)" unless ok
  end
end
