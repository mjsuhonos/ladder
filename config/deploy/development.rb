#If we're not deploying to production, assume we're deploying to a local Vagrant
# box for testing our deployment scripts.  In this case, the default ssh port is
# 2222
set :ssh_options, { :forward_agent => true,
                    :port => 2222,
                    :keys => [File.join(ENV["HOME"], ".ssh", "github_rsa")]
}

role :web, "localhost"
role :app, "localhost"
role :db,  "localhost", :primary => true 
set :server, "localhost"

set :unicorn_env, "development"
set :rails_env, "development" # For Sidekiq Rails-centric-ness of their cap task

# We want to deploy the development gems with bundler in dev mode
# The cap task defaults to --without development,test. We'll overwrite
# that with an empty array to get those gems
set :bundle_without,  []