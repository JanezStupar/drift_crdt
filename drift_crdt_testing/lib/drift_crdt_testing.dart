/// Testing utilities for drift_crdt
///
/// This package provides reusable testing utilities for packages using drift_crdt,
/// including multi-backend support (SQLite and PostgreSQL) and common test fixtures.
library drift_crdt_testing;

export 'src/seed_data.dart' show resetAndSeedBaselineData;
export 'src/serializable.dart' show User;
export 'src/test_backend.dart'
    show
        TestBackend,
        BackendConfig,
        backendConfig,
        configureBackendForPlatform,
        createExecutor,
        clearBackend;
