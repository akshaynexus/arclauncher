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
import 'dart:convert';
import 'dart:math';

import 'package:aerial_views/aerial_views.dart';
import 'package:flutter/material.dart' hide TimeOfDay;
import 'package:flutter/services.dart';
import 'package:flauncher/providers/settings_service.dart';

class AerialWallpaperService extends ChangeNotifier {
  static const MethodChannel _nativeAerialVideoChannel =
      MethodChannel('me.efesser.flauncher/aerial_video');

  final SettingsService _settingsService;
  bool _autoQuality = false;

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
  int get playbackResumeIndex => _settingsService.aerialPlaylistPlaybackIndex;

  /// Apple's CDN (sylvan.apple.com) serves these videos over plain http
  /// reliably, while its https endpoint fails certificate validation on
  /// many TVs — always force http for Apple videos.
  static String playableUrl(AerialMedia media) =>
      media.source == AerialMediaSource.apple
          ? media.url.replaceFirst('https://', 'http://')
          : media.url;

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
    final qualityIndex = _settingsService.aerialVideoQualityIndex;
    if (qualityIndex >= 0 && qualityIndex < VideoQuality.values.length) {
      _selectedQuality = VideoQuality.values[qualityIndex];
    } else {
      // No explicit choice — match the TV's capabilities during initialize().
      _autoQuality = true;
    }
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
    if (_autoQuality) {
      await _detectDefaultQuality();
    }
    await refreshFeed();
  }

  /// Pick the best default quality for this TV: 4K and/or HDR when the
  /// display supports it, instead of always starting at 1080p SDR.
  Future<void> _detectDefaultQuality() async {
    try {
      final caps = await _nativeAerialVideoChannel
          .invokeMapMethod<String, Object?>('getDisplayCapabilities');
      final width = (caps?['width'] as num?)?.toInt() ?? 0;
      final isHdr = caps?['isHdr'] == true;
      final is4k = width >= 3000;
      _selectedQuality = is4k
          ? (isHdr ? VideoQuality.video4kHdr : VideoQuality.video4kSdr)
          : (isHdr ? VideoQuality.video1080Hdr : VideoQuality.video1080Sdr);
    } catch (_) {
      _selectedQuality = VideoQuality.video1080Sdr;
    }
    // Not persisted: stays automatic until the user picks one explicitly.
    _autoQuality = false;
  }

  Future<void> refreshFeed() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final cacheKey = _playlistCacheKey();
      final cachedFeed = _restoreCachedFeed(cacheKey);
      if (cachedFeed != null) {
        _feed = cachedFeed;
        _isLoading = false;
        notifyListeners();
        return;
      }

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
            return _cityFilter
                .any((city) => desc.toLowerCase().contains(city.toLowerCase()));
          }
          return true;
        });
      }

      if (_shuffle) {
        allVideos.shuffle(Random());
      }

      _feed = allVideos;
      await _cacheFeed(cacheKey, allVideos);
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
    _cacheFeed(_playlistCacheKey(), _feed);
    notifyListeners();
  }

  /// Toggle show FPS mode
  void toggleShowFps() {
    _showFps = !_showFps;
    _settingsService.setAerialShowFps(_showFps);
    notifyListeners();
  }

  void _saveFilters() {
    _settingsService.setAerialTimeOfDayFilters(
        _timeOfDayFilter.map((t) => t.name).toList());
    _settingsService
        .setAerialSceneFilters(_sceneFilter.map((s) => s.name).toList());
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

  Future<void> savePlaybackIndex(int index) async {
    if (_feed.isEmpty) return;
    final clamped = index.clamp(0, _feed.length - 1);
    await _settingsService.setAerialPlaylistPlaybackIndex(clamped);
  }

  String _playlistCacheKey() {
    final sources = _selectedSources.toList()..sort();
    final timeOfDays = _timeOfDayFilter.map((t) => t.name).toList()..sort();
    final scenes = _sceneFilter.map((s) => s.name).toList()..sort();
    final cities = _cityFilter.map((city) => city.toLowerCase()).toList()
      ..sort();
    return [
      'v1',
      'quality:${_selectedQuality.name}',
      'shuffle:$_shuffle',
      'sources:${sources.join(",")}',
      'time:${timeOfDays.join(",")}',
      'scenes:${scenes.join(",")}',
      'cities:${cities.join(",")}',
    ].join('|');
  }

  List<AerialMedia>? _restoreCachedFeed(String cacheKey) {
    if (_settingsService.aerialPlaylistCacheKey != cacheKey) return null;
    final json = _settingsService.aerialPlaylistCacheJson;
    if (json == null || json.isEmpty) return null;

    try {
      final decoded = jsonDecode(json);
      if (decoded is! List) return null;
      final items = decoded
          .whereType<Map<String, Object?>>()
          .map(_mediaFromJson)
          .whereType<AerialMedia>()
          .toList(growable: false);
      return items.isEmpty ? null : items;
    } catch (_) {
      unawaited(_settingsService.clearAerialPlaylistCache());
      return null;
    }
  }

  Future<void> _cacheFeed(String cacheKey, List<AerialMedia> feed) async {
    if (feed.isEmpty) {
      await _settingsService.clearAerialPlaylistCache();
      return;
    }
    final cacheMatches = _settingsService.aerialPlaylistCacheKey == cacheKey;
    final playbackIndex = cacheMatches
        ? _settingsService.aerialPlaylistPlaybackIndex.clamp(0, feed.length - 1)
        : 0;
    final json = jsonEncode(feed.map(_mediaToJson).toList(growable: false));
    await _settingsService.setAerialPlaylistCache(
      cacheKey: cacheKey,
      json: json,
      playbackIndex: playbackIndex,
    );
  }

  Map<String, Object?> _mediaToJson(AerialMedia media) => {
        'url': media.url,
        'type': media.type.name,
        'source': media.source.name,
        'metadata': {
          'shortDescription': media.metadata.shortDescription,
          'pointsOfInterest': media.metadata.pointsOfInterest
              .map((key, value) => MapEntry(key.toString(), value)),
          'timeOfDay': media.metadata.timeOfDay.name,
          'scene': media.metadata.scene.name,
        },
      };

  AerialMedia? _mediaFromJson(Map<String, Object?> json) {
    final url = json['url'];
    if (url is! String || url.isEmpty) return null;

    final metadataJson = json['metadata'];
    final metadataMap =
        metadataJson is Map ? Map<String, Object?>.from(metadataJson) : null;
    final poiJson = metadataMap?['pointsOfInterest'];
    final pointsOfInterest = poiJson is Map
        ? poiJson.map((key, value) =>
            MapEntry(int.tryParse(key.toString()) ?? 0, value.toString()))
        : const <int, String>{};

    return AerialMedia(
      url: url,
      type: AerialMediaType.values.firstWhere(
        (type) => type.name == json['type'],
        orElse: () => AerialMediaType.video,
      ),
      source: AerialMediaSource.values.firstWhere(
        (source) => source.name == json['source'],
        orElse: () => AerialMediaSource.unknown,
      ),
      metadata: AerialMediaMetadata(
        shortDescription: metadataMap?['shortDescription']?.toString() ?? '',
        pointsOfInterest: pointsOfInterest,
        timeOfDay: TimeOfDay.values.firstWhere(
          (time) => time.name == metadataMap?['timeOfDay'],
          orElse: () => TimeOfDay.unknown,
        ),
        scene: SceneType.values.firstWhere(
          (scene) => scene.name == metadataMap?['scene'],
          orElse: () => SceneType.unknown,
        ),
      ),
    );
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
