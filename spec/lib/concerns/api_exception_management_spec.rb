require "rails_helper"

RSpec.describe ApiExceptionManagement do
  # rescue_from registration only happens when Rails.env.production? is truthy AT THE MOMENT
  # the concern is included (see the gem's own CLAUDE.md: "ApiExceptionManagement rescue_from
  # handlers are production-only"). Api::V2/V3::ApplicationController already loaded in this
  # test process with production? false, so we verify the registration in isolation instead,
  # by including the concern into a fresh class with Rails.env stubbed production first.
  describe "rescue_from registration (Rails.env.production?)" do
    it "registers ActiveRecord::RecordNotDestroyed alongside RecordInvalid, both handled by invalid!" do
      allow(Rails.env).to receive(:production?).and_return(true)

      klass = Class.new(ActionController::API) { include ApiExceptionManagement }
      registrations = klass.rescue_handlers.select { |name, _| name.start_with?("ActiveRecord::Record") }.to_h

      expect(registrations["ActiveRecord::RecordNotDestroyed"]).to eq(:invalid!)
      expect(registrations["ActiveRecord::RecordInvalid"]).to eq(:invalid!)
    end
  end

  # invalid! itself is defined unconditionally (only the rescue_from line above is
  # production-gated), so its behaviour can be exercised directly in any environment.
  describe "#invalid! (the handler shared by RecordInvalid and RecordNotDestroyed)" do
    let(:handler) do
      Class.new do
        include ApiExceptionManagement
        attr_reader :rendered

        def render(**opts)
          @rendered = opts
        end

        def head(status)
          @rendered = {status: status}
        end
      end.new
    end

    let(:record) do
      role = Role.new
      role.errors.add(:base, "cannot delete: has dependent records")
      role
    end

    it "responds 422 with the record's error messages for a RecordNotDestroyed exception" do
      exception = ActiveRecord::RecordNotDestroyed.new("blocked", record)

      handler.send(:invalid!, exception)

      expect(handler.rendered[:status]).to eq(422)
      expect(handler.rendered[:json][:error]).to include("cannot delete: has dependent records")
    end

    it "responds 422 with the record's error messages for a RecordInvalid exception (existing behaviour, unchanged)" do
      exception = ActiveRecord::RecordInvalid.new(record)

      handler.send(:invalid!, exception)

      expect(handler.rendered[:status]).to eq(422)
      expect(handler.rendered[:json][:error]).to include("cannot delete: has dependent records")
    end
  end
end
