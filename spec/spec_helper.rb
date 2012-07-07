require 'rubygems'
require 'bundler'
Bundler.require(:default, :test)

Mongoid.configure do |config|
  database = Mongo::Connection.new('localhost', 27017).db('lazy_test')
  database.add_user("mongoid", "test")
  config.master = database
end

RSpec.configure do |config|
  config.mock_with :mocha
  config.color_enabled = true

  config.before do
    Mongoid.database.collections.each do |collection|
      unless collection.name.include?('system')
        collection.remove
      end
    end
  end
end
