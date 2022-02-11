$:.push File.expand_path("lib", __dir__)

# Maintain your gem's version:
require "model_driven_api/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |spec|
  spec.name        = "model_driven_api"
  spec.version     = ModelDrivenApi::VERSION
  spec.authors     = ["Gabriele Tassoni"]
  spec.email       = ["gabriele.tassoni@gmail.com"]
  spec.homepage    = "https://github.com/gabrieletassoni/model_driven_api"
  spec.summary     = "Convention based RoR engine which uses DB schema introspection to create REST APIs."
  spec.description = "Ruby on Rails REST APIs built by convention using the DB schema as the foundation, please see README for mode of use."
  spec.license     = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata["allowed_push_host"] = "https://rubygems.org"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  spec.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]

  spec.add_dependency "thecore_backend_commons", "~> 2.4"
  spec.add_dependency "jwt", "~> 2.2"

  spec.add_dependency "simple_command", "~> 0.1"
  spec.add_dependency "kaminari", "~> 1.2"

  spec.add_dependency 'ransack', "~> 2.3"
  
  spec.add_dependency 'rack-cors', "~> 1.1"

  spec.add_dependency 'multi_json', '~> 1.14'

  # Intelligent Merging (recursive and recognizes types)
  # https://github.com/danielsdeleo/deep_merge
  spec.add_dependency "deep_merge", '~> 1.2'
end
