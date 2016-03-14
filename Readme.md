## Stagehand

By [Culture Code](http://culturecode.ca/).

**Stagehand** is a gem that makes it easy to have a staging database where content editors can modify highly relational
data, and then publish those changes to a production database. It aims to solve the problem of being able to publish
specific content, while the latest changes to other content are still being worked on.

In a nutshell, the system is divided into two halves, Staging (where content is prepared by Admins), and Production
(where content is viewed by visitors). These two halves are backed by their own separate databases in order to ensure
that updates in the Staging area do not affect Production until they are ready.

It is important to note that the Production database acts as a cache of the Staging database only, no changes are ever
made to it except to sync changes that have occurred in the Staging database.

Key features:

- Allows published content to be edited without those changes immediately being seen by visitors
- Can selectively update content without needing to sync the entire database with production

## Setup
1. Add **Stagehand** to your Gemfile:

  ```ruby
  gem 'stagehand', :github => 'culturecode/stagehand'
  ```

2. Make a copy of your existing database, this will serve as the Production database, while your current database will
be used as the Staging database.

3. Add stagehand to your Staging database by using the `Stagehand::Schema.add_stagehand!` method. Tables not needed to
serve pages to site viewers can be ignored. This is useful if certain tables are only necessary in the
staging environment.

  ```ruby
    # In a migration
    Stagehand::Schema.add_stagehand! :except => [:users, :admin_messages, :other_tables, :not_needed_by_visitors]
  ```

  Monitoring is achieved using database triggers. Three triggers (INSERT, UPDATE, DELETE) are added to each monitored
  table and are used to create log entries that are used to track changes to content in the staging area.

  You can add stagehand to new tables in subsequent migrations as follows:

  ```ruby
  # In a migration
  Stagehand::Schema.add_stagehand! :only => [:some, :new, :tables]
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

  If there are writes to the database that are triggered in a "Production" controller, be sure to direct them to the staging database if   necessary. This can be achieved in multiple ways.

  ```ruby
  # Block form
  Stagehand::Database.connect_to_database(:staging) do
    # Some operation that should use the data in the staging database
    # All queries inside the block take place on staging
    # Block Form can be nested
  end

  # Model form
  MyModel.establish_connection(:staging) # Overrides connection even when used within the block form

  # Can be reverted to default by using
  MyModel.remove_connection
  ```

6. Set up automated synchronization of records that don't require user confirmation. The Synchronizer polls the database
to check for changes.

  ```bash
  # Syncing can be handled at the command line using a rake task
  rake stagehand:auto_sync
  rake stagehand:auto_sync[10] # Override default polling delay of 5 seconds
  ```

  ```ruby
    # Syncing can also be handled in ruby
    Synchronizer.auto_sync(5.seconds) # Optional delay can be customized. Set to falsey value for no delay.
  ```

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
- Transactions blocks don't expect multiple connections to be operating within them, so if a transaction fails while
writing content to multiple databases, only the connection that started the transaction will roll back.

- Connections to each database are performed in an around filter that wraps each controller action. The filter is
prepended to reduce the chance any other code accesses the database before a connection to the desired database is made.
It is possible that other filter prepended could be inserted so that they run before the connection is made, so be aware
of insertion order when prepending filters.

## TODO
Override create_table migration to require the user to decide stagehand/no stagehand
