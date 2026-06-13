// Copyright (C) 2026 akshaynexus / Akshay CM
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'dart:developer' as developer;

import 'package:flauncher/providers/aerial_wallpaper_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

class AerialVideoBackground extends StatefulWidget {
  const AerialVideoBackground({super.key});

  @override
  State<AerialVideoBackground> createState() => _AerialVideoBackgroundState();
}

class _AerialVideoBackgroundState extends State<AerialVideoBackground>
    with WidgetsBindingObserver {
  static const MethodChannel _nativeAerialVideoChannel =
      MethodChannel('com.hseuniversal.tidytv/aerial_video');

  bool _playerReady = false;
  String? _nativePlaylistKey;
  String? _pendingPlaylistKey;

  // Frame drop diagnostics
  int _lastFrameCount = 0;
  Timer? _frameDropTimer;
  Timer? _playbackIndexTimer;

  // FPS overlay
  Timer? _fpsTimer;
  double _currentFps = 0.0;
  String _playerState = 'unknown';
  bool _isPlaying = false;
  int _itemCount = 0;
  int _currentIndex = 0;
  int _consecutiveErrors = 0;
  int _videoWidth = 0;
  int _videoHeight = 0;
  String _codecs = '';
  String _currentVideo = '';
  int _droppedFrames = 0;
  bool _shuffleActive = false;
  List<String> _debugLogs = const [];
  final List<String> _localDebugLogs = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Defer heavy Player init to post-frame so UI can paint first
    WidgetsBinding.instance.addPostFrameCallback((_) => _initPlayer());
  }

  void _initPlayer() async {
    if (!mounted) return;

    setState(() => _playerReady = true);
    _setupDiagnostics();
    unawaited(_openPlaylist());
  }

  void _setupDiagnostics() {
    _frameDropTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkFrameDrops();
    });
    _playbackIndexTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      unawaited(_savePlaybackIndex());
    });
  }

  Future<void> _checkFrameDrops() async {
    try {
      final stats =
          await _nativeAerialVideoChannel.invokeMapMethod<String, Object?>(
        'getStats',
      );
      final currentDrops = (stats?['droppedFrames'] as num?)?.toInt() ?? 0;
      if (currentDrops > _lastFrameCount) {
        final newDrops = currentDrops - _lastFrameCount;
        if (newDrops > 5) {
          developer.log(
            'Frame drop: $newDrops frames dropped (potential performance issue)',
            name: 'AerialVideoBackground',
          );
        }
        _lastFrameCount = currentDrops;
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _fpsTimer?.cancel();
    _frameDropTimer?.cancel();
    _playbackIndexTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_savePlaybackIndex());
    _nativeAerialVideoChannel.invokeMethod<void>('stop');
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _nativeAerialVideoChannel.invokeMethod<void>('play');
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_savePlaybackIndex());
      _nativeAerialVideoChannel.invokeMethod<void>('pause');
    }
  }

  Future<void> _openPlaylist() async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final service = context.read<AerialWallpaperService>();
    if (service.feed.isEmpty || service.isLoading) {
      _appendLocalDebugLog(
        'skip push feed=${service.feed.length} loading=${service.isLoading}',
      );
      return;
    }

    final urls = service.feed.map(AerialWallpaperService.playableUrl).toList();
    final playlistKey = '${service.shuffle}:${urls.join('\n')}';
    if (_nativePlaylistKey == playlistKey ||
        _pendingPlaylistKey == playlistKey) {
      return;
    }

    _pendingPlaylistKey = playlistKey;
    _appendLocalDebugLog(
      'push playlist count=${urls.length} shuffle=${service.shuffle}',
    );

    try {
      await _nativeAerialVideoChannel.invokeMethod<void>('setPlaylist', {
        'urls': urls,
        'shuffle': service.shuffle,
        'nativeShuffle': false,
        'startIndex': service.playbackResumeIndex,
      });
      if (!mounted) return;
      _nativePlaylistKey = playlistKey;
      _appendLocalDebugLog('push playlist ok');
    } catch (error) {
      if (!mounted) return;
      _appendLocalDebugLog('push playlist failed: $error');
      Future<void>.delayed(const Duration(seconds: 2), () {
        if (mounted && _nativePlaylistKey != playlistKey) {
          unawaited(_openPlaylist());
        }
      });
    } finally {
      if (_pendingPlaylistKey == playlistKey) {
        _pendingPlaylistKey = null;
      }
    }
  }

  Future<void> _savePlaybackIndex() async {
    if (!mounted) return;
    try {
      final stats = await _nativeAerialVideoChannel
          .invokeMapMethod<String, Object?>('getStats');
      final index = (stats?['index'] as num?)?.toInt();
      if (index == null) return;
      await context.read<AerialWallpaperService>().savePlaybackIndex(index);
    } catch (_) {}
  }

  Future<void> _stopNativePlayer(String reason) async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted ||
        (_nativePlaylistKey == null && _pendingPlaylistKey == null)) {
      return;
    }

    _nativePlaylistKey = null;
    _pendingPlaylistKey = null;
    _appendLocalDebugLog('stop player: $reason');
    try {
      await _nativeAerialVideoChannel.invokeMethod<void>('stop');
    } catch (error) {
      _appendLocalDebugLog('stop failed: $error');
    }
  }

  void _updateFpsTimer(bool showFps) {
    if (showFps) {
      if (_fpsTimer == null && _playerReady) {
        _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
          try {
            final stats = await _nativeAerialVideoChannel
                .invokeMapMethod<String, Object?>('getStats');
            if (!mounted) return;
            setState(() {
              _currentFps = (stats?['fps'] as num?)?.toDouble() ?? 0.0;
              _playerState = stats?['state']?.toString() ?? 'unknown';
              _isPlaying = stats?['isPlaying'] == true;
              _itemCount = (stats?['itemCount'] as num?)?.toInt() ?? 0;
              _currentIndex = (stats?['index'] as num?)?.toInt() ?? 0;
              _consecutiveErrors =
                  (stats?['consecutiveErrors'] as num?)?.toInt() ?? 0;
              _videoWidth = (stats?['width'] as num?)?.toInt() ?? 0;
              _videoHeight = (stats?['height'] as num?)?.toInt() ?? 0;
              _codecs = stats?['codecs']?.toString() ?? '';
              _currentVideo = stats?['video']?.toString() ?? '';
              _droppedFrames = (stats?['droppedFrames'] as num?)?.toInt() ?? 0;
              _shuffleActive = stats?['shuffle'] == true;
            });
            final logs = await _nativeAerialVideoChannel
                .invokeListMethod<String>('getDebugLog');
            if (!mounted || logs == null) return;
            setState(() {
              _debugLogs = [
                ..._localDebugLogs.takeLast(4),
                ...logs.takeLast(6),
              ];
            });
          } catch (error) {
            _appendLocalDebugLog('stats failed: $error');
          }
        });
      }
    } else {
      _fpsTimer?.cancel();
      _fpsTimer = null;
      if (_currentFps != 0.0) {
        _currentFps = 0.0;
      }
      if (_debugLogs.isNotEmpty) {
        _debugLogs = const [];
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<AerialWallpaperService>();
    final isLoading = service.isLoading;
    final feedEmpty = service.feed.isEmpty;
    final showFps = service.showFps;

    if (feedEmpty || isLoading || !_playerReady) {
      if (feedEmpty && !isLoading) {
        unawaited(_stopNativePlayer('empty feed'));
      }
      _updateFpsTimer(false);
      return const ColoredBox(color: Colors.black);
    }

    unawaited(_openPlaylist());
    _updateFpsTimer(showFps);

    return Stack(
      children: [
        const SizedBox.expand(),
        if (showFps) _buildDebugOverlay(),
      ],
    );
  }

  Widget _buildDebugOverlay() {
    final service = context.read<AerialWallpaperService>();
    final resolution = _videoWidth > 0 ? '$_videoWidth×$_videoHeight' : '–';
    final isHdrStream = _codecs.toLowerCase().contains('hvc1.2') ||
        _videoHeight >= 2160 && _codecs.toLowerCase().contains('hev');

    String row(String label, String value) => '${label.padRight(10)} $value';

    final statusRows = [
      row('Status', '$_playerState${_isPlaying ? " · playing" : " · paused"}'),
      row('Video',
          '${_currentVideo.isEmpty ? "–" : _currentVideo}  (${_currentIndex + 1}/$_itemCount)'),
      row('Format',
          '$resolution @ ${_currentFps.toStringAsFixed(0)}fps  ${_codecs.isEmpty ? "" : _codecs}${isHdrStream ? "  HDR" : ""}'),
      row('Quality', qualityToString(service.selectedQuality)),
      row('Shuffle', _shuffleActive ? 'on' : 'off'),
      row('Dropped', '$_droppedFrames frames'),
      if (_consecutiveErrors > 0) row('Errors', '$_consecutiveErrors in a row'),
    ];

    return Positioned(
      top: 40,
      right: 40,
      child: Container(
        width: 560,
        constraints: const BoxConstraints(maxHeight: 420),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
              color: Colors.greenAccent.withValues(alpha: 0.4), width: 1.5),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(
              color: Colors.greenAccent,
              fontSize: 13,
              height: 1.4,
              fontFamily: 'monospace'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('AERIAL VIDEO DEBUG',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              ...statusRows.map((line) =>
                  Text(line, maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (_debugLogs.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('LOG',
                    style: TextStyle(
                        color: Colors.greenAccent.withValues(alpha: 0.6))),
                ..._debugLogs.map(
                  (line) => Text(
                    line,
                    style: TextStyle(
                        fontSize: 11.5,
                        color: Colors.white.withValues(alpha: 0.85)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _appendLocalDebugLog(String message) {
    final now = DateTime.now();
    final timestamp = '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    final line = '$timestamp  [dart] $message';
    developer.log(message, name: 'AerialVideoBackground');
    _localDebugLogs.add(line);
    if (_localDebugLogs.length > 20) {
      _localDebugLogs.removeAt(0);
    }
    if (mounted) {
      setState(() {
        _debugLogs = _localDebugLogs.takeLast(8).toList(growable: false);
      });
    }
  }
}

extension _TakeLastExtension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) {
    final items = toList(growable: false);
    if (items.length <= count) return items;
    return items.skip(items.length - count);
  }
}
