require "rails_helper"

# How a record serializes the options a client sent (a / json_attrs), rule by rule
# (host Odoo #6285). Methods defined in this file count as "our code": it lives in this gem,
# which depends on thecore_backend_commons.
RSpec.describe Api::V2::RequestJsonAttrs do
  def serialize(record, options) = record.as_json(described_class.from_params(options))

  let(:role) { create(:role, name: "Reader") }

  before { ModelDrivenApi::Current.reset }

  # Subclassing a model runs thecore's default-module registry, which rewrites the json_attrs
  # class variable the subclass shares with its parent: put the parents' back.
  around do |example|
    saved = [Role, User, PushMessage].to_h { |model| [model, model.json_attrs] }
    example.run
  ensure
    saved.each { |model, attrs| model.json_attrs = attrs }
  end

  describe "attributes the model hides by default" do
    # Hides columns the way Devise does, by adding them to :except: a secret (encrypted_password)
    # and sign-in tracking (last_sign_in_at), which frontends may read through a[only].
    let(:devise_like) do
      Class.new(User) do
        def self.name = "DeviseLikeUser"

        def serializable_hash(options = nil)
          options = (options || {}).dup
          options[:except] = Array(options[:except]) + %w[encrypted_password last_sign_in_at]
          super
        end
      end
    end
    let(:user) { devise_like.find(create(:user).id) }

    it "are never served through only when they are secrets" do
      expect(serialize(user, only: %w[id encrypted_password])).to eq("id" => user.id)
    end

    it "are still served through only when their name is not a secret's" do
      expect(serialize(user, only: %w[id last_sign_in_at])).to eq("id" => user.id, "last_sign_in_at" => nil)
    end

    it "are never served as methods" do
      expect(serialize(user, only: %w[id], methods: %w[encrypted_password])).to eq("id" => user.id)
    end

    it "stay hidden when the client only excludes other columns" do
      expect(serialize(user, except: %w[email])).not_to have_key("encrypted_password")
    end
  end

  describe "methods" do
    let(:klass) do
      Class.new(Role) do
        def self.name = "Role"
        def self.json_attrs = {methods: %i[declared_writer!]}

        def declared_writer!
          update_column(:name, "written on purpose")
          "declared"
        end

        def our_reader = "read #{name}"

        def our_writer
          update_column(:name, "written by accident")
          "written"
        end

        def our_bang! = "bang"

        def our_with_argument(value) = value

        def our_raising = raise(ArgumentError, "boom")

        private

        def our_private = "private"
      end
    end
    let(:record) { klass.find(role.id) }

    before do
      # A fake location on purpose: the method must look written in a foreign gem.
      klass.module_eval("def foreign_reader = 'foreign'", "/opt/elsewhere/gems/foreign-1.0/lib/foreign.rb", 1) # standard:disable Style/EvalWithLocation
    end

    it "run as before when the model declares them, side effects included" do
      expect(serialize(record, only: %w[id], methods: %w[declared_writer!]))
        .to eq("id" => role.id, "declared_writer!" => "declared")
      expect(role.reload.name).to eq("written on purpose")
    end

    it "serve an undeclared public reader written in our code" do
      expect(serialize(record, only: %w[id], methods: %w[our_reader])).to eq("id" => role.id, "our_reader" => "read Reader")
    end

    it "drop an undeclared method of ours that writes, keeping the other fields and the data" do
      expect(serialize(record, only: %w[id], methods: %w[our_writer our_reader]))
        .to eq("id" => role.id, "our_reader" => "read Reader")
      expect(role.reload.name).to eq("Reader")
    end

    it "drop an undeclared method that raises, instead of failing the response" do
      expect(serialize(record, only: %w[id], methods: %w[our_raising])).to eq("id" => role.id)
    end

    it "never call undeclared names ending in ! or =, private ones, or ones needing arguments" do
      expect(serialize(record, only: %w[id], methods: %w[our_bang! name= our_private our_with_argument]))
        .to eq("id" => role.id)
    end

    it "never call methods written outside the app and the thecore gems" do
      expect(serialize(record, only: %w[id], methods: %w[foreign_reader])).to eq("id" => role.id)
    end

    it "never call methods of a non-thecore gem installed inside the app, as deploy images do (/app/vendor/bundle)" do
      gem_dir = Rails.root.join("vendor/bundle/ruby/3.3.0/gems/foreign-1.0").to_s
      foreign = Gem::Specification.new { |spec|
        spec.name = "foreign"
        spec.version = "1.0"
      }
      allow(foreign).to receive(:full_gem_path).and_return(gem_dir)
      allow(Gem).to receive(:loaded_specs).and_return(Gem.loaded_specs.merge("foreign" => foreign))
      klass.module_eval("def bundled_reader = 'bundled'", File.join(gem_dir, "lib/foreign.rb"), 1) # standard:disable Style/EvalWithLocation

      expect(serialize(record, only: %w[id], methods: %w[bundled_reader])).to eq("id" => role.id)
    end

    it "never call framework methods" do
      expect(serialize(record, only: %w[id], methods: %w[destroy touch attributes delete])).to eq("id" => role.id)
      expect(Role.exists?(role.id)).to be(true)
    end

    it "serve columns, associations and <association>_ids as plain reads" do
      user = create(:user)
      user.roles << role

      expect(serialize(user, only: %w[id], methods: %w[email role_ids]))
        .to eq("id" => user.id, "email" => user.email, "role_ids" => [role.id])
    end

    describe "callbacks" do
      # Callbacks written by us and left public (host Odoo #6314). Their side effects may live
      # outside the database (Redis, mail, HTTP), where the read-only guard can't see them.
      let(:calls) { [] }
      let(:callback_klass) do
        log = calls
        Class.new(Role) do
          def self.name = "Role"
          def self.json_attrs = {methods: %i[declared_callback]}

          before_validation :our_validation_callback
          after_save :our_external_callback
          after_commit :declared_callback

          define_method(:our_validation_callback) {
            log << :validation
            "validation"
          }
          define_method(:our_external_callback) {
            log << :external
            "external"
          }
          define_method(:declared_callback) { "declared" }

          def our_reader = "read #{name}"
        end
      end
      let(:record) { callback_klass.find(role.id) }

      it "never call an undeclared callback, whichever chain registers it" do
        expect(serialize(record, only: %w[id], methods: %w[our_validation_callback our_external_callback]))
          .to eq("id" => role.id)
        expect(calls).to be_empty
      end

      it "still run a callback the model declares in json_attrs[:methods]" do
        expect(serialize(record, only: %w[id], methods: %w[declared_callback]))
          .to eq("id" => role.id, "declared_callback" => "declared")
      end

      it "still serve a public method of ours that is not a callback" do
        expect(serialize(record, only: %w[id], methods: %w[our_reader])).to eq("id" => role.id, "our_reader" => "read Reader")
      end

      it "log the refusal as a callback" do
        allow(Rails.logger).to receive(:warn)

        serialize(record, only: %w[id], methods: %w[our_external_callback])

        expect(Rails.logger).to have_received(:warn).with(/Role#our_external_callback dropped \(a callback\)/).once
      end

      it "apply to included records too" do
        log = calls
        stub_const("CallbackUser", Class.new(User) do
          after_save :our_external_callback
          define_method(:our_external_callback) { log << :external }
        end)
        message_class = Class.new(PushMessage) do
          def self.name = "PushMessage"
          belongs_to :callback_sender, class_name: "CallbackUser", foreign_key: :sender_user_id, optional: true
        end
        user = create(:user)
        message = create(:push_message, sender: user)

        expect(serialize(message_class.find(message.id), only: %w[id],
          include: {callback_sender: {only: %w[id], methods: %w[our_external_callback]}}))
          .to eq("id" => message.id, "callback_sender" => {"id" => user.id})
        expect(calls).to be_empty
      end

      it "apply to a polymorphic record with the rules of its own class" do
        log = calls
        stub_const("CallbackUser", Class.new(User) do
          after_save :our_external_callback
          define_method(:our_external_callback) { log << :external }
        end)
        message_class = Class.new(PushMessage) do
          def self.name = "PushMessage"
          belongs_to :subject, polymorphic: true, foreign_key: :sender_user_id, foreign_type: :message_type, optional: true
        end
        user = create(:user)
        message = create(:push_message, sender: user)
        message.update_column(:message_type, "CallbackUser")

        expect(serialize(message_class.find(message.id), only: %w[id],
          include: {subject: {only: %w[id], methods: %w[our_external_callback]}}))
          .to eq("id" => message.id, "subject" => {"id" => user.id})
        expect(calls).to be_empty
      end
    end

    it "log each dropped name once per request" do
      allow(Rails.logger).to receive(:warn)

      serialize([record, record], only: %w[id], methods: %w[destroy])

      expect(Rails.logger).to have_received(:warn).with(/Role#destroy dropped \(not written in the app or a thecore gem\)/).once
    end
  end

  describe "include" do
    let(:user) { create(:user).tap { |u| u.roles << role } }

    it "keeps real associations and applies the rules to the associated records" do
      expect(serialize(user, only: %w[id], include: {roles: {only: %w[name], methods: %w[destroy]}}))
        .to eq("id" => user.id, "roles" => [{"name" => "Reader"}])
      expect(Role.exists?(role.id)).to be(true)
    end

    it "accepts the array form" do
      expect(serialize(user, only: %w[id], include: %w[roles destroy]).keys).to eq(%w[id roles])
    end

    it "follows a polymorphic association with the rules of each record's own class" do
      # The dummy app's only polymorphic association is Active Storage's, which it doesn't
      # configure: a test-only one over PushMessage's existing sender_user_id / message_type.
      klass = Class.new(PushMessage) do
        def self.name = "PushMessage"
        belongs_to :subject, polymorphic: true, foreign_key: :sender_user_id, foreign_type: :message_type, optional: true
      end
      message = create(:push_message, sender: user)
      message.update_column(:message_type, "User")

      expect(serialize(klass.find(message.id), only: %w[id], include: {subject: {only: %w[email], methods: %w[destroy]}}))
        .to eq("id" => message.id, "subject" => {"email" => user.email})
      expect(User.exists?(user.id)).to be(true)
      expect(serialize(klass.find(message.id), only: %w[id], include: {subject: {only: %w[id], include: {roles: {only: %w[name]}}}}))
        .to eq("id" => message.id, "subject" => {"id" => user.id, "roles" => [{"name" => "Reader"}]})
    end
  end

  it "applies the same rules to ActiveModel objects a custom action returns" do
    summary_class = Class.new do
      include ActiveModel::Serializers::JSON

      def self.name = "Summary"
      def attributes = {"title" => nil}
      def title = "Summary"
      def wipe_roles = Role.delete_all
      def total = Role.count
    end
    role

    expect(serialize(summary_class.new, methods: %w[wipe_roles total instance_variables]))
      .to eq("title" => "Summary", "total" => 1)
    expect(Role.exists?(role.id)).to be(true)
  end

  it "leaves options built by the code untouched" do
    expect(role.as_json(only: %w[id], methods: %w[destroy])).to have_key("destroy")
  end
end
