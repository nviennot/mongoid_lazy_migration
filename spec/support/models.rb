class ModelAtomic
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::LazyMigration

  field :some_field
  field :migrated, :type => Boolean

  migration do
    self.migrated = true
  end
end

class ModelLock
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::LazyMigration

  field :some_field
  field :migrated, :type => Boolean

  migration(:lock => true) do
    self.migrated = true
  end
end

class ModelNoMigration
  include Mongoid::Document
  include Mongoid::Timestamps
  include Mongoid::LazyMigration

  field :some_field
  field :migrated, :type => Boolean
end
