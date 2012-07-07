require 'spec_helper'
require 'support/models'

describe Mongoid::LazyMigration::Document, "models_to_migrate" do
  it "returns the list of models performing a lazy migration" do
    Mongoid::LazyMigration.models_to_migrate.to_a.should =~ [ModelLock, ModelAtomic]
  end
end
