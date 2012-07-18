module Mongoid::LazyMigration::Tasks
  def migrate(criteria=nil)
    require 'progressbar'

    criterias = criteria.nil? ? Mongoid::LazyMigration.models_to_migrate : [criteria]
    criterias.each do |criteria|
      to_migrate = criteria.where(:migration_state.ne => :done)
      progress = ProgressBar.new(to_migrate.klass.to_s, to_migrate.count)
      progress.long_running
      to_migrate.each { progress.inc }
      progress.finish
    end
    true
  end

  def cleanup(model)
    if model.in? Mongoid::LazyMigration.models_to_migrate
      raise "Remove the migration from your model before cleaning up the database"
    end

    if model.where(:migration_state => :processing).limit(1).count > 0
      raise ["Some models are still being processed.",
             "Remove the migration code, and go inspect them with:",
             "#{model}.where(:migration_state => :processing))",
             "Don't forget to remove the migration block"].join("\n")
    end

    selector = { :migration_state => { "$exists" => true }}
    changes  = {"$unset" => { :migration_state => 1}}
    safety   = { :safe => true, :multi => true }
    multi    = { :multi => true }

    if Mongoid::LazyMigration.mongoid3
      model.with(safety).where(selector).query.update(changes, multi)
    else
      model.collection.update(selector, changes, safety.merge(multi))
    end
  end
end
