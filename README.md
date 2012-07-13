Mongoid Lazy Migration
======================

[![Build Status](https://secure.travis-ci.org/nviennot/mongoid_lazy_migration.png?branch=master)](http://travis-ci.org/nviennot/mongoid_lazy_migration)

LazyMigration allows you to migrate a Mongoid collection on the fly. As
instances of your model are initialized, the migration is run. In the
background, workers can traverse the collection and migrate other documents.
Thus, your application acts as though your migration as already taken place.

LazyMigration can be used for any app which uses Mongoid. It is most commonly
used for Rails apps. We use it at [Crowdtap](http://crowdtap.it/about-us).


Workflow
--------

Once installed with

```ruby
gem 'mongoid_lazy_migration'
```

You can use the following recipe to perform a migration:

1. Include Mongoid::LazyMigration in your document and write your migration
   specification. Modify your application code to reflect the changes from the
   migration.
2. Deploy.
3. Run `rake db:mongoid:migrate`.
4. Remove the migration block from your model.
5. Deploy.
6. Run `rake db:mongoid:cleanup[Model]`.

The migration specification can be written in one of two modes: *atomic* or
*locked*. Atomic is the default, and is tolerant to dying workers, but it
introduces some constraints on your migration.

Atomic Mode (default)
---------------------

### Constraints

Atomic migration code must respect a few constrains:

1. It can never write anything to the database. This means you should not call
   save yourself; LazyMigration will do this for you. Essentially, you should
   only be setting document fields.
2. It must be deterministic to ensure consistency in the face of migration races.

### Migration States

A document migration goes through the following states:

1. pending: the migration needs to be performed.
2. done: the migration is complete.

### Atomic Migration Example

Suppose we have a model GroupOfPeople with two fields: num_males and
num_females. We wish to add the field num_people. We can do this as follows:

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

  # This can be used by other code while the migration is running
  # because it is atomic
  def inc_num_people
    self.inc(:num_people, 1)
  end
end
```

Note that calling inc_num_people is perfectly fine in presence of contention
because only one client will be able to commit the migration to the database.

Locked Mode
-----------

Locked mode guarantees that only one client will run the migration code, because
it uses locking. Thus, the restrictions on an atomic migration are removed.

However, this has some consequences. Most importantly, if the owner of the lock
dies (exception, ctrl+c, a lost ssh connection, an explosion in your
datacenter, etc.), the document will stay locked in the processing state.
There is no automatic rollback. You are responsible for cleaning up. Be aware
that you cannot instantiate a document stuck in locked state state without
removing the migration block.

Because the lock involves additional database requests, including writes,
a locked migration runs slower than an atomic one.

### Migration States

A document migration goes through the following states:

1. pending: the migration needs to be performed.
2. processing: the document is being migrated, blocking other clients.
3. done: the migration is complete.

### Locked Migration Example

Suppose we have a model GroupOfPeople with an array people_names, which is an

an array of strings. Our migration consists of introducing a new model called
Person and removing the array people_names from GroupOfPeople.

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

We cannot perform an atomic migration in this case because new documents are
created while running the migration block.  In locked mode, we are guaranteed
that we only create the associations once.

Since only one client can execute the migration block, we are guaranteed that
we only create the associations once.

Notice that we don't unset the people_names field in the migration. We keep it
until the entire collection has migrated allowing us to rollback in case of
failure.

Background Migration
--------------------

While the some of your server migrating models on demand, it is recommended to
migrate the rest of the collection in the background. Otherwise, if one
document in your collection is not accessed for a year, your migration will
take one year to complete.

A rake task is provided:

```ruby
# Migrate all the documents that have a pending migration
rake db:mongoid:migrate

# Migrate all the documents of GroupOfPeople
rake db:mongoid:migrate[GroupOfPeople]

# Migrate all the documents of GroupOfPeople that have specific people in the group
rake db:mongoid:migrate[GroupOfPeople.where(:people_names.in => ["marie", "joelle"])]
```

Note that you might need to use single quotes around the whole rake argument,
otherwise your shell might be tempted to evaluate the expression.

The task displays a progress bar.

For performance, it is recommended to migrate the most accessed documents first
so they don't need to be migrated when a user requests them. You can also use
multiple workers on different shards.

If your database doesn't fit entirely in memory, be very careful when migrating
rarely accessed documents since your working set may be evicted from cache.
MongoDB could start trashing in unexpected ways.

The migration is be performed one document at a time, so we avoid holding up
the global lock on MongoDB for long period of time.

Only atomic migration can be safely aborted with Ctrl+C. Support for aborting a
locked migration will be added in the future.

Cleaning up
-----------

Once all the document have their migration state equal to done, you must do two things:

1. Remove the migration block from your model.
2. Cleanup the database (removing the migration_state field) to ensure that you
   can run a future migration with the following rake task:

```ruby
rake db:mongoid:cleanup_migration[Model]
```

The cleanup process will be aborted if any of the document migrations are still
the processing state or if you haven't removed the migration block.

Important Considerations
------------------------

A couple of points that you need to be aware of:

* save() will be called on the document once done with the migration. Don't
  do it yourself. It's racy in atomic mode and unnecessary in locked mode.
* save and update callbacks will not be called when persisting the migration.
* No validation will be performed during the migration.
* The migration will not update the `updated_at` field.
* LazyMigration is designed to support a single production environment and does
  not support versioning, unlike traditional ActiveRecord migrations. Thus, the
  migration code can be included directly in the model and can be removed after
  migration is done.
* Because the migrations are run during the model instantiation,
  using some query like `Member.count` will not perform any migration.
  Similarly, if you bypass Mongoid and use the Mongo driver directly in your
  application, LazyMigration might not be run.
* If you use only() in some of your queries, make sure that you include the
  migration_state field.
* Do not use identity maps and threads at the same time. It is currently
  unsupported, though support may be added in the future.
* Make sure you can migrate a document quickly, because migrations will be
  performed while processing user requests.
* SlaveOk is fine, even in locked mode.
* You might want to try a migration on a staging environment which replicates a
  production workload to evaluate the impact of the lazy migration.

Compatibility
-------------

LazyMigration is tested against against MRI 1.8.7, 1.9.2, 1.9.3, JRuby-1.8, JRuby-1.9.

Only Mongoid 2.4.x is currently supported.

License
-------

LazyMigration is distributed under the MIT license.
