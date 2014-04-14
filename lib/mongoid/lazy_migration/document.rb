module Mongoid::LazyMigration::Document
  def ensure_migration
    self.migration_state = :done if new_record?

    @migrating = true
    perform_migration if migration_state == :pending
    wait_for_completion if migration_state == :processing
    @migrating = false
  end

  def atomic_selector
    return super unless @migrating

    if @running_migrate_block && !self.class.lock_migration
        raise ["You cannot save during an atomic migration,",
               "You are only allowed to set the document fields",
               "The document will be commited once the migration is complete.",
               "If you need to get fancy, like creating associations, use :lock => true"
        ].join("\n")
    end

    # see perform migration
    super.merge('migration_state' => { "$ne" => 'done' })
  end

  def run_callbacks(*args, &block)
    return super(*args, &block) unless @migrating

    block.call if block
  end

  private

  def perform_migration
    # For locked migrations, perform_migration is bypassed when raced by
    # another client. We busy wait until the other client is done with the
    # migration in wait_for_completion.
    return if self.class.lock_migration && !try_lock_migration

    begin
      self.class.skip_callback :create, :update, :set_updated_at

      @running_migrate_block = true
      instance_eval(&self.class.migrate_block)
      @running_migrate_block = false

      # For atomic migrations, save() will be performed with the
      # following additional selector (see atomic_selector):
      #   :migration_state => { "$ne" => :done }
      # This guarantee that we never commit more than one migration on a
      # document, even though we are not taking a lock.
      # Since we do not call reload on the model in case of a race, it is
      # preferable to have a deterministic migration to avoid surprises.
      self.migration_state = :done
      save(:validate => false)
    ensure
      self.class.set_callback :create, :update, :set_updated_at
    end
  end

  def try_lock_migration
    # try_lock_migration returns true if and if only the document
    # transitions from the pending to the progress state. This operation is
    # done atomically by MongoDB (test and set).
    self.migration_state = :processing

    selector = atomic_selector.merge('migration_state' => { "$in" => [nil, 'pending'] })
    changes  = { "$set" => { 'migration_state' => 'processing' }}
    safety   = { :safe => true }

    if Mongoid::LazyMigration.mongoid3
      self.class.with(safety).where(selector).query.update(changes)
    else
      collection.update( selector, changes, safety)
    end['updatedExisting']
  end

  def wait_for_completion
    # We do not explicitly sleep during the loop in the hope of getting a
    # lower latency. reload() sleeps anyway waiting for mongodb to respond.
    # Besides, this is a corner case since contention should be very low.
    reload until migration_state == :done
  end
end
