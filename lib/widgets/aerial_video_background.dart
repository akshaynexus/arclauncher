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

import 'package:aerial_views/aerial_views.dart';
import 'package:flauncher/providers/aerial_wallpaper_service.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

class AerialVideoBackground extends StatefulWidget {
  const AerialVideoBackground({super.key});

  @override
  State<AerialVideoBackground> createState() => _AerialVideoBackgroundState();
}

class _AerialVideoBackgroundState extends State<AerialVideoBackground>
    with WidgetsBindingObserver {
  Player? _player;
  VideoController? _videoController;
  StreamSubscription<Playlist>? _playlistSubscription;
  bool _playlistOpened = false;
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
    // Buffer tuning for network streams
    await _player!.setProperty('demuxer-max-bytes', '${32 * 1024 * 1024}');
    await _player!.setProperty('demuxer-max-back-bytes', '${8 * 1024 * 1024}');
    // Enable explicit cache for HTTP streaming
    await _player!.setProperty('cache', 'yes');
    await _player!.setProperty('cache-secs', '30');
    await _player!.setProperty('demuxer-readahead-secs', '20');

    if (!mounted) return;
    setState(() => _playerReady = true);

    _setupDiagnostics();

    _playlistSubscription = _player!.stream.playlist.listen((playlist) {
      if (playlist.medias.isEmpty && mounted && _playlistOpened) {
        _openPlaylist();
      }
    });

    _openPlaylist();
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
              name: 'AerialVideoBackground',
            );
          }
          _lastFrameCount = currentDrops;
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _frameDropTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _playlistSubscription?.cancel();
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

  void _openPlaylist() {
    final player = _player;
    if (player == null) return;
    final service = context.read<AerialWallpaperService>();
    if (service.feed.isEmpty || service.isLoading) return;

    final playlist = service.toPlaylist();
    if (playlist.medias.isEmpty) return;

    _playlistOpened = true;
    player.open(playlist, play: true);
    player.setVolume(0);
    player.setPlaylistMode(PlaylistMode.loop);
    player.setShuffle(service.shuffle);
  }

  AerialMedia? _getCurrentVideo() {
    final player = _player;
    if (player == null) return null;
    final service = context.read<AerialWallpaperService>();
    final playlist = player.state.playlist;
    if (playlist.medias.isEmpty) return null;

    final index = playlist.index;
    if (index < 0 || index >= service.feed.length) return null;
    return service.feed[index];
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<AerialWallpaperService>();
    final isLoading = service.isLoading;
    final feedEmpty = service.feed.isEmpty;

    if (feedEmpty || isLoading || !_playerReady || _videoController == null) {
      return const ColoredBox(color: Colors.black);
    }

    return Stack(
      children: [
        RepaintBoundary(
          child: Video(
            controller: _videoController!,
            controls: NoVideoControls,
          ),
        ),
        _buildDescriptionOverlay(),
      ],
    );
  }

  Widget _buildDescriptionOverlay() {
    final player = _player;
    if (player == null) return const SizedBox.shrink();

    return StreamBuilder<Playlist>(
      stream: player.stream.playlist,
      builder: (context, snapshot) {
        final video = _getCurrentVideo();
        if (video == null || video.metadata.shortDescription.isEmpty) {
          return const SizedBox.shrink();
        }

        return Positioned(
          bottom: 60,
          left: 40,
          right: 40,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.7),
                ],
              ),
            ),
            child: Text(
              video.metadata.shortDescription,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                shadows: [
                  Shadow(
                    blurRadius: 8,
                    color: Colors.black,
                  ),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      },
    );
  }
}
