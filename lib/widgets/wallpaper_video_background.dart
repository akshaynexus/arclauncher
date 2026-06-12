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
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class WallpaperVideoBackground extends StatefulWidget {
  const WallpaperVideoBackground({
    super.key,
    this.file,
    this.url,
  }) : assert(
            file != null || url != null, 'Either file or url must be provided');

  final File? file;
  final String? url;

  @override
  State<WallpaperVideoBackground> createState() =>
      _WallpaperVideoBackgroundState();
}

class _WallpaperVideoBackgroundState extends State<WallpaperVideoBackground>
    with WidgetsBindingObserver {
  static const MethodChannel _nativeAerialVideoChannel =
      MethodChannel('me.efesser.flauncher/aerial_video');

  bool _playerReady = false;
  String? _mediaKey;

  // Frame drop diagnostics
  int _lastFrameCount = 0;
  Timer? _frameDropTimer;

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
    _openMedia();
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
            name: 'WallpaperVideoBackground',
          );
        }
        _lastFrameCount = currentDrops;
      }
    } catch (_) {}
  }

  @override
  void didUpdateWidget(WallpaperVideoBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPath = oldWidget.file?.path;
    final newPath = widget.file?.path;
    final oldUrl = oldWidget.url;
    final newUrl = widget.url;

    if (oldPath != newPath || oldUrl != newUrl) {
      _nativeAerialVideoChannel.invokeMethod<void>('stop');
      _mediaKey = null;
      _openMedia();
    }
  }

  void _openMedia() async {
    final uri = widget.url ?? widget.file!.uri.toString();
    if (_mediaKey == uri) return;

    _mediaKey = uri;
    try {
      await _nativeAerialVideoChannel.invokeMethod<void>('setPlaylist', {
        'urls': [uri],
        'shuffle': false,
      });
    } catch (error) {
      debugPrint('Video wallpaper initialization failed: $error');
    }
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    if (!_playerReady) {
      return const ColoredBox(color: Colors.black);
    }

    return const SizedBox.expand();
  }
}
