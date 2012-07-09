Mongoid Lazy Migration
======================

![Build Status](https://secure.travis-ci.org/nviennot/mongoid_lazy_migration.png?branch=master)

LazyMigration allows you to migrate your document on the fly.
The migration is run when an instance of your model is initialized.
While your frontend servers are migrating the documents on demand, some workers
traverse the collection to migrate all the documents.

It allows your application logic to be tolerant from having only a portion of
the collection migrated. We use it at [Crowdtap](http://crowdtap.it/about-us).

LazyMigration is designed to support only one production environment. There are
no versioning as opposed to traditional ActiveRecord migrations.
With this in mind, the migration code is directly implemented in the model
itself, as opposed to having a decorator.
Once the migration is complete, the migration code must be deleted, and code
must be redeployed before cleaning up the database.

LazyMigration has two modes of operations: *atomic* and *locked*.
Atomic is the default one, which is less prone to fuck ups, but adds
constrains on what you can do during your migration.

Atomic Mode
-----------

Your migration code must respect a few constrains:

1. Your migrate code should never write anything to the database.
   You should not call save yourself, but let LazyMigration do it.
   Basically you are only allowed to set some document fields.
2. Your migrate code should be deterministic (don't play with Random)
   to keep some sort of consistency even in the presence of races with
   migrations.

When multiple clients are trying to perform the migration at the same
time, all of them will run the migration code, but only one will commit
the changes to the database.
After the migration, the document will not be reloaded, regardless if the
write to the database happened. This implies that the field values are
the one from the migration, and may not correspond to what is actually in
the database. Which is why using a non deterministic migration is not
recommended.

### Migration States

A document migration goes through the following states:

1. pending: the migration needs to be performed.
2. done: the migration is complete.

### Atomic Migration Example

Suppose we have a model `GroupOfPeople` with two fields: `num_males` and
`num_females`.
We wish to add a field `num_people`. Here is how it goes:

```ruby
class GroupOfPeople
  include Mongoid::Document
  include Mongoid::LazyMigration

  field :num_males,   :type => Integer
  field :num_females, :type => Integer
  field :num_people,  :type => Integer

  migration do
    self.num_people = num_males + num_females
  end

  def inc_num_people
    self.inc(:num_people, 1)
  end
end
```

Note that calling `inc_num_people` is perfectly fine in presence of contention
because only one client will be able to commit the migration to the database.

Locked Mode
-----------

The locked mode  guarantees that only one client will run the migration code,
because a lock is taken. As a consequence, your migration code can pretty much
do anything.

In case of contention, the other clients will have to wait until the migration
is complete. This has some heavy consequences: if the owner of the lock dies
(exception, ctrl+c, lost the ssh connection, asteroid crashes on your
datacenter, ...) the document will stay locked in the processing state. There
is no rollback. You are responsible to clean up the mess. Be aware that you
cannot instantiate a document stuck in locked state state without removing
the migration block.

Because of the locking, a locked migration runs slower than an atomic one.

### Migration States

A document migration goes through the following states:
1. pending: the migration needs to be performed.
2. processing: the document is being migrated, blocking other clients.
3. done: the migration is complete.

### Locked Migration Example

Suppose we have a model `GroupOfPeople` with an array `people_names`, which is
an array of strings. Our migration consists of introducing a new model `Person`,
and removing the array `people_names` from `GroupOfPeople`. Here it goes:

```ruby
class Person
  include Mongoid::Document

  field :name, :type => String
  belongs_to :group_of_people
end

class GroupOfPeople
  include Mongoid::Document
  include Mongoid::LazyMigration

  field :people_names, :type => Array
  has_many :people

  migration(:lock => true) do
    people_names.each do |name|
      self.people.create(:name => name)
    end
  end
end
```

Since only one client can execute the migration block, we are guaranteed that
we only create the associations once.

Just to be safe, we don't unset the `people_names` in the migration. It would
be done manually once the migration is complete.

Background Migration
--------------------

While the frontend servers are migrating models on demand, it is recommended to
migrate the rest of the collection in the background.

It can be done programmatically:

* `Mongoid::LazyMigration.migrate` will migrate all the models that have a
  migration block.
* `Mongoid::LazyMigration.migrate(Model)` will only migrate `Model`.
* `Mongoid::LazyMigration.migrate(Model.where(:active => true))` will only
  migrate the active models.

A rake task is provided to call the migrate() method:

* `rake db:mongoid:migrate`
* `rake db:mongoid:migrate[Model]`
* `rake db:mongoid:migrate[Model.where(:active => true)]`

Both methods display a progress bar.

It is recommended to migrate the most accessed documents first so they don't
need to be migrated when a user requests them. It is also possible to use
multiple workers. Example:

Worker 1:
```ruby
rake db:mongoid:migrate[User.where(:shard => 1, :active => true)]
rake db:mongoid:migrate[User.where(:shard => 1, :active => false)]
```

Worker 2:
```ruby
rake db:mongoid:migrate[User.where(:shard => 2, :active => false)]
rake db:mongoid:migrate[User.where(:shard => 2, :active => true)]
```

Cleaning up
-----------

Once all the document have their migration state equal to done, you must
cleanup your collection (removing the migration_state field) to clear some
database space, and to ensure that you can run a future migration.

The two ways to cleanup a model are:

* `Mongoid::LazyMigration.cleanup(Model)`
* `rake db:mongoid:cleanup_migration[Model]`

The cleanup process will abort if any of the document migrations are still in
the processing state, or if you haven't removed the migration block.

Important Considerations
------------------------

A couple of points that you need to be aware of:

* Because the migrations are run during the model instantiation,
  using some query like `Member.count` will not perform any migration.
  With the same rational, If you do something sneaky in your application by
  interacting directly with the mongo driver and bypassing mongoid, you are on
  your own.
* If you use only() in some of your queries, make sure that you include the
  `migration_state` field.
* Do not use identity maps and threads at the same time. It is currently
  unsupported, but support may be added in the future.
* Make sure you can migrate a document quickly, because migrations will be
  performed while processing user requests.
* SlaveOk is fine, even in locked mode.
* save() will be called on the document once done with the migration, don't
  do it yourself.
* The save and update callbacks will not be called when persisting the
  migration.
* No validation will be performed during the migration.
* The migration will not update the `updated_at` field.

You can pass a criteria to `Mongoid::LazyMigration.migrate` (used at step 4
of the recipe). It allows you to:

* Update your most important document first (like your active members),
  and do the rest after.
* Use many workers on different shards of your database. Note that it is
  safe to try migrating the same document by different workers, but not
  recommended for performance reasons.

Workflow
--------

You may use the following recepe to perform a migration:

1. Run `rake db:mongoid:cleanup[Model]` just to be safe.
2. Include Mongoid::LazyMigration in your document and write your migration
   specification. Modify your application code to reflect the changes from the
   migration.
3. Deploy.
4. Run `rake db:mongoid:migrate`.
5. Remove the migration block from your model.
6. Deploy.
7. Run `rake db:mongoid:cleanup[Model]`.

Compatibility
-------------

LazyMigration is tested against against MRI 1.8.7, 1.9.2, 1.9.3, JRuby-1.8, JRuby-1.9.

Only Mongoid 2.4.x is currently supported.

License
-------

LazyMigration is distributed under the MIT license.
