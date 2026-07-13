/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:async';

import 'package:flutter/services.dart';

class FLauncherChannel {
  static const _methodChannel = MethodChannel('com.hseuniversal.tidytv/method');
  static const _appsEventChannel =
      EventChannel('com.hseuniversal.tidytv/event_apps');
  static const _networkEventChannel =
      EventChannel('com.hseuniversal.tidytv/event_network');

  static const _watchNextMaxItems = 10;

  Future<List<Map<dynamic, dynamic>>> getApplications() async {
    List<Map<dynamic, dynamic>>? applications =
        await _methodChannel.invokeListMethod("getApplications");
    return applications!;
  }

  Future<Uint8List> getApplicationBanner(String packageName) async {
    Uint8List bytes =
        await _methodChannel.invokeMethod("getApplicationBanner", packageName);
    return bytes;
  }

  Future<Uint8List> getApplicationIcon(String packageName) async {
    Uint8List bytes =
        await _methodChannel.invokeMethod("getApplicationIcon", packageName);
    return bytes;
  }

  Future<bool> applicationExists(String packageName) async =>
      await _methodChannel.invokeMethod('applicationExists', packageName);

  Future<void> launchActivityFromAction(String action) async =>
      await _methodChannel.invokeMethod('launchActivityFromAction', action);

  Future<void> launchApp(String packageName) async =>
      await _methodChannel.invokeMethod('launchApp', packageName);

  Future<void> openSettings() async =>
      await _methodChannel.invokeMethod('openSettings');

  Future<void> openAppInfo(String packageName) async =>
      await _methodChannel.invokeMethod('openAppInfo', packageName);

  Future<void> uninstallApp(String packageName) async =>
      await _methodChannel.invokeMethod('uninstallApp', packageName);

  Future<bool> isDefaultLauncher() async =>
      await _methodChannel.invokeMethod('isDefaultLauncher');

  Future<bool> checkForGetContentAvailability() async =>
      await _methodChannel.invokeMethod("checkForGetContentAvailability");

  Future<Map<String, dynamic>> getActiveNetworkInformation() async {
    Map<dynamic, dynamic> map =
        await _methodChannel.invokeMethod("getActiveNetworkInformation");
    return map.cast<String, dynamic>();
  }

  Future<int> getDailyWifiUsage() async {
    try {
      final int usage = await _methodChannel.invokeMethod("getDailyWifiUsage");
      return usage;
    } on PlatformException catch (_) {
      return -1;
    }
  }

  Future<int> getWeeklyWifiUsage() async {
    try {
      final int usage = await _methodChannel.invokeMethod("getWeeklyWifiUsage");
      return usage;
    } on PlatformException catch (_) {
      return -1;
    }
  }

  Future<int> getMonthlyWifiUsage() async {
    try {
      final int usage =
          await _methodChannel.invokeMethod("getMonthlyWifiUsage");
      return usage;
    } on PlatformException catch (_) {
      return -1;
    }
  }

  Future<bool> checkUsageStatsPermission() async =>
      await _methodChannel.invokeMethod("checkUsageStatsPermission");

  Future<void> requestUsageStatsPermission() async =>
      await _methodChannel.invokeMethod("requestUsageStatsPermission");

  Future<void> openWifiSettings() async =>
      await _methodChannel.invokeMethod("openWifiSettings");

  Future<bool> startAmbientMode() async =>
      await _methodChannel.invokeMethod("startAmbientMode");

  Future<bool> checkMediaPermissions() async =>
      await _methodChannel.invokeMethod("checkMediaPermissions");

  Future<void> requestMediaPermissions() async =>
      await _methodChannel.invokeMethod("requestMediaPermissions");

  Future<List<Map<String, dynamic>>> getMediaStoreImages() async {
    List<Map<dynamic, dynamic>>? images =
        await _methodChannel.invokeListMethod("getMediaStoreImages");
    return images?.map((e) => e.cast<String, dynamic>()).toList() ?? [];
  }

  Future<List<Map<String, dynamic>>> getMediaStoreVideos() async {
    List<Map<dynamic, dynamic>>? videos =
        await _methodChannel.invokeListMethod("getMediaStoreVideos");
    return videos?.map((e) => e.cast<String, dynamic>()).toList() ?? [];
  }

  Future<bool> installApk(String apkPath) async =>
      await _methodChannel.invokeMethod("installApk", apkPath);

  Future<void> requestInstallUnknownAppsPermission() async =>
      await _methodChannel.invokeMethod("requestInstallUnknownAppsPermission");

  StreamSubscription<dynamic> addAppsChangedListener(
          void Function(Map<String, dynamic>) listener) =>
      _appsEventChannel.receiveBroadcastStream().listen((event) {
        Map<dynamic, dynamic> eventMap = event;
        listener(eventMap.cast<String, dynamic>());
      });

  StreamSubscription<dynamic> addNetworkChangedListener(
          void Function(Map<String, dynamic>) listener) =>
      _networkEventChannel.receiveBroadcastStream().listen((event) {
        Map<dynamic, dynamic> eventMap = event;
        listener(eventMap.cast<String, dynamic>());
      });

  // Watch Next / TV Channels API
  Future<bool> checkWatchNextPermission() async =>
      await _methodChannel.invokeMethod('checkWatchNextPermission') ?? false;

  Future<void> requestWatchNextPermission() async =>
      await _methodChannel.invokeMethod('requestWatchNextPermission');

  Future<List<Map<dynamic, dynamic>>> getWatchNextItems() async {
    try {
      var result = await _methodChannel.invokeMethod('getWatchNextItems', _watchNextMaxItems);
      if (result == null) return [];
      return (result as List).cast<Map<dynamic, dynamic>>();
    } on PlatformException {
      return [];
    } catch (e) {
      return [];
    }
  }

  Future<bool> launchWatchNextItem(String? packageName, String? contentId, String? action) async {
    try {
      var result = await _methodChannel.invokeMethod('launchWatchNextItem', {
        'packageName': packageName,
        'contentId': contentId,
        'action': action,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Load image bytes from a content:// URI (for Watch Next posters)
  Future<Uint8List> loadContentUriImage(String contentUri) async {
    try {
      var result = await _methodChannel.invokeMethod('loadContentUriImage', contentUri);
      return result ?? Uint8List(0);
    } on PlatformException {
      return Uint8List(0);
    } catch (e) {
      return Uint8List(0);
    }
  }
}
