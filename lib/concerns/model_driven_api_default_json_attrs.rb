# Registered into ThecoreBackendCommons::DefaultModuleRegistry (see
# config/initializers/default_json_attrs_registration.rb) so it is
# automatically `include`d into *every* `ApplicationRecord` subclass at
# class-definition time -- not just the handful of named classes
# (ModelDrivenApiUser, ModelDrivenApiRole, ...) that get a bespoke concern.
#
# See vendor/external/thecore/docs/adr/0001-application-record-defaults-over-generated-concerns.md
# in the host app for the design rationale: default model behavior should
# not require a generated per-model `Api::ModelName` concern file for the
# no-customization case.
#
# A model that *does* need custom serialization still gets (or keeps) an
# explicit `Api::ModelName` concern, `include`d directly in the model file
# exactly as today -- because `ApplicationRecord.inherited` (which applies
# this default) fires *before* the subclass's own body executes, that later
# explicit `include` always runs after this default has already set
# `json_attrs`, so it freely overrides (or, via `ModelDrivenApi.smart_merge`,
# merges on top of) the default's value. See `ModelDrivenApiUser`/
# `ModelDrivenApiRole` for that pattern.
module ModelDrivenApiDefaultJsonAttrs
  extend ActiveSupport::Concern

  included do
    ## DSL (AKA what to show in the returned JSON)
    # Use self.json_attrs to drive json rendering for
    # API model responses (index, show and update ones).
    # For reference:
    # https://api.rubyonrails.org/classes/ActiveModel/Serializers/JSON.html
    # The object passed accepts only these keys:
    # - only: list [] of model field names in symbol notation to be shown in JSON
    #       serialization.
    # - except: exclude these fields from the JSON serialization, is a list []
    #        of model field names in symbol notation.
    # - methods: include the result of some methods defined in the model (virtual
    #       fields).
    # - include: include associated models, it's a list [] of hashes {} which also
    #       accepts the [:only, :except, :methods, :include] keys.
    #
    # Default shape: no `only`/`except` restriction beyond the empty array
    # below (so every column is serialized), no `methods`, no `include` (no
    # associations sideloaded) -- the simplest safe default for a model that
    # has no customization needs. `cattr_accessor` (not a plain method
    # definition) is required so `json_attrs` lands as an *own* method on
    # each concrete model class -- `Api::V2::InfoController#schema`/`#dsl`
    # check `instance_methods(false).include?(:json_attrs)` while walking
    # `ApplicationRecord.subclasses`, and a merely-inherited method would
    # silently fail that check and drop the model from introspection output.
    cattr_accessor :json_attrs
    self.json_attrs = { except: [] }
  end
end
