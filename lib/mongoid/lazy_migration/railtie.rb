module Mongoid::LazyMigration
  class Railtie < Rails::Railtie
    rake_tasks { load 'mongoid/lazy_migration/railtie/migrate.rake' }
  end
end
