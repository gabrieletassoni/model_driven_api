require "rails_helper"

# Covers the UTC-only contract that replaced the old global
# TimeWithZone#as_json -> utc monkeypatch (config/initializers/time_with_zone.rb):
# the app zone is enforced at boot instead, and a value deliberately localized with
# in_time_zone keeps its own offset in JSON.
RSpec.describe "UTC-only backend time zone" do
  describe "ModelDrivenApi.enforce_utc!" do
    it "accepts UTC, with or without an explicit :utc ActiveRecord storage" do
      expect { ModelDrivenApi.enforce_utc!("UTC") }.not_to raise_error
      expect { ModelDrivenApi.enforce_utc!("Etc/UTC", :utc) }.not_to raise_error
    end

    it "refuses a non-UTC config.time_zone" do
      expect { ModelDrivenApi.enforce_utc!("Europe/Rome") }.to raise_error(ArgumentError, /config\.time_zone/)
    end

    it "refuses local ActiveRecord storage" do
      expect { ModelDrivenApi.enforce_utc!("UTC", :local) }.to raise_error(ArgumentError, /default_timezone/)
    end
  end

  it "boots the dummy app in UTC" do
    expect(Time.zone.name).to eq("UTC")
  end

  describe "JSON rendering of TimeWithZone" do
    let(:instant) { Time.utc(2026, 8, 29, 8, 0, 0) }

    it "renders a plain (UTC) value as ...Z, as before" do
      expect(instant.in_time_zone.to_json).to eq('"2026-08-29T08:00:00.000Z"')
    end

    it "keeps the offset of a value deliberately localized to another zone" do
      expect(instant.in_time_zone("Europe/Rome").to_json).to eq('"2026-08-29T10:00:00.000+02:00"')
    end
  end
end
