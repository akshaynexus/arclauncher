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

import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:flauncher/gradients.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:path_provider/path_provider.dart';

class WallpaperService extends ChangeNotifier {
  final SettingsService _settingsService;

  late File _wallpaperFile;
  late File _wallpaperDayFile;
  late File _wallpaperNightFile;
  late File _wallpaperVideoFile;
  late File _wallpaperDayVideoFile;
  late File _wallpaperNightVideoFile;
  bool _initialized = false;
  Timer? _timer;

  ImageProvider? _wallpaper;

  ImageProvider? get wallpaper => _wallpaper;

  File? get wallpaperVideoFile {
    final f = _resolveActiveVideoFile();
    return f != null && f.existsSync() ? f : null;
  }

  FLauncherGradient get gradient => FLauncherGradients.all.firstWhere(
        (gradient) => gradient.uuid == _settingsService.gradientUuid,
        orElse: () => FLauncherGradients.saintPetersburg,
      );

  WallpaperService(this._settingsService) :
    _wallpaper = null
  {
    _settingsService.addListener(_onSettingsChanged);
    _init();
  }

  bool _lastTimeBasedEnabled = false;

  void _onSettingsChanged() {
    final enabled = _settingsService.timeBasedWallpaperEnabled;
    if (enabled != _lastTimeBasedEnabled) {
      _lastTimeBasedEnabled = enabled;
      _updateTimerState();
      _updateWallpaper();
    }
  }

  @override
  void dispose() {
    _settingsService.removeListener(_onSettingsChanged);
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final directory = await getApplicationDocumentsDirectory();
    _wallpaperFile = File("${directory.path}/wallpaper");
    _wallpaperDayFile = File("${directory.path}/wallpaper_day");
    _wallpaperNightFile = File("${directory.path}/wallpaper_night");
    _wallpaperVideoFile = File("${directory.path}/wallpaper_video");
    _wallpaperDayVideoFile = File("${directory.path}/wallpaper_day_video");
    _wallpaperNightVideoFile = File("${directory.path}/wallpaper_night_video");
    _initialized = true;

    _lastTimeBasedEnabled = _settingsService.timeBasedWallpaperEnabled;
    _updateWallpaper();
    _updateTimerState();
  }

  void _updateTimerState() {
    final enabled = _settingsService.timeBasedWallpaperEnabled;
    if (enabled && (_timer == null || !_timer!.isActive)) {
      _timer = Timer.periodic(const Duration(minutes: 1), (_) => _updateWallpaper());
    } else if (!enabled && _timer != null) {
      _timer?.cancel();
      _timer = null;
    }
  }

  File? _resolveActiveVideoFile() {
    if (!isInitialized) return null;

    final now = DateTime.now();
    final isDay = now.hour >= 6 && now.hour < 18;
    final enabled = _settingsService.timeBasedWallpaperEnabled;

    if (enabled) {
      if (isDay && _wallpaperDayVideoFile.existsSync()) {
        return _wallpaperDayVideoFile;
      }
      if (!isDay && _wallpaperNightVideoFile.existsSync()) {
        return _wallpaperNightVideoFile;
      }
      if (_wallpaperVideoFile.existsSync()) {
        return _wallpaperVideoFile;
      }
    } else if (_wallpaperVideoFile.existsSync()) {
      return _wallpaperVideoFile;
    }
    return null;
  }

  bool get isInitialized => _initialized;

  void _updateWallpaper({bool force = false}) {
    final now = DateTime.now();
    final isDay = now.hour >= 6 && now.hour < 18;
    final enabled = _settingsService.timeBasedWallpaperEnabled;

    final videoFile = _resolveActiveVideoFile();

    ImageProvider? newWallpaper;

    if (videoFile != null) {
      newWallpaper = null;
    } else if (enabled) {
      if (isDay && _wallpaperDayFile.existsSync()) {
        newWallpaper = _fileToMemoryImage(_wallpaperDayFile);
      } else if (!isDay && _wallpaperNightFile.existsSync()) {
        newWallpaper = _fileToMemoryImage(_wallpaperNightFile);
      } else if (_wallpaperFile.existsSync()) {
        newWallpaper = _fileToMemoryImage(_wallpaperFile);
      }
    } else if (_wallpaperFile.existsSync()) {
      newWallpaper = _fileToMemoryImage(_wallpaperFile);
    }

    if (_wallpaper != newWallpaper || videoFile != null || force) {
      _wallpaper = newWallpaper;
      notifyListeners();
    }
  }

  ImageProvider? _fileToMemoryImage(File file) {
    try {
      final bytes = file.readAsBytesSync();
      return MemoryImage(Uint8List.fromList(bytes));
    } catch (_) {
      return null;
    }
  }

  Future<void> setWallpaper(File sourceFile) async {
    await _saveToFile(sourceFile, _wallpaperFile);
  }

  Future<void> setWallpaperDay(File sourceFile) async {
    await _saveToFile(sourceFile, _wallpaperDayFile);
  }

  Future<void> setWallpaperNight(File sourceFile) async {
    await _saveToFile(sourceFile, _wallpaperNightFile);
  }

  Future<void> setVideoWallpaper(File sourceFile) async {
    await _saveToFile(sourceFile, _wallpaperVideoFile);
  }

  Future<void> setVideoWallpaperDay(File sourceFile) async {
    await _saveToFile(sourceFile, _wallpaperDayVideoFile);
  }

  Future<void> setVideoWallpaperNight(File sourceFile) async {
    await _saveToFile(sourceFile, _wallpaperNightVideoFile);
  }

  Future<void> _saveToFile(File sourceFile, File targetFile) async {
    final pairedVideo = _pairedVideoForImage(targetFile);
    if (pairedVideo != null && await pairedVideo.exists()) {
      await pairedVideo.delete();
      await cleanVideoWallpaperFiles();
    }

    final bytes = await sourceFile.readAsBytes();
    await targetFile.writeAsBytes(bytes, flush: true);

    _wallpaper = MemoryImage(Uint8List.fromList(bytes));
    notifyListeners();
  }

  File? _pairedVideoForImage(File imageFile) {
    if (imageFile.path == _wallpaperFile.path) return _wallpaperVideoFile;
    if (imageFile.path == _wallpaperDayFile.path) return _wallpaperDayVideoFile;
    if (imageFile.path == _wallpaperNightFile.path) return _wallpaperNightVideoFile;
    return null;
  }

  Future<void> setGradient(FLauncherGradient fLauncherGradient) async {
    await cleanImageWallpaperFiles();
    await cleanVideoWallpaperFiles();

    _wallpaper = null;
    _timer?.cancel();
    _timer = null;

    await _settingsService.setGradientUuid(fLauncherGradient.uuid);
    _updateWallpaper(force: true);
  }

  // Cleaning methods

  Future<void> cleanVideoWallpaperFiles() async {
    if (await _wallpaperVideoFile.exists()) {
      await _wallpaperVideoFile.delete();
    }

    if (await _wallpaperDayVideoFile.exists()) {
      await _wallpaperDayVideoFile.delete();
    }

    if (await _wallpaperNightVideoFile.exists()) {
      await _wallpaperNightVideoFile.delete();
    }
  }

  Future<void> cleanImageWallpaperFiles() async {
    if (await _wallpaperFile.exists()) {
      await _wallpaperFile.delete();
    }

    if (await _wallpaperDayFile.exists()) {
      await _wallpaperDayFile.delete();
    }

    if (await _wallpaperNightFile.exists()) {
      await _wallpaperNightFile.delete();
    }
  }
}

class NoFileExplorerException implements Exception {}
