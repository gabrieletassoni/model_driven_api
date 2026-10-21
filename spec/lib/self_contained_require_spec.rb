require "rails_helper"
require "open3"

# A host app gets this gem's runtime dependencies only transitively, so Bundler.require does NOT
# auto-require them: `require "model_driven_api"` must require everything it uses at runtime.
# The dummy app's own Gemfile lists jsonapi-serializer directly (auto-required), which hid a
# missing require: every /api/v3 request in a host answered 500 "uninitialized constant
# Api::V3::SerializerFactory::JSONAPI". Checked in a fresh process, outside the dummy's
# Bundler.require (same trap as pagy, see CLAUDE.md).
RSpec.describe "require \"model_driven_api\" (as a host app loads it)" do
  it "loads the runtime dependencies it references" do
    script = <<~RUBY
      require "rails"
      require "active_record/railtie"
      require "model_driven_api"
      missing = %w[JSONAPI::Serializer Pagy Kaminari Ransack SimpleCommand JWT].reject { |c| Object.const_defined?(c) }
      print missing.join(",")
    RUBY
    out, err, status = Open3.capture3("ruby", "-e", script, chdir: File.expand_path("../..", __dir__))
    expect(status).to be_success, err
    expect(out).to eq(""), "not loaded by require \"model_driven_api\": #{out}"
  end
end
