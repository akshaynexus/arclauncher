/*
 * FLauncher
 * Copyright (C) 2026
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

package me.efesser.flauncher;

import android.app.Activity;
import android.view.SurfaceView;
import android.view.ViewGroup;
import android.widget.FrameLayout;

import androidx.annotation.NonNull;
import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.MediaItem;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.exoplayer.DefaultLoadControl;
import androidx.media3.exoplayer.DefaultRenderersFactory;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.analytics.AnalyticsListener;
import androidx.media3.exoplayer.analytics.AnalyticsListener.EventTime;
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;

/**
 * Plays aerial wallpaper videos with ExoPlayer in a SurfaceView placed
 * BEHIND the (transparent) FlutterView. MediaCodec decodes straight onto
 * the SurfaceView and SurfaceFlinger composites it, so 4K HEVC HDR10/HLG
 * plays with zero-copy hardware decode and native HDR passthrough —
 * the same pipeline the AerialViews screensaver app uses.
 */
@androidx.media3.common.util.UnstableApi
public class AerialVideoPlayer {
    private final Activity activity;
    private final MethodChannel channel;

    private ExoPlayer player;
    private SurfaceView surfaceView;
    private long droppedFrames = 0;

    public AerialVideoPlayer(@NonNull Activity activity, @NonNull BinaryMessenger messenger) {
        this.activity = activity;
        channel = new MethodChannel(messenger, "me.efesser.flauncher/aerial_video");
        channel.setMethodCallHandler((call, result) -> {
            switch (call.method) {
                case "setPlaylist" -> {
                    Map<String, Object> args = call.arguments();
                    setPlaylist(args);
                    result.success(null);
                }
                case "play" -> {
                    if (player != null) player.play();
                    result.success(null);
                }
                case "pause" -> {
                    if (player != null) player.pause();
                    result.success(null);
                }
                case "stop" -> {
                    release();
                    result.success(null);
                }
                case "getStats" -> result.success(getStats());
                default -> result.notImplemented();
            }
        });
    }

    @SuppressWarnings("unchecked")
    private void setPlaylist(Map<String, Object> args) {
        List<String> urls = (List<String>) args.get("urls");
        boolean shuffle = Boolean.TRUE.equals(args.get("shuffle"));
        if (urls == null || urls.isEmpty()) {
            release();
            return;
        }

        ensurePlayer();

        List<MediaItem> items = new ArrayList<>(urls.size());
        for (String url : urls) {
            items.add(MediaItem.fromUri(url));
        }
        player.setMediaItems(items);
        player.setShuffleModeEnabled(shuffle);
        player.prepare();
        player.play();
    }

    private void ensurePlayer() {
        if (player != null) return;

        // Same configuration as the AerialViews screensaver: decoder
        // fallback enabled, modest buffers so 4K streams don't hog memory.
        DefaultTrackSelector trackSelector = new DefaultTrackSelector(activity);
        DefaultRenderersFactory renderersFactory =
                new DefaultRenderersFactory(activity.getApplicationContext());
        renderersFactory.setEnableDecoderFallback(true);

        DefaultLoadControl loadControl = new DefaultLoadControl.Builder()
                .setBufferDurationsMs(10_000, 20_000, 3_000, 5_000)
                .setTargetBufferBytes(C.LENGTH_UNSET)
                .build();

        player = new ExoPlayer.Builder(activity.getApplicationContext())
                .setTrackSelector(trackSelector)
                .setRenderersFactory(renderersFactory)
                .setLoadControl(loadControl)
                .build();
        player.setVolume(0f);
        player.setRepeatMode(Player.REPEAT_MODE_ALL);
        player.addAnalyticsListener(new AnalyticsListener() {
            @Override
            public void onDroppedVideoFrames(@NonNull EventTime eventTime, int count, long elapsedMs) {
                droppedFrames += count;
            }
        });
        // Skip to the next video instead of freezing the wallpaper on a
        // bad stream or decoder hiccup.
        player.addListener(new Player.Listener() {
            @Override
            public void onPlayerError(@NonNull PlaybackException error) {
                if (player != null) {
                    player.seekToNextMediaItem();
                    player.prepare();
                    player.play();
                }
            }
        });

        surfaceView = new SurfaceView(activity);
        ViewGroup content = activity.findViewById(android.R.id.content);
        content.addView(surfaceView, 0, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        // The window background would otherwise be drawn over the
        // punched-through SurfaceView.
        activity.getWindow().setBackgroundDrawableResource(android.R.color.transparent);
        player.setVideoSurfaceView(surfaceView);
    }

    private Map<String, Object> getStats() {
        Map<String, Object> stats = new HashMap<>();
        if (player == null) return stats;
        Format format = player.getVideoFormat();
        if (format != null) {
            stats.put("fps", (double) format.frameRate);
            stats.put("width", format.width);
            stats.put("height", format.height);
            stats.put("codecs", format.codecs == null ? "" : format.codecs);
        }
        stats.put("droppedFrames", droppedFrames);
        stats.put("index", player.getCurrentMediaItemIndex());
        return stats;
    }

    public void onResume() {
        if (player != null) player.play();
    }

    public void onPause() {
        if (player != null) player.pause();
    }

    public void release() {
        if (player != null) {
            player.setVideoSurface(null);
            player.release();
            player = null;
        }
        if (surfaceView != null) {
            ViewGroup parent = (ViewGroup) surfaceView.getParent();
            if (parent != null) parent.removeView(surfaceView);
            surfaceView = null;
        }
        droppedFrames = 0;
    }
}
