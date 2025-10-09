# Testing With Postgres

- Run tests with both Postgres flags set: `DRIFT_CRDT_TEST_BACKEND=postgres DRIFT_CRDT_PG_USER=postgres`.
- The Postgres service must listen on the default host/port; credentials come from `DRIFT_CRDT_PG_*` env vars.
- Since the tests are being run against a live database, use the `-j 1` flag to prevent concurrent test execution.
