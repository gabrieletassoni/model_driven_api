module ModelDrivenApi
  VERSION = "#{`git describe --tags $(git rev-list --tags --max-count=1)`.chomp}"
  # VERSION = "3.0.0"
end
