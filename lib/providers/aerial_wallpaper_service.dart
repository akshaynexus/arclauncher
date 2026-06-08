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

import 'dart:math';

import 'package:aerial_views/aerial_views.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide TimeOfDay;
import 'package:flauncher/providers/settings_service.dart';

class AerialWallpaperService extends ChangeNotifier {
  final SettingsService _settingsService;

  List<AerialMedia> _feed = [];
  int _currentIndex = 0;
  bool _isLoading = false;
  String? _error;
  bool _shuffle = true;

  // User preferences
  int _selectedSourceIndex = 0;
  VideoQuality _selectedQuality = VideoQuality.video1080Sdr;
  final Set<TimeOfDay> _timeOfDayFilter = {};
  final Set<SceneType> _sceneFilter = {};

  List<AerialMedia> get feed => _feed;
  int get currentIndex => _currentIndex;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get shuffle => _shuffle;
  int get selectedSourceIndex => _selectedSourceIndex;
  VideoQuality get selectedQuality => _selectedQuality;
  Set<TimeOfDay> get timeOfDayFilter => Set.unmodifiable(_timeOfDayFilter);
  Set<SceneType> get sceneFilter => Set.unmodifiable(_sceneFilter);

  AerialMedia? get currentVideo {
    if (_feed.isEmpty || _currentIndex >= _feed.length) return null;
    return _feed[_currentIndex];
  }

  String? get currentVideoUrl {
    final video = currentVideo;
    if (video == null) return null;
    return video.url;
  }

  bool get hasNext => _currentIndex < _feed.length - 1;
  bool get hasPrevious => _currentIndex > 0;
  int get totalCount => _feed.length;

  static const List<AerialSource> sources = [
    AerialSource(
      id: 'apple',
      name: 'Apple Aerial',
      icon: Icons.apple,
      description: 'macOS/iOS screensaver videos with 4K HDR support',
    ),
    AerialSource(
      id: 'jetson',
      name: 'Jetson Creative',
      icon: Icons.public,
      description: 'Jetson Creative aerial footage (AerialCommunity)',
    ),
    AerialSource(
      id: 'robin',
      name: 'Robin Fourcade',
      icon: Icons.public,
      description: 'Robin Fourcade aerial videos (AerialShots)',
    ),
    AerialSource(
      id: 'amazon',
      name: 'Amazon/Fire TV',
      icon: Icons.tv,
      description: 'Fire TV aerial screensaver content',
    ),
  ];

  static const List<VideoQuality> qualities = [
    VideoQuality.video1080H264,
    VideoQuality.video1080Sdr,
    VideoQuality.video1080Hdr,
    VideoQuality.video4kSdr,
    VideoQuality.video4kHdr,
  ];

  AerialWallpaperService(this._settingsService) {
    _loadPreferences();
  }

  void _loadPreferences() {
    _selectedSourceIndex = _settingsService.aerialVideoSourceIndex;
    _selectedQuality = VideoQuality.values[_settingsService.aerialVideoQualityIndex];
    _shuffle = _settingsService.aerialVideoShuffle;
  }

  Future<void> initialize() async {
    await refreshFeed();
  }

  Future<void> refreshFeed() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final source = sources[_selectedSourceIndex];
      final List<AerialMedia> allVideos = [];

      // Get providers for this source
      final providers = _getProvidersForSource(source.id);

      for (final provider in providers) {
        final videos = await provider.fetch();
        allVideos.addAll(videos);
      }

      if (_shuffle) {
        allVideos.shuffle(Random());
      }

      _feed = allVideos;
      _currentIndex = 0;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  List<BundledVideoProvider> _getProvidersForSource(String sourceId) {
    switch (sourceId) {
      case 'apple':
        return [
          AppleProvider(
            quality: _selectedQuality,
            timeOfDayFilter: _timeOfDayFilter,
            sceneFilter: _sceneFilter,
          ),
        ];
      case 'jetson':
        return [
          Comm1Provider(
            quality: _selectedQuality,
            timeOfDayFilter: _timeOfDayFilter,
            sceneFilter: _sceneFilter,
          ),
        ];
      case 'robin':
        return [
          Comm2Provider(
            quality: _selectedQuality,
            timeOfDayFilter: _timeOfDayFilter,
            sceneFilter: _sceneFilter,
          ),
        ];
      case 'amazon':
        return [
          AmazonProvider(
            quality: _selectedQuality,
            timeOfDayFilter: _timeOfDayFilter,
            sceneFilter: _sceneFilter,
          ),
        ];
      default:
        return [];
    }
  }

  /// Advance to the next video in the feed
  AerialMedia? next() {
    if (!hasNext) {
      // Loop back to start
      _currentIndex = 0;
      if (_shuffle) _feed.shuffle(Random());
    } else {
      _currentIndex++;
    }
    notifyListeners();
    return currentVideo;
  }

  /// Go to the previous video in the feed
  AerialMedia? previous() {
    if (hasPrevious) {
      _currentIndex--;
    }
    notifyListeners();
    return currentVideo;
  }

  /// Jump to a specific index in the feed
  AerialMedia? jumpTo(int index) {
    if (index >= 0 && index < _feed.length) {
      _currentIndex = index;
      notifyListeners();
    }
    return currentVideo;
  }

  /// Set source and refresh feed
  void setSource(int index) {
    if (index >= 0 && index < sources.length && index != _selectedSourceIndex) {
      _selectedSourceIndex = index;
      _settingsService.setAerialVideoSourceIndex(index);
      refreshFeed();
    }
  }

  /// Set quality and refresh feed
  void setQuality(VideoQuality quality) {
    if (quality != _selectedQuality) {
      _selectedQuality = quality;
      _settingsService.setAerialVideoQualityIndex(quality.index);
      refreshFeed();
    }
  }

  /// Toggle shuffle mode
  void toggleShuffle() {
    _shuffle = !_shuffle;
    _settingsService.setAerialVideoShuffle(_shuffle);
    if (_shuffle) {
      _feed.shuffle(Random());
      _currentIndex = 0;
    }
    notifyListeners();
  }

  /// Add time of day filter
  void addTimeOfDayFilter(TimeOfDay timeOfDay) {
    _timeOfDayFilter.add(timeOfDay);
    refreshFeed();
  }

  /// Remove time of day filter
  void removeTimeOfDayFilter(TimeOfDay timeOfDay) {
    _timeOfDayFilter.remove(timeOfDay);
    refreshFeed();
  }

  /// Add scene filter
  void addSceneFilter(SceneType scene) {
    _sceneFilter.add(scene);
    refreshFeed();
  }

  /// Remove scene filter
  void removeSceneFilter(SceneType scene) {
    _sceneFilter.remove(scene);
    refreshFeed();
  }

  /// Clear all filters
  void clearFilters() {
    _timeOfDayFilter.clear();
    _sceneFilter.clear();
    refreshFeed();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}

class AerialSource {
  final String id;
  final String name;
  final IconData icon;
  final String description;

  const AerialSource({
    required this.id,
    required this.name,
    required this.icon,
    required this.description,
  });
}

String qualityToString(VideoQuality quality) {
  switch (quality) {
    case VideoQuality.video1080H264:
      return '1080p H.264';
    case VideoQuality.video1080Sdr:
      return '1080p SDR';
    case VideoQuality.video1080Hdr:
      return '1080p HDR';
    case VideoQuality.video4kSdr:
      return '4K SDR';
    case VideoQuality.video4kHdr:
      return '4K HDR';
  }
}

String timeOfDayToString(TimeOfDay timeOfDay) {
  switch (timeOfDay) {
    case TimeOfDay.day:
      return 'Day';
    case TimeOfDay.night:
      return 'Night';
    case TimeOfDay.sunset:
      return 'Sunset';
    case TimeOfDay.sunrise:
      return 'Sunrise';
    case TimeOfDay.unknown:
      return 'Unknown';
  }
}

String sceneTypeToString(SceneType scene) {
  switch (scene) {
    case SceneType.nature:
      return 'Nature';
    case SceneType.countryside:
      return 'Countryside';
    case SceneType.waterfall:
      return 'Waterfall';
    case SceneType.beach:
      return 'Beach';
    case SceneType.city:
      return 'City';
    case SceneType.sea:
      return 'Sea';
    case SceneType.space:
      return 'Space';
    case SceneType.patterns:
      return 'Patterns';
    case SceneType.fire:
      return 'Fire';
    case SceneType.unknown:
      return 'Unknown';
  }
}
