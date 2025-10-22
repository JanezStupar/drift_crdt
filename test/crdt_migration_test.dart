import 'package:test/test.dart';

import 'utils/test_backend.dart' as backend;

void crdtMigrationTests() {
  // Note: These tests are skipped in Flutter-agnostic mode because they require
  // Flutter's rootBundle for asset loading. For Flutter apps, you can re-enable
  // these tests by adding the flutter dependency and uncommenting the code below.

  test('on nonmigrated database an error occurs', () async {
    // Skipped: Requires Flutter asset loading
    // To enable: Uncomment and add flutter_test dependency
  }, skip: 'Requires Flutter asset loading (rootBundle)');

  test('if migration parameter is passed migration gets performed', () async {
    // Skipped: Requires Flutter asset loading
    // To enable: Uncomment and add flutter_test dependency
  }, skip: 'Requires Flutter asset loading (rootBundle)');
}

Future<void> main() async {
  await backend.configureBackendForPlatform();

  if (backend.backendConfig.isPostgres) {
    test(
      'migration tests are sqlite-specific',
      () {},
      skip: 'Migration fixtures rely on sqlite asset databases.',
    );
    return;
  }

  crdtMigrationTests();
}
