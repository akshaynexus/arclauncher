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
import 'package:flutter/material.dart' hide TimeOfDay;
import 'package:flauncher/providers/settings_service.dart';
import 'package:media_kit/media_kit.dart';

class AerialWallpaperService extends ChangeNotifier {
  final SettingsService _settingsService;

  List<AerialMedia> _feed = [];
  bool _isLoading = false;
  String? _error;
  bool _shuffle = true;

  // User preferences
  int _selectedSourceIndex = 0;
  final Set<int> _selectedSources = {0};
  VideoQuality _selectedQuality = VideoQuality.video1080Sdr;
  final Set<TimeOfDay> _timeOfDayFilter = {};
  final Set<SceneType> _sceneFilter = {};
  final Set<String> _cityFilter = {};
  bool _showFps = false;


  List<AerialMedia> get feed => _feed;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get shuffle => _shuffle;
  bool get enabled => _settingsService.aerialEnabled;
  int get selectedSourceIndex => _selectedSourceIndex;
  Set<int> get selectedSources => Set.unmodifiable(_selectedSources);
  VideoQuality get selectedQuality => _selectedQuality;
  Set<TimeOfDay> get timeOfDayFilter => Set.unmodifiable(_timeOfDayFilter);
  Set<SceneType> get sceneFilter => Set.unmodifiable(_sceneFilter);
  Set<String> get cityFilter => Set.unmodifiable(_cityFilter);
  bool get showFps => _showFps;
  int get totalCount => _feed.length;


  /// Convert feed to a media_kit Playlist
  Playlist toPlaylist() {
    return Playlist(
      _feed.map((v) => Media(v.url)).toList(),
    );
  }

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

  static const List<String> cities = [
    'Dubai',
    'Hong Kong',
    'London',
    'Los Angeles',
    'New York',
    'San Francisco',
  ];


  AerialWallpaperService(this._settingsService) {
    _loadPreferences();
    if (enabled) {
      initialize();
    }
  }

  void _loadPreferences() {
    _selectedSourceIndex = _settingsService.aerialVideoSourceIndex;
    final savedSources = _settingsService.aerialSelectedSources;
    if (savedSources.isNotEmpty) {
      _selectedSources.addAll(savedSources);
    } else {
      _selectedSources.add(_selectedSourceIndex);
    }
    _selectedQuality = VideoQuality.values[_settingsService.aerialVideoQualityIndex];
    _shuffle = _settingsService.aerialVideoShuffle;
    _showFps = _settingsService.aerialShowFps;

    final savedTimeOfDays = _settingsService.aerialTimeOfDayFilters;
    _timeOfDayFilter.clear();
    for (final name in savedTimeOfDays) {
      final t = TimeOfDay.fromString(name);
      if (t != TimeOfDay.unknown) {
        _timeOfDayFilter.add(t);
      }
    }

    final savedScenes = _settingsService.aerialSceneFilters;
    _sceneFilter.clear();
    for (final name in savedScenes) {
      final s = SceneType.fromString(name);
      if (s != SceneType.unknown) {
        _sceneFilter.add(s);
      }
    }

    final savedCities = _settingsService.aerialCityFilters;
    _cityFilter.clear();
    _cityFilter.addAll(savedCities);
  }


  Future<void> initialize() async {
    await refreshFeed();
  }

  Future<void> refreshFeed() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final List<AerialMedia> allVideos = [];

      for (final sourceIndex in _selectedSources) {
        if (sourceIndex < 0 || sourceIndex >= sources.length) continue;
        final source = sources[sourceIndex];
        final providers = _getProvidersForSource(source.id);
        for (final provider in providers) {
          final videos = await provider.fetch();
          final enriched = provider.fetchMetadata(videos);
          allVideos.addAll(enriched);
        }
      }

      // Apply city filter if populated (only filters city videos)
      if (_cityFilter.isNotEmpty) {
        allVideos.retainWhere((item) {
          if (item.metadata.scene == SceneType.city) {
            final desc = item.metadata.shortDescription;
            return _cityFilter.any((city) => desc.toLowerCase().contains(city.toLowerCase()));
          }
          return true;
        });
      }

      if (_shuffle) {
        allVideos.shuffle(Random());
      }

      _feed = allVideos;

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

  /// Set the primary source (also ensures it's in selected sources)
  void setSource(int index) {
    if (index >= 0 && index < sources.length) {
      _selectedSourceIndex = index;
      _selectedSources.add(index);
      _settingsService.setAerialVideoSourceIndex(index);
      _settingsService.setAerialSelectedSources(_selectedSources.toList());
      refreshFeed();
    }
  }

  /// Toggle a source in the multi-source selection
  void toggleSource(int index) {
    if (index < 0 || index >= sources.length) return;
    if (_selectedSources.contains(index)) {
      if (_selectedSources.length <= 1) return;
      _selectedSources.remove(index);
    } else {
      _selectedSources.add(index);
    }
    _settingsService.setAerialSelectedSources(_selectedSources.toList());
    refreshFeed();
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
    }
    notifyListeners();
  }

  /// Toggle show FPS mode
  void toggleShowFps() {
    _showFps = !_showFps;
    _settingsService.setAerialShowFps(_showFps);
    notifyListeners();
  }

  void _saveFilters() {
    _settingsService.setAerialTimeOfDayFilters(_timeOfDayFilter.map((t) => t.name).toList());
    _settingsService.setAerialSceneFilters(_sceneFilter.map((s) => s.name).toList());
    _settingsService.setAerialCityFilters(_cityFilter.toList());
  }


  /// Add time of day filter
  void addTimeOfDayFilter(TimeOfDay timeOfDay) {
    _timeOfDayFilter.add(timeOfDay);
    _saveFilters();
    refreshFeed();
  }

  /// Remove time of day filter
  void removeTimeOfDayFilter(TimeOfDay timeOfDay) {
    _timeOfDayFilter.remove(timeOfDay);
    _saveFilters();
    refreshFeed();
  }

  /// Add scene filter
  void addSceneFilter(SceneType scene) {
    _sceneFilter.add(scene);
    _saveFilters();
    refreshFeed();
  }

  /// Remove scene filter
  void removeSceneFilter(SceneType scene) {
    _sceneFilter.remove(scene);
    _saveFilters();
    refreshFeed();
  }

  /// Add city filter
  void addCityFilter(String city) {
    _cityFilter.add(city);
    _saveFilters();
    refreshFeed();
  }

  /// Remove city filter
  void removeCityFilter(String city) {
    _cityFilter.remove(city);
    _saveFilters();
    refreshFeed();
  }

  /// Clear all filters
  void clearFilters() {
    _timeOfDayFilter.clear();
    _sceneFilter.clear();
    _cityFilter.clear();
    _saveFilters();
    refreshFeed();
  }


  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearFeed() {
    _feed = [];
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
