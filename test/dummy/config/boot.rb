ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../../../Gemfile", __dir__)

require "bundler/setup" if File.exist?(ENV["BUNDLE_GEMFILE"])
$LOAD_PATH.unshift File.expand_path("../../../lib", __dir__)

# Postgres is the only DB target: tests run on Postgres (this gem, like the host apps, uses
# Postgres-specific SQL that SQLite cannot exercise). DATABASE_URL overrides database.yml, and
# the devcontainer points it at the host app's dev DB — which this dummy app's schema load
# (force: :cascade) or db:test:prepare (drop + create) would clobber. Done here, not in the
# test helper, so every entry point (bin/rails db:*, the db:test:prepare subprocess Rails
# spawns for pending schema) is covered: keep DATABASE_URL's server/credentials, but always
# use this gem's own per-environment database.
if ENV["DATABASE_URL"].to_s.start_with?("postgres")
  ENV["DATABASE_URL"] = ENV["DATABASE_URL"].sub(%r{/[^/?]*(?=\?|\z)}, "/model_driven_api_#{ENV.fetch("RAILS_ENV", "development")}")
end
