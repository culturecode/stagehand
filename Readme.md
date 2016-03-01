## Assumptions
As records are synchronized to the live site, their corresponding commit entries are removed from the database.
CommitEntries with no commit_id are assumed to be operations by system processes, thus requiring no confirmation before syncing
## TODO

Override create_table migration to require the user to decide stagehand/no stagehand
Be sure to lock the row being copied to the production DB
