# Arc Launcher (FLauncher fork)

Android TV launcher built with Flutter. Fork of FLauncher with aerial video wallpapers, premium subscriptions, and TV-optimized UI.

## Architecture

```
lib/
├── main.dart                          # Entry point, Provider setup, RevenueCat init
├── flauncher.dart                     # Main launcher layout (wallpaper host, app grid)
├── flauncher_app.dart                 # MaterialApp + theme + dialog theme
├── database.dart                      # Drift/SQLite database
├── actions.dart                       # Custom BackAction, Focus actions
├── models/
│   ├── app.dart                       # App model
│   └── category.dart                  # Category model
├── providers/                         # ChangeNotifier state management
│   ├── purchases_service.dart         # RevenueCat: isPro, loadOfferings, purchase
│   ├── aerial_wallpaper_service.dart  # Aerial video feeds (Apple, Jetson, Robin, Amazon)
│   ├── settings_service.dart          # SharedPreferences getters/setters
│   ├── wallpaper_service.dart         # Single video/image wallpaper
│   ├── apps_service.dart              # Installed apps list
│   ├── launcher_state.dart            # UI state: panels, home screen
│   ├── brightness_service.dart        # Display brightness
│   ├── network_service.dart           # Connectivity
│   └── update_service.dart            # OTA update check
├── widgets/
│   ├── settings/                      # All settings panels and dialogs
│   │   ├── wallpaper_panel_page.dart  # Aerial views toggle, premium gating, sources, quality, filters
│   │   ├── settings_panel_page.dart   # Restore Purchases, about
│   │   ├── settings_panel.dart        # Wraps settings in SidePanelDialog
│   │   ├── focusable_settings_tile.dart # Reusable TV-focusable row widget
│   │   ├── gradient_panel_page.dart   # Gradient wallpaper config
│   │   ├── update_dialogs.dart        # Update progress/available/install dialogs
│   │   └── flauncher_about_dialog.dart
│   ├── aerial_video_background.dart   # Aerial video player (MethodChannel to native ExoPlayer)
│   ├── wallpaper_video_background.dart # Single video wallpaper
│   ├── side_panel_dialog.dart         # Slide-in dialog for settings
│   ├── app_card.dart                  # App icon grid card
│   ├── tv_media_picker.dart           # File picker dialog
│   ├── rounded_switch_list_tile.dart  # Switch tile wrapping FocusableSettingsTile
│   ├── category_container_common.dart # App category container
│   └── ...
└── generated/locale_keys.g.dart       # Localization keys
```

## Premium / Pro System

- **RevenueCat** via `purchases_flutter` SDK (test API key in `purchases_service.dart`)
- `PurchasesService` exposes `isPro`, `loadOfferings()`, `purchase(identifier)`, `restorePurchases()`
- Purchase options: `PurchaseOption` data class with `identifier`, `title`, `description`, `priceString`, `period`
- Offerings are fetched before showing the premium dialog

### Premium Gating Pattern

Features gated behind `PurchasesService.isPro`. When a non-pro user attempts to enable a pro feature:

1. Dialog is shown with feature list + inline purchase options (e.g. `_PremiumDialog`)
2. User can select a plan or tap "Maybe Later"
3. On purchase: dialog closes, snackbar shows result

See `wallpaper_panel_page.dart:_showPremiumDialog()` and `_PremiumDialog`.

## TV / Leanback Patterns

- **No Google Leanback widgets** — custom Flutter focus handling instead
- `FocusableSettingsTile`: Reusable row with `Focus` + `AnimatedContainer` for visible focus (border, glow, color shift)
- `_TvFilterChip`: Filter chip with focus/selected/focus+selected visual states
- `_DialogOptionTile`: Purchase option card in dialog with focus border/glow
- `_DialogTextButton`: Focusable text button for dialogs
- All interactive widgets use `Actions` + `ActivateIntent`/`ButtonActivateIntent` for D-pad/remote activation
- Dialogs use `showDialog` -> `AlertDialog` with dark theme (`Color(0xFF1E1E1E)` background, rounded corners)
- Dialog theme defined in `flauncher_app.dart`

### Focus Conventions

Every focusable widget follows:
```dart
Actions(
  actions: {
    ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => onTap()),
    ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) => onTap()),
  },
  child: Focus(
    onFocusChange: (hasFocus) => setState(() => _focused = hasFocus),
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        decoration: BoxDecoration(
          border: Border.all(color: _focused ? accent : transparent, width: _focused ? 2.5 : 2.0),
          boxShadow: _focused ? [BoxShadow(color: accent.withOpacity(0.3), blurRadius: 12)] : null,
        ),
        child: ...
      ),
    ),
  ),
)
```

## Aerial Views

- `AerialWallpaperService` manages feeds from 4 sources: Apple, Jetson Creative, Robin Fourcade, Amazon/Fire TV
- Native ExoPlayer in `AerialVideoPlayer.java` behind transparent Flutter SurfaceView
- MethodChannel: `com.hseuniversal.tidytv/aerial_video`
- Supports quality selection (1080p H.264/SDR/HDR, 4K SDR/HDR)
- Filters: time of day, scene type, city
- Playlist caching via SharedPreferences

## Wallpaper Panel (`wallpaper_panel_page.dart`)

Settings panel for wallpaper configuration. Key sections:
- **Aerial Views toggle** — shows lock icon when not pro, triggers premium dialog
- Sources — multi-select checkboxes for aerial video sources
- Quality — radio selection
- Shuffle / FPS toggles
- Filters — time of day, scene, city chips
- Time-based wallpaper / gradient / picture / video

## Key Conventions

- **State management**: `Provider` + `ChangeNotifier` (no Riverpod/Bloc)
- **Localization**: `easy_localization` with `LocaleKeys.*` generated keys
- **Theme**: Material 3 dark, accent color from `SettingsService.accentColor`, `ColorScheme.fromSeed`
- **Colors**: Surface `#1E1E1E`, Background `#121212`
- **`withValues(alpha:)`** used instead of deprecated `withOpacity()`
- **Dialog width**: Default AlertDialog width on TV; use `SidePanelDialog` for side panels (250px wide)
- **Purchases**: RevenueCat offerings loaded asynchronously before showing purchase UI
