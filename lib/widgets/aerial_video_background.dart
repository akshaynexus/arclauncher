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

  // Frame drop diagnostics
  int _lastFrameCount = 0;
  Timer? _frameDropTimer;

  // FPS overlay
  Timer? _fpsTimer;
  double _currentFps = 0.0;

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
    _openPlaylist();
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

  void _openPlaylist() {
    final service = context.read<AerialWallpaperService>();
    if (service.feed.isEmpty || service.isLoading) return;

    final urls = service.feed.map((video) => video.url).toList();
    final playlistKey = '${service.shuffle}:${urls.join('\n')}';
    if (_nativePlaylistKey == playlistKey) return;

    _nativePlaylistKey = playlistKey;
    _nativeAerialVideoChannel.invokeMethod<void>('setPlaylist', {
      'urls': urls,
      'shuffle': service.shuffle,
    });
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
            });
          } catch (_) {}
        });
      }
    } else {
      _fpsTimer?.cancel();
      _fpsTimer = null;
      if (_currentFps != 0.0) {
        _currentFps = 0.0;
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
      _updateFpsTimer(false);
      return const ColoredBox(color: Colors.black);
    }

    _openPlaylist();
    _updateFpsTimer(showFps);

    return Stack(
      children: [
        const SizedBox.expand(),
        if (showFps) _buildFpsOverlay(),
      ],
    );
  }

  Widget _buildFpsOverlay() {
    return Positioned(
      top: 40,
      right: 40,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
              color: Colors.greenAccent.withValues(alpha: 0.4), width: 1.5),
        ),
        child: Text(
          'FPS: ${_currentFps.toStringAsFixed(1)}',
          style: const TextStyle(
            color: Colors.greenAccent,
            fontSize: 14,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}
