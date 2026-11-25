namespace :thecore do
  namespace :db do
    desc "Rebuilds the thecore_raw role and its privileges, under which raw/sql runs (idempotent; ADR 0048)."
    task raw_grants: :environment do
      result = RawSqlGrants.apply!
      puts(result == :applied ? "thecore_raw grants applied" : "thecore_raw grants skipped: the database user is not superuser")
    end

    # The hook below. As a prerequisite it runs once every rake file is loaded, so the grants are
    # appended after thecore_auth_commons' seed actions whatever order the engines load in.
    task :raw_grants_after_seed do
      Rake::Task["thecore:db:seed"].enhance do
        Rake::Task["thecore:db:raw_grants"].reenable
        Rake::Task["thecore:db:raw_grants"].invoke
      end
    end
  end
end

# thecore:db:seed runs after the migrations both in thecore:db:init/update and in the image
# entrypoint (db:migrate then thecore:db:seed), so every deploy ends by re-applying the grants.
Rake::Task.define_task("thecore:db:seed" => "thecore:db:raw_grants_after_seed")
