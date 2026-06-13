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
import 'dart:io';
import 'dart:collection';
import 'package:collection/collection.dart' as collection;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:drift/drift.dart';
import 'package:flauncher/database.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/widgets.dart' hide Category;

import '../models/app.dart';
import '../models/category.dart';

class AppsService extends ChangeNotifier {
  final FLauncherChannel _fLauncherChannel;
  final FLauncherDatabase _database;

  bool _initialized = false;
  int _layoutVersion = 0;

  List<LauncherSection> _launcherSections = List.empty(growable: true);
  Map<String, App> _applications = Map();
  Map<String, Uint8List> _iconCache = Map();
  Map<String, Uint8List> _bannerCache = Map();

  Map<int, Category> _categoriesById = Map();

  final Map<String, Future<Uint8List>> _pendingBanners = {};
  final Map<String, Future<Uint8List>> _pendingIcons = {};
  StreamSubscription? _appsSubscription;

  // Cached SharedPreferences instance to avoid repeated disk I/O
  SharedPreferences? _prefs;
  Future<SharedPreferences> get _prefsAsync async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  bool get initialized => _initialized;
  int get layoutVersion => _layoutVersion;

  @override
  void notifyListeners() {
    _layoutVersion++;
    super.notifyListeners();
  }

  String? _pendingReorderFocusPackage;
  int? _pendingReorderFocusCategoryId;
  String? get pendingReorderFocusPackage => _pendingReorderFocusPackage;
  int? get pendingReorderFocusCategoryId => _pendingReorderFocusCategoryId;
  void clearPendingReorderFocusPackage() {
    _pendingReorderFocusPackage = null;
    _pendingReorderFocusCategoryId = null;
  }

  void setPendingReorderFocus(String packageName, int categoryId) {
    _pendingReorderFocusPackage = packageName;
    _pendingReorderFocusCategoryId = categoryId;
  }

  final Set<String> _dirtyImagePackages = {};
  bool consumeDirtyImage(String packageName) =>
      _dirtyImagePackages.remove(packageName);

  List<App> get applications => UnmodifiableListView(
      _applications.values.sortedBy((application) => application.name));

  List<LauncherSection> get launcherSections =>
      List.unmodifiable(_launcherSections);
  List<Category> get categories => _categoriesById.values
      .map((category) => category.unmodifiable())
      .toList(growable: false);

  AppsService(this._fLauncherChannel, this._database) {
    _init();
  }

  Future<void> _init() async {
    try {
      // Phase 1: Load from DB immediately (fast)
      await _loadFromDatabase();

      if (_categoriesById.isEmpty) {
        await _initDefaultCategories();
      }

      debugPrint(
          'AppsService loaded from DB: ${_applications.length} apps, ${_categoriesById.length} categories');

      // Phase 2: Sync with system before marking initialized so UI
      // never sees an empty app list on fresh install.
      // Timeout prevents hanging if platform channel is unresponsive.
      try {
        await _syncWithSystem().timeout(const Duration(seconds: 10));
      } catch (e) {
        debugPrint('AppsService sync timed out or failed: $e');
      }

      // After sync, check if apps exist but aren't placed into any
      // category.  This happens on fresh install: _initDefaultCategories()
      // ran before sync when there were 0 apps, so only Favorites was
      // created.  After sync populates apps, they have no category.
      final bool hasUncategorizedApps = _applications.values.any(
        (app) => !app.hidden && app.categoryOrders.isEmpty,
      );
      if (hasUncategorizedApps && _applications.isNotEmpty) {
        // Wipe the skeleton categories and rebuild with actual apps
        await _initDefaultCategories();
      }

      _appsSubscription =
          _fLauncherChannel.addAppsChangedListener((event) async {
        try {
          String? changedPackageName;
          if (event.containsKey('packageName')) {
            changedPackageName = event['packageName'];
          } else if (event.containsKey('activityInfo')) {
            changedPackageName = event['activityInfo']['packageName'];
          }

          if (changedPackageName != null) {
            _iconCache.remove(changedPackageName);
            _bannerCache.remove(changedPackageName);
            _dirtyImagePackages.add(changedPackageName);
          }

          switch (event["action"]) {
            case "PACKAGE_ADDED":
            case "PACKAGE_CHANGED":
              Map<dynamic, dynamic> applicationInfo = event['activityInfo'];
              await _database
                  .persistApps([_buildAppCompanion(applicationInfo)]);

              App newApp = App.fromSystem(applicationInfo);
              App? existingApp = _applications[newApp.packageName];

              if (existingApp != null) {
                newApp.hidden = existingApp.hidden;
                newApp.categoryOrders = Map.from(existingApp.categoryOrders);
                for (int categoryId in newApp.categoryOrders.keys) {
                  if (_categoriesById.containsKey(categoryId)) {
                    Category category = _categoriesById[categoryId]!;
                    int index = category.applications.indexOf(existingApp);
                    if (index != -1) {
                      category.applications[index] = newApp;
                    } else {
                      category.applications.add(newApp);
                    }
                  }
                }
                _applications[newApp.packageName] = newApp;
              } else {
                _applications[newApp.packageName] = newApp;
                final targetCategory = _findTargetCategoryForNewApp();
                if (targetCategory != null) {
                  await addToCategory(newApp, targetCategory,
                      shouldNotifyListeners: false);
                }
              }
              break;
            case "PACKAGES_AVAILABLE":
              List<dynamic> applicationsInfo = event["activitiesInfo"];
              await _database
                  .persistApps((applicationsInfo).map(_buildAppCompanion));

              for (Map<dynamic, dynamic> applicationInfo in applicationsInfo) {
                App newApp = App.fromSystem(applicationInfo);
                App? existingApp = _applications[newApp.packageName];

                if (existingApp != null) {
                  newApp.hidden = existingApp.hidden;
                  newApp.categoryOrders = Map.from(existingApp.categoryOrders);
                  for (int categoryId in newApp.categoryOrders.keys) {
                    if (_categoriesById.containsKey(categoryId)) {
                      Category category = _categoriesById[categoryId]!;
                      int index = category.applications.indexOf(existingApp);
                      if (index != -1) {
                        category.applications[index] = newApp;
                      } else {
                        category.applications.add(newApp);
                      }
                    }
                  }
                  _applications[newApp.packageName] = newApp;
                } else {
                  _applications[newApp.packageName] = newApp;
                }
                _iconCache.remove(newApp.packageName);
                _bannerCache.remove(newApp.packageName);
              }
              break;
            case "PACKAGE_REMOVED":
              String packageName = event['packageName'];
              await _database.deleteApps([packageName]);

              // Clear icon cache for removed app
              _iconCache.remove(packageName);
              _bannerCache.remove(packageName);

              App? application = _applications.remove(packageName);

              if (application != null) {
                for (int categoryId in application.categoryOrders.keys) {
                  if (_categoriesById.containsKey(categoryId)) {
                    Category category = _categoriesById[categoryId]!;
                    category.applications.remove(application);
                  }
                }
              }
              break;
          }

          notifyListeners();
        } catch (e) {
          debugPrint('Error handling app change event: $e');
        }
      });

      debugPrint(
          'AppsService initialized: ${_applications.length} apps, ${_categoriesById.length} categories');
    } catch (e) {
      debugPrint('Error initializing AppsService: $e');
    } finally {
      // Always mark initialized so the UI never gets permanently stuck
      // on the loading spinner, even if sync failed.
      _initialized = true;
      notifyListeners();

      // If apps are still empty after init (e.g. sync timed out on fresh
      // install), schedule a retry so we don't leave the user stranded.
      if (_applications.isEmpty) {
        _scheduleRetrySync();
      } else {
        // Pre-cache icons for visible apps (throttled)
        _preCacheIcons();
      }
    }
  }

  /// Retries sync with the system after a delay. Used when initial sync
  /// fails or times out on a fresh install, leaving 0 apps.
  bool _retryInProgress = false;

  void _scheduleRetrySync() {
    Future.delayed(const Duration(seconds: 3), () async {
      if (_applications.isNotEmpty) return; // Already populated
      await retrySync();
    });
  }

  /// Public method for the UI to manually trigger a re-sync (e.g. retry button).
  Future<void> retrySync() async {
    if (_retryInProgress) return; // Guard against concurrent retries
    _retryInProgress = true;
    debugPrint('AppsService: manual retry sync triggered');
    try {
      await _syncWithSystem().timeout(const Duration(seconds: 15));
      // Check if apps still lack category assignments
      final bool hasUncategorizedApps = _applications.values.any(
        (app) => !app.hidden && app.categoryOrders.isEmpty,
      );
      if (hasUncategorizedApps && _applications.isNotEmpty) {
        await _initDefaultCategories();
      }
      notifyListeners();
      if (_applications.isNotEmpty) {
        _preCacheIcons();
      }
    } catch (e) {
      debugPrint('AppsService retry sync failed: $e');
    } finally {
      _retryInProgress = false;
    }
  }

  Future<void> _loadFromDatabase() async {
    final results = await Future.wait([
      _database.getApplications(),
      _database.getAppsCategories(),
      _database.getCategories(),
      _database.getLauncherSpacers(),
    ]);
    List<App> appsFromDatabase = results[0] as List<App>;
    List<AppCategory> appsCategories = results[1] as List<AppCategory>;
    List<Category> categories = results[2] as List<Category>;
    List<LauncherSpacer> spacers = results[3] as List<LauncherSpacer>;

    _categoriesById = Map.fromEntries(
        categories.map((category) => MapEntry(category.id, category)));
    _applications = Map.fromEntries(appsFromDatabase
        .map((application) => MapEntry(application.packageName, application)));

    _launcherSections.clear();
    _launcherSections.addAll(categories);
    _launcherSections.addAll(spacers);
    _launcherSections.sort((ls0, ls1) => ls0.order.compareTo(ls1.order));

    if (appsCategories.isNotEmpty) {
      final appsCategoriesByPackage = collection.groupBy<AppCategory, String>(
        appsCategories,
        (ac) => ac.appPackageName,
      );
      for (App application in _applications.values) {
        if (application.hidden) continue;
        final currentCategories =
            appsCategoriesByPackage[application.packageName] ?? [];

        for (AppCategory appCategory in currentCategories) {
          if (_categoriesById.containsKey(appCategory.categoryId)) {
            Category category = _categoriesById[appCategory.categoryId]!;
            application.categoryOrders[category.id] = appCategory.order;
            category.applications.add(application);
          }
        }
      }
    }

    for (Category category in _categoriesById.values) {
      sortCategory(category);
    }
  }

  Future<void> _syncWithSystem() async {
    try {
      List<Map<dynamic, dynamic>> appsFromSystem =
          await _fLauncherChannel.getApplications();
      Iterable<MapEntry<String, (Map, AppsCompanion)>> appEntries =
          appsFromSystem.map((appFromSystem) => MapEntry(
              appFromSystem['packageName'],
              (appFromSystem, _buildAppCompanion(appFromSystem))));
      Map<String, (Map, AppsCompanion)> appsFromSystemByPackageName =
          Map.fromEntries(appEntries);

      final Iterable<App> appsRemovedFromSystem = _applications.values.where(
          (app) => !appsFromSystemByPackageName.containsKey(app.packageName));

      final List<String> uninstalledApplications = [];
      if (appsRemovedFromSystem.isNotEmpty) {
        final existenceChecks = await Future.wait(
          appsRemovedFromSystem.map((app) async {
            final exists =
                await _fLauncherChannel.applicationExists(app.packageName);
            return (app.packageName, exists);
          }),
        );
        for (final (packageName, exists) in existenceChecks) {
          if (!exists) {
            uninstalledApplications.add(packageName);
          }
        }
      }

      await _database.transaction(() async {
        await _database.persistApps(
            appsFromSystemByPackageName.values.map((record) => record.$2));
        await _database.deleteApps(uninstalledApplications);
      });

      // Reload from DB after persist
      await _loadFromDatabase();

      // Merge system info (action, sideloaded) into loaded apps
      for (App application in _applications.values) {
        Map? applicationFromSystem =
            appsFromSystemByPackageName[application.packageName]?.$1;
        if (applicationFromSystem != null) {
          if (applicationFromSystem.containsKey('action')) {
            application.action = applicationFromSystem['action'];
          }
          if (applicationFromSystem.containsKey('sideloaded')) {
            application.sideloaded = applicationFromSystem['sideloaded'];
          }
        }
      }

      for (Category category in _categoriesById.values) {
        sortCategory(category);
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error syncing with system: $e');
    }
  }

  Future<void> _preCacheIcons() async {
    // Only cache apps that are not hidden, in throttled batches
    // to avoid flooding the platform channel at startup.
    final visibleApps =
        _applications.values.where((app) => !app.hidden).toList();
    const batchSize = 5;
    for (int i = 0; i < visibleApps.length; i += batchSize) {
      final end = (i + batchSize < visibleApps.length)
          ? i + batchSize
          : visibleApps.length;
      final batch = visibleApps.sublist(i, end);
      // Fire off a batch concurrently
      await Future.wait(
        batch.map((app) async {
          await getAppIcon(app.packageName);
          await getAppBanner(app.packageName);
        }),
      );
      // Small gap between batches to let the main thread breathe
      if (end < visibleApps.length) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  AppsCompanion _buildAppCompanion(dynamic data) {
    String? version = data["version"];
    if (version == null) {
      version = "";
    }

    return AppsCompanion(
        packageName: Value(data["packageName"]),
        name: Value(data["name"]),
        version: Value(version),
        hidden: const Value.absent());
  }

  Future<void> _initDefaultCategories() {
    final allApps =
        _applications.values.where((application) => !application.hidden);
    final defaultFavoriteLauncherPackageNames = [
      'com.hseuniversal.tidytv',
      'com.hseuniversal.tidytv.debug',
    ];

    return _database.transaction(() async {
      int allAppsCategoryId = -1;
      if (allApps.isNotEmpty) {
        allAppsCategoryId = await addCategory("All Apps",
            type: CategoryType.grid, shouldNotifyListeners: false);

        Category allAppsCategory = _categoriesById[allAppsCategoryId]!;
        // Batch insert all apps into "All Apps" category
        List<AppsCategoriesCompanion> allAppsEntries = [];
        int order = 0;
        for (final app in allApps) {
          allAppsCategory.applications.add(app);
          app.categoryOrders[allAppsCategoryId] = order;
          allAppsEntries.add(AppsCategoriesCompanion.insert(
            categoryId: allAppsCategoryId,
            appPackageName: app.packageName,
            order: order,
          ));
          order++;
        }
        await _database.insertAppsCategories(allAppsEntries);
      }

      final int favoritesId =
          await addCategory("Favorites", shouldNotifyListeners: false);
      final Category favoritesCategory = _categoriesById[favoritesId]!;
      final Category? allAppsCategory = _getAppsCategory();

      // Batch insert favorites
      List<AppsCategoriesCompanion> favoriteEntries = [];
      List<String> favPackageNames = [];
      int favOrder = 0;
      for (final packageName in defaultFavoriteLauncherPackageNames) {
        final app = _applications[packageName];
        if (app != null && !app.hidden) {
          favoritesCategory.applications.add(app);
          app.categoryOrders[favoritesId] = favOrder;
          favoriteEntries.add(AppsCategoriesCompanion.insert(
            categoryId: favoritesId,
            appPackageName: app.packageName,
            order: favOrder,
          ));
          favPackageNames.add(packageName);
          favOrder++;
        }
      }
      if (favoriteEntries.isNotEmpty) {
        await _database.insertAppsCategories(favoriteEntries);
      }

      // Remove favorites from "All Apps" if category exists
      if (allAppsCategory != null && favPackageNames.isNotEmpty) {
        for (final packageName in favPackageNames) {
          final app = _applications[packageName];
          if (app != null) {
            app.categoryOrders.remove(allAppsCategoryId);
            allAppsCategory.applications.remove(app);
          }
        }
        await _database.customStatement(
          "DELETE FROM apps_categories WHERE category_id = ? AND app_package_name IN (${favPackageNames.map((_) => '?').join(',')})",
          [allAppsCategoryId, ...favPackageNames],
        );
      }
    });
  }

  void sortCategory(Category category) {
    if (category.sort == CategorySort.alphabetical) {
      category.applications.sortBy((application) => application.name);
    } else if (category.sort == CategorySort.lastUsed) {
      category.applications.sort((a, b) {
        final aTime =
            a.lastLaunchedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime =
            b.lastLaunchedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime); // Descending (newest first)
      });
    } else {
      category.applications.sortBy<num>(
          (application) => application.categoryOrders[category.id]!);
    }
  }

  /// Finds the appropriate category for a newly installed app.
  /// Returns "All Apps" category, or falls back to first non-Favorites category.
  Category? _findTargetCategoryForNewApp() {
    return _categoriesById.values.firstWhere(
      (c) => c.name.toLowerCase() == "all apps",
      orElse: () {
        return _categoriesById.values.firstWhere(
          (c) => c.name.toLowerCase() != 'favorites',
          orElse: () => _categoriesById.values.first,
        );
      },
    );
  }

  Future<Uint8List> getAppBanner(String packageName) async {
    if (_bannerCache.containsKey(packageName)) {
      return _bannerCache[packageName]!;
    }
    if (_pendingBanners.containsKey(packageName)) {
      return _pendingBanners[packageName]!;
    }

    final Future<Uint8List> future = _loadAppBannerInternal(packageName);
    _pendingBanners[packageName] = future;
    try {
      return await future;
    } finally {
      _pendingBanners.remove(packageName);
    }
  }

  Future<Uint8List> _loadAppBannerInternal(String packageName) async {
    try {
      final prefs = await _prefsAsync;
      final customBannerPath = prefs.getString('custom_banner_$packageName');
      if (customBannerPath != null) {
        final file = File(customBannerPath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          _bannerCache[packageName] = bytes;
          return bytes;
        }
      }
    } on FileSystemException {
      // File was deleted between check and read - clear stale reference
      final prefs = await _prefsAsync;
      await prefs.remove('custom_banner_$packageName');
    } catch (_) {
      // Ignore other errors reading custom banner
    }

    final bytes = await _fLauncherChannel.getApplicationBanner(packageName);
    if (bytes.isNotEmpty) {
      _bannerCache[packageName] = bytes;
    }
    return bytes;
  }

  Future<void> setCustomAppBanner(String packageName, String imagePath) async {
    final prefs = await _prefsAsync;
    await prefs.setString('custom_banner_$packageName', imagePath);
    _bannerCache.remove(packageName);
    _dirtyImagePackages.add(packageName);
    notifyListeners();
  }

  Future<void> removeCustomAppBanner(String packageName) async {
    final prefs = await _prefsAsync;
    final customBannerPath = prefs.getString('custom_banner_$packageName');
    if (customBannerPath != null) {
      try {
        await File(customBannerPath).delete();
      } catch (_) {
        // Ignore file deletion errors
      }
    }
    await prefs.remove('custom_banner_$packageName');
    _bannerCache.remove(packageName);
    _dirtyImagePackages.add(packageName);
    notifyListeners();
  }

  Future<bool> hasCustomBanner(String packageName) async {
    final prefs = await _prefsAsync;
    return prefs.containsKey('custom_banner_$packageName');
  }

  Future<Uint8List> getAppIcon(String packageName) async {
    if (_iconCache.containsKey(packageName)) {
      return _iconCache[packageName]!;
    }
    if (_pendingIcons.containsKey(packageName)) {
      return _pendingIcons[packageName]!;
    }

    final Future<Uint8List> future = _loadAppIconInternal(packageName);
    _pendingIcons[packageName] = future;
    try {
      return await future;
    } finally {
      _pendingIcons.remove(packageName);
    }
  }

  Future<Uint8List> _loadAppIconInternal(String packageName) async {
    final bytes = await _fLauncherChannel.getApplicationIcon(packageName);
    if (bytes.isNotEmpty) {
      _iconCache[packageName] = bytes;
    }
    return bytes;
  }

  Future<void> launchApp(App app) async {
    app.lastLaunchedAt = DateTime.now();
    await _database.updateApp(app.packageName,
        AppsCompanion(lastLaunchedAt: Value(app.lastLaunchedAt)));
    notifyListeners();

    Future<void> future;
    if (app.action == null) {
      future = _fLauncherChannel.launchApp(app.packageName);
    } else {
      future = _fLauncherChannel.launchActivityFromAction(app.action!);
    }

    return future;
  }

  Future<void> openAppInfo(App app) =>
      _fLauncherChannel.openAppInfo(app.packageName);

  Future<void> uninstallApp(App app) =>
      _fLauncherChannel.uninstallApp(app.packageName);

  Future<void> openSettings() => _fLauncherChannel.openSettings();

  Future<bool> isDefaultLauncher() => _fLauncherChannel.isDefaultLauncher();

  Future<void> startAmbientMode() => _fLauncherChannel.startAmbientMode();

  Future<void> addToCategory(App app, Category category,
      {bool shouldNotifyListeners = true}) async {
    int index = await _database.nextAppCategoryOrder(category.id) ?? 0;
    await _database.insertAppsCategories([
      AppsCategoriesCompanion.insert(
        categoryId: category.id,
        appPackageName: app.packageName,
        order: index,
      )
    ]);

    if (_categoriesById.containsKey(category.id)) {
      Category categoryFound = _categoriesById[category.id]!;
      app.categoryOrders[categoryFound.id] = index;
      categoryFound.applications.add(app);

      if (shouldNotifyListeners) {
        sortCategory(categoryFound);
        notifyListeners();
      }
    }
  }

  Future<void> removeFromCategory(App application, Category category) async {
    await _database.deleteAppCategory(category.id, application.packageName);
    if (_categoriesById.containsKey(category.id)) {
      Category categoryFound = _categoriesById[category.id]!;
      application.categoryOrders.remove(categoryFound.id);
      categoryFound.applications.remove(application);

      notifyListeners();
    }
  }

  /// Auto-populates a category based on its special name.
  /// For "All Apps": adds all non-hidden apps regardless of sideloaded status.
  Future<void> autoPopulateCategory(Category category) async {
    if (!_categoriesById.containsKey(category.id)) {
      return;
    }
    Category actualCategory = _categoriesById[category.id]!;

    Iterable<App> appsToAdd;

    switch (actualCategory.name) {
      case 'All Apps':
        appsToAdd = _applications.values.where((app) => !app.hidden);
        break;
      default:
        return;
    }

    final List<AppsCategoriesCompanion> entries = [];
    int order = await _database.nextAppCategoryOrder(actualCategory.id) ?? 0;
    for (final app in appsToAdd) {
      actualCategory.applications.add(app);
      app.categoryOrders[actualCategory.id] = order;
      entries.add(AppsCategoriesCompanion.insert(
        categoryId: actualCategory.id,
        appPackageName: app.packageName,
        order: order,
      ));
      order++;
    }
    if (entries.isNotEmpty) {
      await _database.insertAppsCategories(entries);
    }

    notifyListeners();
  }

  Category? _getAppsCategory() {
    return _categoriesById.values.firstWhereOrNull(
      (category) => category.name == 'All Apps',
    );
  }

  /// Gets the Favorites category, creating it if it doesn't exist
  Future<Category> getOrCreateFavoritesCategory() async {
    Category? favorites = _categoriesById.values
        .firstWhereOrNull((category) => category.name == 'Favorites');

    if (favorites != null) {
      return favorites;
    }

    int categoryId =
        await addCategory('Favorites', shouldNotifyListeners: false);
    return _categoriesById[categoryId]!;
  }

  /// Checks if an app is in the Favorites category
  bool isAppInFavorites(App app) {
    Category? favorites = _categoriesById.values
        .firstWhereOrNull((category) => category.name == 'Favorites');

    if (favorites == null) {
      return false;
    }

    return favorites.applications.any((a) => a.packageName == app.packageName);
  }

  /// Adds an app to Favorites and removes it from the Apps category
  Future<void> addToFavorites(App app) async {
    Category favorites = await getOrCreateFavoritesCategory();

    if (!favorites.applications.any((a) => a.packageName == app.packageName)) {
      await addToCategory(app, favorites, shouldNotifyListeners: false);
    }

    final appsCategory = _getAppsCategory();
    if (appsCategory != null &&
        appsCategory.applications
            .any((a) => a.packageName == app.packageName)) {
      await removeFromCategory(app, appsCategory);
    } else {
      notifyListeners();
    }
  }

  /// Removes an app from Favorites and puts it back in the Apps category
  Future<void> removeFromFavorites(App app) async {
    Category? favorites = _categoriesById.values
        .firstWhereOrNull((category) => category.name == 'Favorites');

    if (favorites != null) {
      await removeFromCategory(app, favorites);
    }

    final appsCategory = _getAppsCategory();
    if (appsCategory != null &&
        !appsCategory.applications
            .any((a) => a.packageName == app.packageName)) {
      await addToCategory(app, appsCategory);
    }
  }

  /// Toggles an app in/out of Favorites
  Future<void> toggleFavorite(App app) async {
    if (isAppInFavorites(app)) {
      await removeFromFavorites(app);
    } else {
      await addToFavorites(app);
    }
  }

  Future<void> saveApplicationOrderInCategory(Category category) async {
    if (!_categoriesById.containsKey(category.id)) {
      return;
    }

    Category categoryFound = _categoriesById[category.id]!;
    List<App> applications = categoryFound.applications;
    List<AppsCategoriesCompanion> orderedAppCategories = [];

    for (int i = 0; i < applications.length; ++i) {
      orderedAppCategories.add(AppsCategoriesCompanion(
        categoryId: Value(categoryFound.id),
        appPackageName: Value(applications[i].packageName),
        order: Value(i),
      ));
    }
    await _database.replaceAppsCategories(orderedAppCategories);
    notifyListeners();
  }

  Future<void> moveAppToAdjacentCategory(
      App app, Category currentCategory, AxisDirection direction) async {
    int currentSectionIndex = _launcherSections.indexOf(currentCategory);
    if (currentSectionIndex == -1) {
      return;
    }

    int targetSectionIndex = -1;
    Category? targetCategory;

    // Find next valid category (skip spacers)
    if (direction == AxisDirection.down) {
      for (int i = currentSectionIndex + 1; i < _launcherSections.length; i++) {
        if (_launcherSections[i] is Category) {
          targetSectionIndex = i;
          targetCategory = _launcherSections[i] as Category;
          break;
        }
      }
    } else if (direction == AxisDirection.up) {
      for (int i = currentSectionIndex - 1; i >= 0; i--) {
        if (_launcherSections[i] is Category) {
          targetSectionIndex = i;
          targetCategory = _launcherSections[i] as Category;
          break;
        }
      }
    }

    if (targetCategory == null) {
      return;
    }

    // Remove from current
    await removeFromCategory(app, currentCategory);

    // Set pending focus package so AppCard can reclaim focus and reorder mode
    _pendingReorderFocusPackage = app.packageName;

    // Add to target
    int newIndex = 0;
    if (direction == AxisDirection.up) {
      // If moving UP (to previous section), append to BOTTOM
      newIndex = await _database.nextAppCategoryOrder(targetCategory.id) ?? 0;
    } else {
      // If moving DOWN (to next section), insert at TOP (index 0)
      newIndex = 0;
    }

    // DB Insert Logic
    // 1. Get current items in target
    List<App> targetApps = targetCategory.applications;

    // 2. Adjust local list
    if (direction == AxisDirection.down) {
      targetApps.insert(0, app); // Insert at top
    } else {
      targetApps.add(app); // Insert at bottom
    }

    // 3. Update orders for all items in target category
    List<AppsCategoriesCompanion> orderedAppCategories = [];
    for (int i = 0; i < targetApps.length; ++i) {
      App a = targetApps[i];
      a.categoryOrders[targetCategory.id] = i; // Update local map
      orderedAppCategories.add(AppsCategoriesCompanion(
        categoryId: Value(targetCategory.id),
        appPackageName: Value(a.packageName),
        order: Value(i),
      ));
    }

    // 4. Batch DB update
    await _database.replaceAppsCategories(orderedAppCategories);

    notifyListeners();
  }

  void reorderApplication(Category category, int oldIndex, int newIndex) {
    if (!_categoriesById.containsKey(category.id)) {
      return;
    }
    Category categoryFound = _categoriesById[category.id]!;
    List<App> applications = categoryFound.applications;
    App application = applications.removeAt(oldIndex);
    applications.insert(newIndex, application);

    notifyListeners();
  }

  Future<int> addCategory(String categoryName,
      {CategorySort sort = Category.Sort,
      CategoryType type = Category.Type,
      int columnsCount = Category.ColumnsCount,
      int rowHeight = Category.RowHeight,
      bool shouldNotifyListeners = true}) async {
    List<CategoriesCompanion> orderedCategories = [];
    int categoryOrder = 1, newCategoryId = -1;
    for (Category category in _categoriesById.values) {
      orderedCategories.add(CategoriesCompanion(
          id: Value(category.id), order: Value(categoryOrder++)));
    }

    newCategoryId = await _database.transaction(() async {
      int newCategoryId = await _database.insertCategory(
          CategoriesCompanion.insert(name: categoryName, order: 0));
      await _database.updateCategories(orderedCategories);

      return newCategoryId;
    });

    Map<int, Category> newCategories = Map();
    Category newCategory = Category(
        id: newCategoryId,
        name: categoryName,
        sort: sort,
        type: type,
        columnsCount: columnsCount,
        rowHeight: rowHeight,
        order: 0);
    newCategories[newCategoryId] = newCategory;

    categoryOrder = 1;
    for (Category category in _categoriesById.values) {
      newCategories[category.id] = category;
      category.order = categoryOrder++;
    }

    _categoriesById = newCategories;
    _launcherSections.add(newCategory);

    if (shouldNotifyListeners) {
      notifyListeners();
    }

    return newCategoryId;
  }

  Future<void> updateCategory(int categoryId, String name, CategorySort sort,
      CategoryType type, int columnsCount, int rowHeight,
      {bool shouldNotifyListeners = true}) async {
    Category? category = _categoriesById[categoryId];
    assert(category != null);

    await _database.updateCategory(
        categoryId,
        CategoriesCompanion(
            name: Value(name),
            sort: Value(sort),
            type: Value(type),
            columnsCount: Value(columnsCount),
            rowHeight: Value(rowHeight)));

    CategorySort oldSort = category!.sort;

    category.name = name;
    category.sort = sort;
    category.type = type;
    category.columnsCount = columnsCount;
    category.rowHeight = rowHeight;

    if (oldSort != sort) {
      sortCategory(category);
    }

    if (shouldNotifyListeners) {
      notifyListeners();
    }
  }

  Future<void> addSpacer(int height) async {
    int order = launcherSections.length;
    int spacerId = await _database.insertSpacer(
        LauncherSpacersCompanion.insert(height: height, order: order));

    _launcherSections
        .add(LauncherSpacer(id: spacerId, height: height, order: order));

    notifyListeners();
  }

  Future<void> updateSpacerHeight(LauncherSpacer spacer, int height) async {
    await _database.updateSpacer(
        spacer.id, LauncherSpacersCompanion(height: Value(height)));

    spacer.height = height;
    notifyListeners();
  }

  Future<void> renameCategory(Category category, String categoryName) async {
    await _database.updateCategory(
        category.id, CategoriesCompanion(name: Value(categoryName)));

    if (_categoriesById.containsKey(category.id)) {
      Category categoryFound = _categoriesById[category.id]!;
      categoryFound.name = categoryName;
      notifyListeners();
    }
  }

  Future<void> deleteSection(int index) async {
    assert(index < _launcherSections.length);

    LauncherSection section = _launcherSections[index];
    if (section is Category) {
      await _database.deleteCategory(section.id);
      _categoriesById.remove(section.id);
    } else {
      await _database.deleteSpacer(section.id);
    }

    _launcherSections.removeAt(index);

    notifyListeners();
  }

  void moveSectionInMemory(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= _launcherSections.length ||
        newIndex < 0 ||
        newIndex >= _launcherSections.length) return;

    final section = _launcherSections.removeAt(oldIndex);
    _launcherSections.insert(newIndex, section);
    notifyListeners();
  }

  Future<void> persistSectionsOrder() async {
    List<CategoriesCompanion> orderedCategories = [];
    List<LauncherSpacersCompanion> orderedSpacers = [];

    for (int i = 0; i < _launcherSections.length; ++i) {
      LauncherSection section = _launcherSections[i];
      // Update the order property on the object itself
      if (section is Category)
        section.order = i;
      else if (section is LauncherSpacer) section.order = i;

      if (section is Category) {
        orderedCategories
            .add(CategoriesCompanion(id: Value(section.id), order: Value(i)));
      } else {
        orderedSpacers.add(
            LauncherSpacersCompanion(id: Value(section.id), order: Value(i)));
      }
    }

    await Future.wait([
      _database.updateCategories(orderedCategories),
      _database.updateSpacers(orderedSpacers)
    ]);
  }

  Future<void> moveSection(int oldIndex, int newIndex) async {
    moveSectionInMemory(oldIndex, newIndex);
    await persistSectionsOrder();
  }

  Future<void> hideApplication(App application) async {
    await _database.updateApp(
        application.packageName, const AppsCompanion(hidden: Value(true)));

    if (_applications.containsKey(application.packageName)) {
      App applicationFound = _applications[application.packageName]!;
      applicationFound.hidden = true;

      for (int categoryId in applicationFound.categoryOrders.keys) {
        if (_categoriesById.containsKey(categoryId)) {
          Category category = _categoriesById[categoryId]!;
          category.applications.removeWhere((application0) =>
              application0.packageName == application.packageName);
        }
      }

      notifyListeners();
    }
  }

  Future<void> showApplication(App application) async {
    await _database.updateApp(
        application.packageName, const AppsCompanion(hidden: Value(false)));

    if (_applications.containsKey(application.packageName)) {
      App applicationFound = _applications[application.packageName]!;
      applicationFound.hidden = false;

      for (int categoryId in application.categoryOrders.keys) {
        if (_categoriesById.containsKey(categoryId)) {
          Category category = _categoriesById[categoryId]!;
          category.applications.add(application);
          sortCategory(category);
        }
      }

      notifyListeners();
    }
  }

  Future<void> setCategoryType(Category category, CategoryType type,
      {bool shouldNotifyListeners = true}) async {
    await _database.updateCategory(
        category.id, CategoriesCompanion(type: Value(type)));

    if (_categoriesById.containsKey(category.id)) {
      Category categoryFound = _categoriesById[category.id]!;
      categoryFound.type = type;

      if (shouldNotifyListeners) {
        notifyListeners();
      }
    }
  }

  Future<void> setCategorySort(Category category, CategorySort sort) async {
    await _database.updateCategory(
        category.id, CategoriesCompanion(sort: Value(sort)));
    if (_categoriesById.containsKey(category.id)) {
      Category categoryFound = _categoriesById[category.id]!;
      categoryFound.sort = sort;
      sortCategory(categoryFound);

      notifyListeners();
    }
  }

  Future<void> setCategoryColumnsCount(
      Category category, int columnsCount) async {
    await _database.updateCategory(
        category.id, CategoriesCompanion(columnsCount: Value(columnsCount)));

    if (_categoriesById.containsKey(category.id)) {
      Category categoryFound = _categoriesById[category.id]!;
      categoryFound.columnsCount = columnsCount;

      notifyListeners();
    }
  }

  Future<void> setCategoryRowHeight(Category category, int rowHeight) async {
    await _database.updateCategory(
        category.id, CategoriesCompanion(rowHeight: Value(rowHeight)));

    if (_categoriesById.containsKey(category.id)) {
      Category categoryFound = _categoriesById[category.id]!;
      categoryFound.rowHeight = rowHeight;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _appsSubscription?.cancel();
    super.dispose();
  }
}
