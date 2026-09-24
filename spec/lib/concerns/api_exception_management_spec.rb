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

  # Registration alone proves nothing about dispatch: Rails tries rescue_from handlers from
  # the LAST declared to the first, so a catch-all StandardError declared after the specific
  # handlers used to shadow all of them — in production every AccessDenied, RecordNotFound,
  # RecordInvalid... answered 500 (e.g. POST /authenticate with wrong credentials). This
  # asserts which handler Rails actually selects for each exception.
  describe "rescue_from dispatch precedence (Rails.env.production?)" do
    let(:controller) do
      allow(Rails.env).to receive(:production?).and_return(true)
      Class.new(ActionController::API) { include ApiExceptionManagement }.new
    end

    def selected_handler(exception)
      controller.handler_for_rescue(exception)&.name
    end

    let(:record) { Role.new }

    {
      "AuthenticateUser::AccessDenied" => [-> { AuthenticateUser::AccessDenied.new }, :unauthenticated!],
      "CanCan::AccessDenied" => [-> { CanCan::AccessDenied.new }, :unauthorized!],
      "ActiveRecord::RecordNotFound" => [-> { ActiveRecord::RecordNotFound.new }, :not_found!],
      "NoMethodError" => [-> { NoMethodError.new("x") }, :not_found!],
      "ActiveRecord::StaleObjectError" => [-> { ActiveRecord::StaleObjectError.new }, :stale!]
    }.each do |name, (build, expected)|
      it "routes #{name} to #{expected}, not the StandardError catch-all" do
        expect(selected_handler(build.call)).to eq(expected)
      end
    end

    it "routes RecordInvalid and RecordNotDestroyed to invalid!" do
      expect(selected_handler(ActiveRecord::RecordInvalid.new(record))).to eq(:invalid!)
      expect(selected_handler(ActiveRecord::RecordNotDestroyed.new("blocked", record))).to eq(:invalid!)
    end

    # Unreachable while the catch-all shadowed it; it used to point straight at api_error,
    # which takes keywords only, so the handler itself raised ArgumentError when reached.
    it "handles EndpointValidationError without the handler itself crashing" do
      exception = EndpointValidationError.new("verb not allowed")
      expect(selected_handler(exception)).to eq(:endpoint_invalid!)

      rendered = nil
      controller.define_singleton_method(:render) { |**opts| rendered = opts }
      controller.handler_for_rescue(exception).call(exception)

      expect(rendered[:status]).to eq(501)
      expect(rendered[:json][:error]).to eq("verb not allowed")
    end

    it "still routes any other StandardError to fivehundred!" do
      expect(selected_handler(RuntimeError.new("boom"))).to eq(:fivehundred!)
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
