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

package com.omeda.arc;

import android.app.Activity;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.Display;
import android.view.SurfaceView;
import android.view.ViewGroup;
import android.widget.FrameLayout;

import androidx.annotation.NonNull;
import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.MediaItem;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.Player;
import androidx.media3.common.VideoSize;
import androidx.media3.datasource.DefaultDataSource;
import androidx.media3.datasource.DefaultHttpDataSource;
import androidx.media3.exoplayer.DefaultLoadControl;
import androidx.media3.exoplayer.DefaultRenderersFactory;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.analytics.AnalyticsListener;
import androidx.media3.exoplayer.analytics.AnalyticsListener.EventTime;
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory;
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
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
    private static final String TAG = "AerialVideoPlayer";
    private static final int MAX_LOG_LINES = 80;
    private static final int MAX_CONSECUTIVE_ERRORS = 5;

    private final Activity activity;
    private final MethodChannel channel;
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final List<String> debugLog = new ArrayList<>();

    private ExoPlayer player;
    private SurfaceView surfaceView;
    private long droppedFrames = 0;
    private int consecutiveErrors = 0;
    private boolean requestedShuffle = false;

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
                case "getDisplayCapabilities" -> result.success(getDisplayCapabilities());
                case "getDebugLog" -> result.success(getDebugLog());
                case "clearDebugLog" -> {
                    clearDebugLog();
                    result.success(null);
                }
                default -> result.notImplemented();
            }
        });
    }

    @SuppressWarnings("unchecked")
    private void setPlaylist(Map<String, Object> args) {
        List<String> urls = (List<String>) args.get("urls");
        requestedShuffle = Boolean.TRUE.equals(args.get("shuffle"));
        boolean nativeShuffle = Boolean.TRUE.equals(args.get("nativeShuffle"));
        int startIndex = intArg(args.get("startIndex"), 0);
        if (urls == null || urls.isEmpty()) {
            addLog("setPlaylist empty; releasing player");
            release();
            return;
        }

        addLog("setPlaylist count=" + urls.size() + " shuffle=" + requestedShuffle
                + " nativeShuffle=" + nativeShuffle + " startIndex=" + startIndex
                + " first=" + urls.get(0));
        ensurePlayer();

        List<MediaItem> items = new ArrayList<>(urls.size());
        for (String url : urls) {
            items.add(MediaItem.fromUri(url));
        }
        player.setMediaItems(items);
        player.setShuffleModeEnabled(nativeShuffle);
        if (startIndex > 0 && startIndex < items.size()) {
            player.seekToDefaultPosition(startIndex);
        }
        consecutiveErrors = 0;
        player.prepare();
        player.play();
        addLog("prepare/play requested");
    }

    private void ensurePlayer() {
        if (player != null) return;

        addLog("creating ExoPlayer");
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

        DefaultHttpDataSource.Factory httpDataSourceFactory = new DefaultHttpDataSource.Factory()
                .setAllowCrossProtocolRedirects(true)
                .setConnectTimeoutMs(15_000)
                .setReadTimeoutMs(30_000)
                .setUserAgent("ArcLauncher/1.0 ExoPlayer");

        DefaultDataSource.Factory dataSourceFactory = new DefaultDataSource.Factory(
                activity.getApplicationContext(),
                httpDataSourceFactory);

        player = new ExoPlayer.Builder(activity.getApplicationContext())
                .setTrackSelector(trackSelector)
                .setRenderersFactory(renderersFactory)
                .setLoadControl(loadControl)
                .setMediaSourceFactory(new DefaultMediaSourceFactory(dataSourceFactory))
                .build();
        player.setVolume(0f);
        player.setRepeatMode(Player.REPEAT_MODE_ALL);
        // Don't let the TV switch display modes to match each video's frame
        // rate — every transition would flash the launcher to black.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            player.setVideoChangeFrameRateStrategy(C.VIDEO_CHANGE_FRAME_RATE_STRATEGY_OFF);
        }
        player.addAnalyticsListener(new AnalyticsListener() {
            @Override
            public void onDroppedVideoFrames(@NonNull EventTime eventTime, int count, long elapsedMs) {
                droppedFrames += count;
                if (count > 5) {
                    addLog("droppedFrames +" + count + " total=" + droppedFrames);
                }
            }

            @Override
            public void onVideoSizeChanged(@NonNull EventTime eventTime, @NonNull VideoSize videoSize) {
                addLog("videoSize " + videoSize.width + "x" + videoSize.height + " ratio=" + videoSize.pixelWidthHeightRatio);
            }
        });
        // Skip to the next video instead of freezing the wallpaper on a
        // bad stream or decoder hiccup.
        player.addListener(new Player.Listener() {
            @Override
            public void onPlayerError(@NonNull PlaybackException error) {
                handlePlayerError(error);
            }

            @Override
            public void onPlaybackStateChanged(int playbackState) {
                addLog("state=" + stateName(playbackState) + " index=" + player.getCurrentMediaItemIndex());
                if (playbackState == Player.STATE_READY) {
                    consecutiveErrors = 0;
                }
            }

            @Override
            public void onIsPlayingChanged(boolean isPlaying) {
                addLog("isPlaying=" + isPlaying);
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
        addLog("surface attached");
    }

    private void handlePlayerError(@NonNull PlaybackException error) {
        consecutiveErrors++;
        addLog("error #" + consecutiveErrors + " code=" + error.getErrorCodeName()
                + " uri=" + currentUri()
                + " message=" + error.getMessage()
                + " cause=" + rootCauseMessage(error));
        if (player == null) return;

        if (consecutiveErrors > MAX_CONSECUTIVE_ERRORS) {
            addLog("too many consecutive errors; pausing recovery");
            player.pause();
            return;
        }

        mainHandler.removeCallbacksAndMessages(null);
        mainHandler.postDelayed(() -> {
            if (player == null) return;
            int itemCount = player.getMediaItemCount();
            if (itemCount == 0) return;

            int nextIndex = (player.getCurrentMediaItemIndex() + 1) % itemCount;
            addLog("recovering with item " + nextIndex + "/" + itemCount);
            player.seekToDefaultPosition(nextIndex);
            player.prepare();
            player.play();
        }, 1000);
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
        stats.put("state", stateName(player.getPlaybackState()));
        stats.put("isPlaying", player.isPlaying());
        stats.put("itemCount", player.getMediaItemCount());
        stats.put("consecutiveErrors", consecutiveErrors);
        stats.put("shuffle", requestedShuffle);
        String uri = currentUri();
        stats.put("video", uri.isEmpty() ? "" : uri.substring(uri.lastIndexOf('/') + 1));
        return stats;
    }

    /// The TV's UI may run at 1080p while the panel supports 4K — report
    /// the largest supported display mode, plus HDR capability.
    private Map<String, Object> getDisplayCapabilities() {
        Map<String, Object> caps = new HashMap<>();
        Display display = activity.getWindowManager().getDefaultDisplay();
        int maxWidth = 0;
        int maxHeight = 0;
        for (Display.Mode mode : display.getSupportedModes()) {
            if (mode.getPhysicalWidth() > maxWidth) {
                maxWidth = mode.getPhysicalWidth();
                maxHeight = mode.getPhysicalHeight();
            }
        }
        boolean isHdr;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            isHdr = display.isHdr();
        } else {
            Display.HdrCapabilities hdrCaps = display.getHdrCapabilities();
            isHdr = hdrCaps != null && hdrCaps.getSupportedHdrTypes().length > 0;
        }
        caps.put("width", maxWidth);
        caps.put("height", maxHeight);
        caps.put("isHdr", isHdr);
        addLog("display caps " + maxWidth + "x" + maxHeight + " hdr=" + isHdr);
        return caps;
    }

    private List<String> getDebugLog() {
        synchronized (debugLog) {
            return new ArrayList<>(debugLog);
        }
    }

    private void clearDebugLog() {
        synchronized (debugLog) {
            debugLog.clear();
        }
    }

    private void addLog(String message) {
        String timestamp =
                new SimpleDateFormat("HH:mm:ss", Locale.US).format(new Date());
        String line = timestamp + "  " + message;
        Log.d(TAG, message);
        synchronized (debugLog) {
            debugLog.add(line);
            if (debugLog.size() > MAX_LOG_LINES) {
                debugLog.remove(0);
            }
        }
    }

    private String stateName(int playbackState) {
        return switch (playbackState) {
            case Player.STATE_IDLE -> "idle";
            case Player.STATE_BUFFERING -> "buffering";
            case Player.STATE_READY -> "ready";
            case Player.STATE_ENDED -> "ended";
            default -> "unknown";
        };
    }

    private String currentUri() {
        if (player == null || player.getCurrentMediaItem() == null ||
                player.getCurrentMediaItem().localConfiguration == null) {
            return "";
        }
        return player.getCurrentMediaItem().localConfiguration.uri.toString();
    }

    private String rootCauseMessage(Throwable error) {
        Throwable cause = error;
        while (cause.getCause() != null) {
            cause = cause.getCause();
        }
        String message = cause.getMessage();
        return cause.getClass().getSimpleName() + (message == null ? "" : ": " + message);
    }

    private int intArg(Object value, int fallback) {
        if (value instanceof Number) {
            return ((Number) value).intValue();
        }
        return fallback;
    }

    public void onResume() {
        addLog("onResume");
        if (player != null) player.play();
    }

    public void onPause() {
        addLog("onPause");
        if (player != null) player.pause();
    }

    public void release() {
        addLog("release");
        mainHandler.removeCallbacksAndMessages(null);
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
        consecutiveErrors = 0;
        requestedShuffle = false;
    }
}
