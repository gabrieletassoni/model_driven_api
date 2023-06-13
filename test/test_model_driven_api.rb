# frozen_string_literal: true

require "test_helper"

class ModelDrivenApiTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::ModelDrivenApi::VERSION
  end

  def test_all_models_have_crud
    Zeitwerk::Loader.eager_load_all
    ApplicationRecord.descendants.each do |model|
      refute_nil model
    end
  end
end
