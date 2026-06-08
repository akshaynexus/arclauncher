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

import 'package:flauncher/providers/aerial_wallpaper_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

class AerialVideoBackground extends StatefulWidget {
  const AerialVideoBackground({super.key});

  @override
  State<AerialVideoBackground> createState() => _AerialVideoBackgroundState();
}

class _AerialVideoBackgroundState extends State<AerialVideoBackground>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _isInitializing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCurrentVideo();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeController();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.resumed) {
      controller.play();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      controller.pause();
    }
  }

  void _initializeCurrentVideo() {
    final service = context.read<AerialWallpaperService>();
    final video = service.currentVideo;
    if (video == null || _isInitializing) return;

    _isInitializing = true;
    _disposeController();

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(video.url),
    );
    _controller = controller;

    controller.initialize().then((_) {
      if (!mounted || _controller != controller) {
        _controller = null;
        controller.dispose();
        _isInitializing = false;
        return;
      }

      controller.setLooping(false);
      controller.setVolume(0);

      controller.addListener(() {
        _onVideoProgress();
      });

      controller.play();
      _isInitializing = false;
      setState(() {});
    }).catchError((error) {
      debugPrint('Aerial video initialization failed: $error');
      _isInitializing = false;
      if (mounted) {
        // Try next video on error
        _playNextVideo();
      }
    });
  }

  void _onVideoProgress() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    final position = controller.value.position;
    final duration = controller.value.duration;

    // Auto-advance when video ends (with 1 second buffer)
    if (duration.inSeconds > 0 &&
        position.inSeconds >= duration.inSeconds - 1) {
      controller.removeListener(_onVideoProgress);
      _playNextVideo();
    }
  }

  void _playNextVideo() {
    final service = context.read<AerialWallpaperService>();
    service.next();
    _initializeCurrentVideo();
  }

  void _disposeController() {
    _controller?.removeListener(_onVideoProgress);
    _controller?.dispose();
    _controller = null;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final service = context.watch<AerialWallpaperService>();
    final video = service.currentVideo;

    // Show loading state
    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(color: Colors.black);
    }

    final size = controller.value.size;
    final description = video?.metadata.shortDescription ?? '';

    return Stack(
      children: [
        // Video player
        RepaintBoundary(
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: RepaintBoundary(child: VideoPlayer(controller)),
              ),
            ),
          ),
        ),
        // Video description overlay
        if (description.isNotEmpty)
          Positioned(
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
                description,
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
          ),
        // Video counter
        Positioned(
          top: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${service.currentIndex + 1} / ${service.totalCount}',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
