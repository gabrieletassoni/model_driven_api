module ModelDrivenApi
  VERSION = "#{`git describe --tags $(git rev-list --tags --max-count=1)`}"
end
