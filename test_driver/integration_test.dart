// Driver for the integration_test screenshot run. Receives the PNG bytes that
// `binding.takeScreenshot(name)` emits and writes them to ./screenshots/.
//
// Invoked indirectly by:
//   flutter drive \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/screenshot_test.dart -d <emulator-id>

import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot:
        (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      final file = await File('screenshots/$name.png').create(recursive: true);
      file.writeAsBytesSync(bytes);
      return true;
    },
  );
}
