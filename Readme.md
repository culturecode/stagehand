## Introduction
staging database - Admins do their draft work in this database
production database - Admins publish their draft work to this database

As records are synchronized to the live site, their corresponding commit entries are removed from the database.
CommitEntries with no commit_id are assumed to be operations by system processes, thus requiring no confirmation before syncing


## Setup
1. Make a copy of your existing database, this will serve as the Production database.

2. Add stagehand to your database by using the Stagehand::Schema.add_stagehand! method. Tables can be ignored by passing
:except => [:users, :other_table]

3. Modify the environment configuration file to specify which database to use as for staging and which to use for
production. The connection name should match whatever names you've used in database.yml.

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

4. Add the following to set which controllers serve up the database from the production site, and which controllers use
the staging server.

```ruby
class ApplicationController < ActionController::Base
  include Stagehand::Production::Controller # This controller and all subclasses will connect to the production database
end

class AdminController < ApplicationController
  include Stagehand::Staging::Controller  # This controller and all subclasses will connect to the staging database
end
```

5. If there are writes to the database that are triggered in a "Production" controller, be sure to direct them to the
staging database if necessary. This can be achieved in multiple ways.

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


## TODO
Override create_table migration to require the user to decide stagehand/no stagehand

## Possible Caveats to double check when development is complete
- Transactions blocks don't expect multiple connections to be operating within them, so if a transaction fails while
writing content to multiple databases, only the connection that started the transaction will roll back.

- Connections to each database are performed in an around filter that wraps each controller action. The filter is
prepended to reduce the chance any other code accesses the database before a connection to the desired database is made.
It is possible that other filter prepended could be inserted so that they run before the connection is made, so be aware
of insertion order when prepending filters.
