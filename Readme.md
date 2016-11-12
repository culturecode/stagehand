## Stagehand [![Gem Version](https://badge.fury.io/rb/culturecode_stagehand.svg)](https://badge.fury.io/rb/culturecode_stagehand)

By [Culture Code](http://culturecode.ca/).

**Stagehand** is a gem that makes it easy to have a staging database where content editors can modify highly relational
data, and then publish those changes to a production database. It aims to solve the problem of being able to publish
specific content, while the latest changes to other content are still being worked on.

In a nutshell, the system is divided into two halves, Staging (where content is prepared by Admins), and Production
(where content is viewed by visitors). These two halves are backed by their own separate databases in order to ensure
that updates in the Staging area do not affect Production until they are ready.

It is important to note that the Production database acts as a cache of the staging database only, no changes are ever
made to it except to sync changes that have occurred in the staging database.

Key features:

- Allows published content to be edited without those changes immediately being seen by visitors
- Can selectively update content without needing to sync the entire database with production

## Compatibility

Stagehand currently supports MySQL, but could easily be adapted to work on multiple databases by modifying the database
triggers and session identification code.

## Setup
1. Add **Stagehand** to your Gemfile:

  ```ruby
  gem 'stagehand', :github => 'culturecode/stagehand'
  ```

2. Make a copy of your existing database, this will serve as the Production database, while your current database will
be used as the staging database.

3. Add stagehand to your staging database by using the `Stagehand::Schema.add_stagehand!` method. Tables not needed to
serve pages to site viewers can be ignored. This is useful if certain tables are only necessary in the
staging environment.

  ```ruby
    # In a migration
    Stagehand::Schema.init_stagehand! :except => [:users, :admin_messages, :other_tables, :not_needed_by_visitors]
  ```

  Monitoring is achieved using database triggers. Three triggers (INSERT, UPDATE, DELETE) are added to each monitored
  table and are used to create log entries that are used to track changes to content in the staging area.

  You can add stagehand to new tables in subsequent migrations as follows:

  ```ruby
  # In a migration
  Stagehand::Schema.add_stagehand! :only => [:some, :new, :tables]
  ```

  From now on, when creating a table Stagehand will allow you to declare whether or not that table is for use in
  the production database. Logging triggers are added automatically unless `:stagehand => false` is passed.

  ```ruby
  # In a migration

  create_table :my_table_used_in_production do |t|
    # etc...
  end

  create_table :my_other_table_used_just_for_staging, :stagehand => false do |t|
    # etc...
  end
  ```

4. Modify the environment configuration file to specify which database to use for staging and which to use for
production. The connection name should match whatever names you've used in `database.yml`.

  ```yaml
  # In your database.yml
  staging:
    adapter: mysql2
    database: admin_staging

  production:
    adapter: mysql2
    database: production_live  
  ```

  ```ruby
  # In your production.rb, development.rb, etc...
  config.x.stagehand.staging_connection_name = :staging
  config.x.stagehand.production_connection_name = :production
  ```

5. Include the `Stagehand::Production::Controller` and `Stagehand::Staging::Controller` modules to set which controllers use the production and staging databases, respectively.

  ```ruby
  class ApplicationController < ActionController::Base
    include Stagehand::Production::Controller # This controller and all subclasses will connect to the production database
  end

  class AdminController < ApplicationController
    include Stagehand::Staging::Controller  # This controller and all subclasses will connect to the staging database
  end
  ```

  If there are writes to the database that are triggered in a "Production" controller, be sure to direct them to the staging database if   necessary.

  ```ruby
  class MyModel
    include Stagehand::Staging::Model # Connects to staging database even when used within a production controller
  end
  ```

## Usage

Syncing is the process of copying modified records from the staging database to the production database. Changes may
include creation of a record, updates to that record, or deletion of that record. Each time a record is modified, a log
entry is added to the `stagehand_commit_entries` table using database triggers. This table is used to keep track of what
records in the staging database need to be synchronized to the production database, as well as provide the data
necessary to perform more advanced syncing operations.

### Staging Changes

To prevent modifications from being synced to the database without user confirmation, you can wrap blocks of changes in
a Commit. This bundles the changes together and forces them to be synchronized manually. The typical usecase for this is
to track changes made in a controller action like create or update.

```ruby
# In an action in any controller that includes Stagehand::Staging::Controller
def create
  stage_changes do |commit|
    # database modifications to be confirmed before syncing
    commit.subject = Record.create # Subject is set during the block, after it is created
  end
end

def update
  stage_changes(@subject_record) do # Subject can be set while opening the block since it already exists
    # database modifications to be confirmed before syncing
  end
end
```

```ruby
# ... or anywhere you want to ensure a set of changes are synchronized to the production database together
Stagehand::Staging::Commit.capture(subject_record) do
  # database modifications
end
```

Any database changes that take place within the block will logged as part of a Commit. Commits are used when determining
what additional records to sync when syncing a specific record. For instance, if creating a record updates another
record in the process, the commit will ensure that manual syncing copies both the new record and the updated record.

Note, in these examples, the subject of the commit is being set. Doing so allows commits to be associated with each
other, even if they do not modify the same records, e.g. if a commit only updated nested attributes, setting the commit
subject will ensure the nested records are synced when the record is synced even if the record and its nested records
are never modified together in the same commit.

The `:except` option can be passed to `stage_changes` to exclude certain tables from a commit. This is useful if
inconsequential updates to a certain table (e.g. counter cache updates) are causing records to be linked together unnecessarily.
Note that commit entries for changes to these tables are still created, just not included in the commit.

```ruby
Stagehand::Staging::Commit.capture(subject_record, except: :components) do
  # updates to the components table will not be included in this commit
end
```

### Previewing Changes

Before syncing changes to the production database, it's a good idea to review what records will be copied in order to
maintain consistency while avoiding the need to copy the entire database. Use the Checklist to see what records should
be reviewed before syncing.

```ruby
  checklist = Stagehand::Staging::Checklist.new(subject_record)
  checklist.affected_records #=> Records that are directly or indirectly related to changes made to the subject record
  checklist.requires_confirmation #=> Affected Records whose changes should be checked by a user before syncing
  checklist.confirm_create #=> Requires Confirmation records that will be created in the production database
  checklist.confirm_update #=> Requires Confirmation records that will be updated in the production database
  checklist.confirm_delete #=> Requires Confirmation records that will be deleted in the production database
```

The checklist automatically treats changes to the subject as preconfirmed, excluding them from the list of records requiring confirmation.
Subjects can be your application's records, or Stagehand CommitEntry records. While passing a record to the checklist will confirm all
its CommitEntries, passing a CommitEntry as the subject will only preconfirm that entry, requiring confirmation for the record if other
entries for it exist. It is also possible to pass multiple subject records, making the checklist output the combined status of changes for
each subject.

To determine which records are related to the subject record, two methods of detection are used:

#### Related Records

If a commit contains multiple records, and other commits contain any of those records, they too will need to be synced
to maintain database consistency on production. To resolve all the interconnectedness between commits, and make it
simple to sync a record and changes to all affected records, use the Checklist to determine which records will be
synced, and which changes should be confirmed by the user.

In addition to records that were modified during related commits, other common operations are taken into account when
previewing changes.

#### Associated Records

If during a commit a record is saved and another record is assigned to it via a `has many :through` association, the
commit will contain an entry for the creation of the `:through` record that associates the two records. However, since
the record at the end of the through association was not modified during the commit, it will not be contained in the
commit.

| **Commit**               | **Uncontained**    |
|:-------------------------|:------------------:|     
|                          | Create - Vehicle 1 |
| Update - User 1          |                    |
| Create - ThroughRecord 1 |                    |

To work around this issue, the Checklist includes all `belongs_to` associations of records in the commit when detecting
what records need to be synced. In this case, ThroughRecord 1 has two `belongs_to` associations, one that points at the
User, and one that points at the Vehicle. Both of those records are then used to detect additional related records. This
ensures that if a record is published with a foreign key to another record, the association will not be orphaned if the
associated record does not already exist in the production database.

#### Options

For fine control over which records are returned by the `requires_confirmation` method, a filter block can be passed to
the constructor. Any records for which the block returns `true` will be included.

```ruby
Stagehand::Staging::Checklist.new(subject_record) do |affected_record|
  affected_record.published?
end
```

### Syncing Changes Manually

Manual syncing typically takes place in a a controller action where a user confirms the changes to records about to be
synced.

```ruby
# In an action in any controller that includes Stagehand::Staging::Controller
def update
  # ...
  sync_record(record) if params[:sync_confirmed]
  # ...
end
```

```ruby
# ... or anywhere you want
Stagehand::Staging::Synchronizer.sync_record(record)
```

To sync all changes regardless of whether confirmation is required, use the following commands:

```bash
rake stagehand:sync_all # Will sync all records and then exit
```

```ruby
Stagehand::Staging::Synchronizer.sync_all
```

### Syncing Changes Automatically

In addition to manually syncing records that require confirmation, you can set up automated synchronization of records
that don't require user confirmation. The Synchronizer polls the database to check for changes.

```bash
# Syncing can be handled at the command line using a rake task
rake stagehand:sync # Will sync records and then exit (can be use for scheduled syncs)
rake stagehand:sync[1000] # Will sync a 1000 entries and then exit
rake stagehand:auto_sync
rake stagehand:auto_sync[10] # Override default polling delay of 5 seconds
```

```ruby
# Syncing can also be handled in ruby
Stagehand::Staging::Synchronizer.auto_sync(5.seconds) # Optional delay can be customized. Set to falsey value for no delay.
```

### Immediate Syncing

If an automated task makes changes to the database that need to be synced together, these can be wrapped in a special
commit capture block that attempts an immediate sync. If the changes are unable to sync immediately due to
interconnectedness with other commits, they will remain unsynced in a commit block, ready to be synced when any of the
interconnected records are synced.

```ruby
# Syncing can also be handled in ruby
Stagehand::Staging::Synchronizer.sync_now do
  # Some automated task that does not require user confirmation
  # but that requires a block of changes to be synced together.
end
```


## ActiveRecord::Base Extensions

### Sync Callbacks

Stagehand extends ActiveRecord::Base with `before_sync` and `after_sync` callbacks. You can use these callbacks as you
would `before_save` and `after_save` callbacks to run code related to a sync.
NOTE: The only difference from typical ActiveRecord callbacks is that the callbacks are not run on the record instance
being synced, but instead are run on a new instance reloaded from the database.

### #synced?

Stagehand also adds a `synced?` method to ActiveRecord models to make it easy to display the sync status of a record in
the UI. The method uses the `stagehand_unsynced_indicator` association to detect if a CommitEntry exists for the record. The
association should be eager loaded to prevent n+1 queries whenever appropriate.


## Ghost Mode

Before rolling out the system to you users, it's a good idea to test that everything works as you'd expect. You can
enable the system "behind the scenes" by enabling Ghost Mode. In this mode database changes are still logged
but database connection swapping is disabled, so all controllers connect the database specified in your database.yml as
usual. The database connections used for auto synchronization will not be affected by Ghost Mode, allowing changes to be
previewed in the stagehand production database. Instead of only copying changes that don't require confirmation, in
Ghost Mode, auto synchronization will simulate immediate user confirmation of all changes and copy everything to the
production database.

|                 | **Visitor** | **Admin** | **Auto Sync to production**             |
|:----------------|:-----------:|:---------:|:---------------------------------------:|                 
|**Regular Mode** | Production  | Staging   | Changes that don't require confirmation |
|**Ghost Mode**   | Staging     | Staging   | All changes                             |


You can enable ghost mode in the environment
```ruby
# In your production.rb, development.rb, etc...
config.x.stagehand.ghost_mode = true
```

## Database Migrations

Both staging and production databases need to be migrated to allow syncing to occur. The default behaviour of db:migrate
has been enhanced to migrate both staging and production databases. If the two databases have different schema versions,
a `Stagehand::SchemaMismatch` exception will be raised when trying to sync.

### create_table

In order to minimize the chance new tables are not tracked for changes, the `create_table` schema migration method
is extended to automatically call `add_stagehand!` on the new table.

### rename_table

In order to ensure that change tracking triggers are not left recording the wrong table name after the table is renamed,
the `rename_table` schema migration method is extended to automatically `remove_stagehand!``


## Error Detection

### Unsynced Production Writes

Unsynced production writes occur when data is written directly to the production database without first being written
to the staging database. While models that are written while in a Production::Controller action can be designated as
Staging::Models, causing them to read and write to the staging database, unexpected writes may still be written directly
to the production database.

Take the following example, imagine a FormSubmission model that captures forms submitted by visitors. This model, while
created during a Production::Controller action, is designated as a Staging::Model because we always write to the Staging
database. Consider what would happen if the FormSubmission belonged to a Form, and if the Form keeps a counter cache
to of all its submissions. The Form model is not a Staging::Model because it is never saved during the
Production::Controller action... or is it? When the FormSubmission is created, it will be saved to staging, but it will
load and update the counter cache on the Form, causing an unsynced write to the production database.

By default Stagehand will raise an `Stagehand::UnsyncedProductionWrite` exception when this occurs. You can enable
unsynced production writes in the environment. Instead of raising an exception, warnings will be logged in Rails.

```ruby
# In your production.rb, development.rb, etc...
config.x.stagehand.allow_unsynced_production_writes = true
```

### Incomplete Commits

In order to achieve minimal impact on the normal operation of the app, Stagehand does not wrap Commits in a transaction.
This means if the app terminates unexpectedly, the entries that make up a Stagehand::Commit may not have been finalized
or even all exist. Stagehand is designed to limit the impact of such errors on normal logging and syncing behaviour,
however it is also possible to detect these incomplete commits so as to correct the issue manually. It is recommended
that the Auditor be added to a Rake task that at an appropriate time, e.g. nightly, at startup, or if the system detects
an unexpected termination.

```ruby
incomplete_commits = Stagehand::Auditor.incomplete_commits #=> { 1 => [start, insert], 13 => [start, end] }
```

The Auditor's `incomplete_commits` method returns a hash where the keys are the commit id and the values are the entries
that are part of the incomplete commit. These entries can be synced manually if desired:

```ruby
Stagehand::Staging::Synchronizer.sync_record(incomplete_commits[13]) # Syncs commit 13
```

Be aware that sync_record will still search the database for related commits that must also be synced to maintain
database consistency. See [Previewing Changes](#previewing-changes).

### Mismatched Records

If you suspect that some failure has left the staging and production databases out of sync, you can detect mismatched
records as follows.

```ruby
Stagehand::Auditor.mismatched_records #=> { table name => { id => { :staging => [row data...], :production => [row_data...] } } }
```

Each mismatched record is grouped by table name and then by id, with `:staging` and `:production` containing the row
data from their respective databases for comparison purposes.


## Removing Stagehand

To stop monitoring a table for changes:

```ruby
# In a migration
Stagehand::Schema.remove_stagehand! :only => [:some_table, :other_table]
```

If you need to completely remove Stagehand from your app:

1. Remove the database triggers and log table:

  ```ruby
  # In a migration
  Stagehand::Schema.remove_stagehand!
  ```

2. Remove the Stagehand includes from your controllers, and the configuration options from your environment files.


## Possible Caveats to double check when development is complete
- A transaction is opened on the staging and production databases when syncing. This reduces the timing window where the
sync process could be killed after the production database write, but before the staging database write had completed,
resulting in a rollback of only the staging database.

  Although this does not completely eliminate the issue, it can only occur if the process is killed exactly as
the inner transaction is completing, but before the outer transaction has completed. Even if this happened, it would
leave the system in a recoverable state, as the data would remain in an unsynced state in the staging database, and the
sync can be re-run to completion.

- Connections to each database are performed in an around filter that wraps each controller action. The filter is
prepended to reduce the chance any other code accesses the database before a connection to the desired database is made.
It is possible that other filter prepended could be inserted so that they run before the connection is made, so be aware
of insertion order when prepending filters.

- If the host app has some sort of undelete system where a record is actually deleted from the database and restored
by inserting them back into the table with the same id, there could be bugs. The checklist compacts entries by preferring
delete entries over all others, so the re-insertion entry will be masked by any unsynced delete entry. When the entries
are synced, the re-insertion entry will be erased because the delete entry is assumed to represent the current state of
that record.

- If a crash leaves a commit unfinished, subsequent commit entries which use the same session will not be autosynced.

- CommitEntry#record loads the record associated with the commit entry. However, only the table name and the record id
are saved in the entry, so the actual record class is inferred from the table_name. If multiple classes share the same
table_name, the first one is chosen. This may lead to unexpected behaviour if anything other than the record attributes
are being used.

- Usnynced write detection relies on the `exec_insert`, `exec_update`, `exec_delete` methods from
ActiveRecord::AbstractAdapter. It will not detect writes using the `execute` method.
