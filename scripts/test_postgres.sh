#!/usr/bin/env bash
export DRIFT_CRDT_TEST_BACKEND=postgres
export DRIFT_CRDT_PG_USER=postgres
flutter test "$@"