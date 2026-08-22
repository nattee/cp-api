namespace :programs do
  desc "Dissolve the synthetic program 0999 onto the regular CS lineage. " \
       "Dry-run by default; COMMIT=1 to write."
  task dissolve_0999: :environment do
    DissolveProgram0999.new(commit: ENV["COMMIT"] == "1").run
  end
end
