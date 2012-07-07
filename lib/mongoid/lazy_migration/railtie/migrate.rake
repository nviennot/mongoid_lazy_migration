namespace :db do
  namespace :mongoid do
    desc 'Migrate the documents specified by criteria. criteria is optional'
    task :migrate, [:criteria] => :environment do |t, args|
      criteria = args.criteria ? eval(args.criteria) : nil
      Mongoid::LazyMigration.migrate(criteria)
    end

    desc 'Cleanup a migration'
    task :cleanup_migration, [:model] => :environment do |t, args|
      raise "Please provide a model" unless args.model
      Mongoid::LazyMigration.cleanup(eval(args.model))
    end
  end
end
