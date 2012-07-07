require 'spec_helper'
require 'support/models'
require 'support/mute_progressbar'

describe Mongoid::LazyMigration, ".migrate" do
  let!(:pendings_lock)   { 5.times { ModelLock.collection.insert({})} }
  let!(:pendings_atomic) { 5.times { ModelAtomic.collection.insert({})} }

  it "migrates all the models by default" do
    ModelLock.where(:migrated => true).count.should == 0
    ModelAtomic.where(:migrated => true).count.should == 0
    Mongoid::LazyMigration.migrate
    ModelLock.where(:migrated => true).count.should == 5
    ModelAtomic.where(:migrated => true).count.should == 5
  end

  it "migrates all the documents of a specific class" do
    ModelLock.where(:migrated => true).count.should == 0
    Mongoid::LazyMigration.migrate(ModelLock)
    ModelLock.where(:migrated => true).count.should == 5

    ModelAtomic.where(:migrated => true).count.should == 0
  end

  it "supports a criteria" do
    ModelLock.where(:migrated => true).count.should == 0
    Mongoid::LazyMigration.migrate(ModelLock.limit(2))
    ModelLock.where(:migrated => true).count.should == 2
  end
end

describe Mongoid::LazyMigration, ".cleanup" do
  let!(:done1) { ModelNoMigration.collection.insert(:migration_state => :done) }
  let!(:done2) { ModelNoMigration.collection.insert(:migration_state => :done) }

  it "cleans up all the documents of a specific class" do
    Mongoid::LazyMigration.cleanup(ModelNoMigration)
    ModelNoMigration.where(:migration_state => nil).count.should == 2
  end

  it "chokes if any documents are still being processed" do
    ModelNoMigration.collection.insert(:migration_state => :processing)
    proc { Mongoid::LazyMigration.cleanup(ModelNoMigration) }.should raise_error
    ModelNoMigration.where(:migration_state => nil).count.should == 0
  end

  it "chokes if the migration is still defined" do
    proc { Mongoid::LazyMigration.cleanup(ModelAtomic) }.should raise_error
  end
end
