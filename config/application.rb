require "bundler/setup"
require "rage"
Bundler.require(*Rage.groups)

require "rage/all"

Rage.configure do
  # use this to add settings that are constant across all environments
  config.logger = Rage::Logger.new($stdout)
end

# Explicitly load lib files since Rage only autoloads app/controllers and app/models
Dir[File.join(__dir__, "../app/lib/**/*.rb")].each { |f| require f }

require "rage/setup"
