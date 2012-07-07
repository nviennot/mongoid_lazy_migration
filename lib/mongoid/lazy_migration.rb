require 'active_support/concern'
require 'active_support/core_ext'
require 'set'

module Mongoid
  module LazyMigration
    require 'mongoid/lazy_migration/version'
    require 'mongoid/lazy_migration/document'
    require 'mongoid/lazy_migration/tasks'

    extend ActiveSupport::Concern
    extend Tasks

    mattr_reader :models_to_migrate
    @@models_to_migrate = Set.new

    module ClassMethods
      def migration(options = {}, &block)
        include Mongoid::LazyMigration::Document

        field :migration_state, :type => Symbol, :default => :pending
        after_initialize :ensure_migration, :unless => proc { @migrating }

        cattr_accessor :migrate_block, :lock_migration
        self.migrate_block = block
        self.lock_migration = options[:lock]

        Mongoid::LazyMigration.models_to_migrate << self
      end
    end

  end
end

require "mongoid/lazy_migration/railtie" if defined?(Rails)
