## Assumptions
There is a staging database - Admins do their draft work in this database
There is a production database - Admins publish their draft work to this database

As records are synchronized to the live site, their corresponding commit entries are removed from the database.
CommitEntries with no commit_id are assumed to be operations by system processes, thus requiring no confirmation before syncing

## Preparation
Add stagehand to your database by using the Stagehand::Schema.add_stagehand! method. Tables can be ignored by passing
:except => [:users, :other_table]

Ensure content submitted by visitors is submitted to the staging database, as nothing is copied from
production => staging, only staging => production.

## TODO
Override create_table migration to require the user to decide stagehand/no stagehand
