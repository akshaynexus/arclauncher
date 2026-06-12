/*
 * FLauncher
 * Copyright (C) 2026 Meddouri Badis
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 */

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
      MethodChannel('me.efesser.flauncher/aerial_video');

  bool _playerReady = false;
  String? _nativePlaylistKey;
  String? _pendingPlaylistKey;

  // Frame drop diagnostics
  int _lastFrameCount = 0;
  Timer? _frameDropTimer;

  // FPS overlay
  Timer? _fpsTimer;
  double _currentFps = 0.0;
  String _playerState = 'unknown';
  bool _isPlaying = false;
  int _itemCount = 0;
  int _consecutiveErrors = 0;
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
    WidgetsBinding.instance.removeObserver(this);
    _nativeAerialVideoChannel.invokeMethod<void>('stop');
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _nativeAerialVideoChannel.invokeMethod<void>('play');
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
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

    final urls = service.feed.map((video) => video.url).toList();
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

  Future<void> _stopNativePlayer(String reason) async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted || (_nativePlaylistKey == null && _pendingPlaylistKey == null)) {
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
              _consecutiveErrors =
                  (stats?['consecutiveErrors'] as num?)?.toInt() ?? 0;
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
    return Positioned(
      top: 40,
      right: 40,
      child: Container(
        width: 560,
        constraints: const BoxConstraints(maxHeight: 360),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
              color: Colors.greenAccent.withValues(alpha: 0.4), width: 1.5),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(
              color: Colors.greenAccent, fontSize: 13, fontFamily: 'monospace'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'VIDEO DEBUG  fps=${_currentFps.toStringAsFixed(1)} '
                'state=$_playerState playing=$_isPlaying '
                'items=$_itemCount errors=$_consecutiveErrors',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              ..._debugLogs.map(
                (line) => Text(
                  line,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _appendLocalDebugLog(String message) {
    final line = '${DateTime.now().toIso8601String()} dart $message';
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
