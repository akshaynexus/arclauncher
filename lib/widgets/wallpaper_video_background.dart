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
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class WallpaperVideoBackground extends StatefulWidget {
  const WallpaperVideoBackground({
    super.key,
    this.file,
    this.url,
  }) : assert(file != null || url != null, 'Either file or url must be provided');

  final File? file;
  final String? url;

  @override
  State<WallpaperVideoBackground> createState() =>
      _WallpaperVideoBackgroundState();
}

class _WallpaperVideoBackgroundState extends State<WallpaperVideoBackground>
    with WidgetsBindingObserver {
  Player? _player;
  VideoController? _videoController;
  bool _playerReady = false;

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

    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 20 * 1024 * 1024,
      ),
    );
    _videoController = VideoController(_player!);

    // Hardware decode pipeline — let mpv pick best available decoder
    await _player!.setProperty('hwdec', 'auto');
    await _player!.setProperty('hwdec-codecs', 'all');
    // Optimal thread count for decode parallelism
    await _player!.setProperty('vd-lavc-threads', '0');
    // Buffer tuning for local/network video
    await _player!.setProperty('demuxer-max-bytes', '${32 * 1024 * 1024}');
    await _player!.setProperty('demuxer-max-back-bytes', '${8 * 1024 * 1024}');
    // Enable explicit cache for HTTP streaming
    await _player!.setProperty('cache', 'yes');
    await _player!.setProperty('cache-secs', '30');
    await _player!.setProperty('demuxer-readahead-secs', '20');

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
    final player = _player;
    if (player == null || !player.state.playing) return;
    try {
      final propValue = await player.getProperty('drop-frame-count');
      if (propValue.isNotEmpty) {
        final currentDrops = int.tryParse(propValue) ?? 0;
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
      _player?.stop();
      _openMedia();
    }
  }

  void _openMedia() async {
    final player = _player;
    if (player == null) return;
    try {
      if (widget.url != null) {
        await player.open(Media(widget.url!));
      } else {
        await player.open(Media('file://${widget.file!.path}'));
      }

      player.setPlaylistMode(PlaylistMode.single);
      player.setVolume(0);
    } catch (error) {
      debugPrint('Video wallpaper initialization failed: $error');
    }
  }

  @override
  void dispose() {
    _frameDropTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _player?.stop();
    _player?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _player?.play();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _player?.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_playerReady || _videoController == null) {
      return const ColoredBox(color: Colors.black);
    }

    return RepaintBoundary(
      child: Video(
        controller: _videoController!,
        controls: NoVideoControls,
      ),
    );
  }
}
