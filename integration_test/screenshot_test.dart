// Captures Android-TV screenshots of the launcher for the Play Store listing.
//
// Run via the helper script (creates/boots a TV emulator, then flutter drive):
//   ./tool/tv_screenshots.sh
// or manually against an already-running Android TV emulator:
//   flutter drive \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/screenshot_test.dart -d <emulator-id>
//
// Screenshots are produced at 1920x1080 (16:9) when driven from a `tv_1080p`
// AVD, which directly satisfies Google Play's high-res TV screenshot spec.

import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flauncher/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture Android TV launcher screenshots', (tester) async {
    await app.main();
    await _settle(tester);

    // Android REQUIRES the Flutter surface be rendered into an image (and a
    // frame pumped) before takeScreenshot, otherwise the capture is black.
    if (!kIsWeb && Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
      await tester.pump(const Duration(milliseconds: 500));
    }

    // 1) Home / launcher grid.
    await _shot(tester, binding, '01-home');

    // 2) Settings panel (opened from the app-bar settings button).
    if (await _tapIcon(tester, Icons.settings_outlined)) {
      await _shot(tester, binding, '02-settings');

      // 3) Wallpaper panel (Aerial Views is free here now).
      if (await _tapText(tester, 'Wallpaper')) {
        await _shot(tester, binding, '03-wallpaper');
      }
    }

    // Add more screens by following the same guarded pattern above — every
    // step is best-effort so a missing/renamed target never aborts the run.
  });
}

/// pumpAndSettle, but tolerant of the launcher's perpetual animations (focus
/// glow, aerial video) that would otherwise make pumpAndSettle time out.
Future<void> _settle(WidgetTester tester) async {
  try {
    await tester.pumpAndSettle(
      const Duration(milliseconds: 100),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 8),
    );
  } catch (_) {
    await tester.pump(const Duration(seconds: 1));
  }
}

Future<void> _shot(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
) async {
  await _settle(tester);
  await binding.takeScreenshot(name);
}

Future<bool> _tapIcon(WidgetTester tester, IconData icon) async {
  final finder = find.byIcon(icon);
  if (finder.evaluate().isEmpty) return false;
  await tester.tap(finder.first, warnIfMissed: false);
  await _settle(tester);
  return true;
}

Future<bool> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text);
  if (finder.evaluate().isEmpty) return false;
  await tester.tap(finder.first, warnIfMissed: false);
  await _settle(tester);
  return true;
}
