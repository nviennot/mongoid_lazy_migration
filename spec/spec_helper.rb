require 'rubygems'
require 'bundler'
Bundler.require(:default, :test)

HOST = ENV['MONGOID_SPEC_HOST'] || 'localhost'
PORT = ENV['MONGOID_SPEC_PORT'] || '27017'
DATABASE = 'mongoid_lazy_migration_test'

Mongoid.configure do |config|
  database = Mongo::Connection.new(HOST, PORT.to_i).db(DATABASE)
  config.master = database
  config.logger = nil
end

RSpec.configure do |config|
  config.mock_with :mocha
  config.color_enabled = true

  config.before(:each) do
    Mongoid.database.collections.each do |collection|
      unless collection.name.include?('system')
        collection.remove
      end
    end
    Mongoid::IdentityMap.clear
  end

  config.after(:suite) do
    Mongoid.master.connection.drop_database(DATABASE)
  end
end
