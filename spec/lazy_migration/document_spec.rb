require 'spec_helper'
require 'support/models'

describe Mongoid::LazyMigration::Document, ".migration(lock)" do
  let(:pending)    { ModelLock.collection.insert({})}
  let(:processing) { ModelLock.collection.insert(:migration_state => :processing) }
  let(:done)       { ModelLock.collection.insert(:migration_state => :done) }

  it "migrates pending models on fetch" do
    ModelLock.find(pending).migrated.should == true
  end

  it "doesn't migrate done models on fetch" do
    ModelLock.find(done).migrated.should_not == true
  end

  it "busy waits when a model has a migration in process" do
    # I don't know how to test this.
  end

  it "never lets two migrations happen at the same time on the same model" do
    # I don't know how to test this.
  end

  it "doesn't update the updated_at field during the migration" do
    model = ModelLock.find(pending)
    model.updated_at.should == nil
    model.some_field = "bacon"
    model.save
    model.updated_at.should_not == nil
  end
end

describe Mongoid::LazyMigration::Document, ".migration(atomic)" do
  let(:pending)    { ModelAtomic.collection.insert({})}
  let(:processing) { ModelAtomic.collection.insert(:migration_state => :processing) }
  let(:done)       { ModelAtomic.collection.insert(:migration_state => :done) }

  it "migrates pending models on fetch" do
    ModelAtomic.find(pending).migrated.should == true
  end

  it "doesn't migrate done models on fetch" do
    ModelAtomic.find(done).migrated.should_not == true
  end

  it "never lets two migrations to be commit to the database for the same model" do
    # I don't know how to test this.
  end
end

describe Mongoid::LazyMigration::Document, ".migration" do
  it "does not run any save/update callbacks" do
    class ModelCallbacks
      include Mongoid::Document
      include Mongoid::LazyMigration
      cattr_accessor :callback_called
      @@callback_called = 0

      field :some_field
      migration {}

      before_save   { self.class.callback_called += 1 }
      after_save    { self.class.callback_called += 1 }
      before_update { self.class.callback_called += 1 }
      after_update  { self.class.callback_called += 1 }
    end
    Mongoid::LazyMigration.models_to_migrate.delete(ModelCallbacks)

    id = ModelCallbacks.collection.insert({})
    model = ModelCallbacks.find(id)
    ModelCallbacks.callback_called.should == 0

    model.some_field = "bacon"
    model.save
    ModelCallbacks.callback_called.should == 4
  end

  it "does not validate" do
    class ModelValidate
      include Mongoid::Document
      include Mongoid::LazyMigration
      cattr_accessor :migration_count
      @@migration_count = 0

      field :some_field
      validates_presence_of :some_field
      migration do
        self.class.migration_count += 1
      end
    end
    Mongoid::LazyMigration.models_to_migrate.delete(ModelValidate)

    id = ModelValidate.collection.insert({})
    ModelValidate.find(id)
    ModelValidate.find(id)
    ModelValidate.migration_count.should == 1
  end

  it "does not allow saving during the migration" do
    class ModelInvalid
      include Mongoid::Document
      include Mongoid::LazyMigration
      field :some_field
      migration do
        self.some_field = "bacon"
        self.save
      end
    end
    Mongoid::LazyMigration.models_to_migrate.delete(ModelInvalid)

    id = ModelInvalid.collection.insert({})
    proc { ModelInvalid.find(id) }.should raise_error
  end

  describe "#atomic_selector" do
    it 'returns the original selector when not doing a migration' do
      m = ModelAtomic.create
      m.atomic_selector.should == { "_id" => m._id }
    end
  end

end
