/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:io';

import 'package:aerial_views/aerial_views.dart';
import 'package:flauncher/providers/aerial_wallpaper_service.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/providers/wallpaper_service.dart';
import 'package:flauncher/widgets/settings/focusable_settings_tile.dart';
import 'package:flauncher/widgets/settings/gradient_panel_page.dart';
import 'package:flauncher/widgets/tv_media_picker.dart';
import 'package:flutter/material.dart' hide TimeOfDay;
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flauncher/generated/locale_keys.g.dart';

import 'package:flauncher/widgets/rounded_switch_list_tile.dart';

class WallpaperPanelPage extends StatelessWidget {
  static const String routeName = "wallpaper_panel";

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Text(LocaleKeys.wallpaper.tr(),
            style: Theme.of(context).textTheme.titleLarge),
        Divider(),
        // Aerial Views toggle
        Consumer<AerialWallpaperService>(builder: (_, aerialService, __) {
          return RoundedSwitchListTile(
            title: Text(LocaleKeys.aerialViews.tr()),
            secondary: Icon(Icons.flight),
            value: aerialService.enabled,
            onChanged: (value) => _toggleAerial(context, value),
          );
        }),
        // Aerial Views settings (shown when enabled)
        Consumer<AerialWallpaperService>(builder: (_, aerialService, __) {
          if (!aerialService.enabled) return SizedBox.shrink();
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
                child: Text(
                  'Sources',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),
              _buildSourceTiles(context, aerialService),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 8, bottom: 4),
                child: Text(
                  'Quality',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),
              _buildQualityTiles(context, aerialService),
              const SizedBox(height: 8),
              _buildShuffleToggle(context, aerialService),
              const SizedBox(height: 8),
              _buildShowFpsToggle(context, aerialService),
              const SizedBox(height: 8),
              _buildFilterSection(context, aerialService),
            ],
          );
        }),
        Consumer<SettingsService>(builder: (_, settings, __) {
          return RoundedSwitchListTile(
            title: Text(LocaleKeys.timeBasedWallpaper.tr()),
            secondary: Icon(Icons.access_time),
            value: settings.timeBasedWallpaperEnabled,
            onChanged: (value) => settings.setTimeBasedWallpaperEnabled(value),
          );
        }),
        Consumer<SettingsService>(builder: (_, settings, __) {
          final wallpaperService = context.read<WallpaperService>();
          if (settings.timeBasedWallpaperEnabled) {
            return Column(
              children: [
                FocusableSettingsTile(
                  leading: Icon(Icons.wb_sunny),
                  title: Text(LocaleKeys.pickDayWallpaper.tr()),
                  onPressed: () => _pickWallpaper(
                      context, wallpaperService.setWallpaperDay, false),
                ),
                FocusableSettingsTile(
                  leading: Icon(Icons.videocam_outlined),
                  title: Text(LocaleKeys.pickDayVideoWallpaper.tr()),
                  onPressed: () => _pickWallpaper(
                      context, wallpaperService.setVideoWallpaperDay, true),
                ),
                FocusableSettingsTile(
                  leading: Icon(Icons.nights_stay),
                  title: Text(LocaleKeys.pickNightWallpaper.tr()),
                  onPressed: () => _pickWallpaper(
                      context, wallpaperService.setWallpaperNight, false),
                ),
                FocusableSettingsTile(
                  leading: Icon(Icons.videocam_outlined),
                  title: Text(LocaleKeys.pickNightVideoWallpaper.tr()),
                  onPressed: () => _pickWallpaper(
                      context, wallpaperService.setVideoWallpaperNight, true),
                ),
              ],
            );
          } else {
            return Column(
              children: [
                FocusableSettingsTile(
                  autofocus: true,
                  leading: Icon(Icons.gradient),
                  title: Text(LocaleKeys.gradient.tr(),
                      style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: () => Navigator.of(context)
                      .pushNamed(GradientPanelPage.routeName),
                ),
                FocusableSettingsTile(
                  leading: Icon(Icons.insert_drive_file_outlined),
                  title: Text(LocaleKeys.picture.tr(),
                      style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: () => _pickWallpaper(
                      context, wallpaperService.setWallpaper, false),
                ),
                FocusableSettingsTile(
                  leading: Icon(Icons.videocam_outlined),
                  title: Text(LocaleKeys.video.tr(),
                      style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: () => _pickWallpaper(
                      context, wallpaperService.setVideoWallpaper, true),
                ),
              ],
            );
          }
        }),
      ],
    );
  }

  Future<void> _toggleAerial(BuildContext context, bool enabled) async {
    final aerialService = context.read<AerialWallpaperService>();
    final settingsService = context.read<SettingsService>();
    await settingsService.setAerialEnabled(enabled);
    if (enabled) {
      await aerialService.initialize();
    } else {
      aerialService.clearFeed();
    }
  }

  Widget _buildSourceTiles(BuildContext context, AerialWallpaperService service) {
    final accentColor = Theme.of(context).colorScheme.primary;
    return Column(
      children: List.generate(AerialWallpaperService.sources.length, (i) {
        final source = AerialWallpaperService.sources[i];
        final isMultiSelected = service.selectedSources.contains(i);
        return FocusableSettingsTile(
          autofocus: i == 0,
          leading: Icon(source.icon, size: 20),
          title: Text(
            source.name,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          trailing: Icon(
            isMultiSelected ? Icons.check_box : Icons.check_box_outline_blank,
            color: isMultiSelected ? accentColor : Colors.white38,
            size: 24,
          ),
          onPressed: () => service.toggleSource(i),
        );
      }),
    );
  }

  Widget _buildQualityTiles(BuildContext context, AerialWallpaperService service) {
    final accentColor = Theme.of(context).colorScheme.primary;
    return Column(
      children: AerialWallpaperService.qualities.map((q) {
        final isSelected = q == service.selectedQuality;
        return FocusableSettingsTile(
          title: Text(
            qualityToString(q),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          trailing: isSelected
              ? Icon(Icons.check_circle, color: accentColor, size: 20)
              : Icon(Icons.radio_button_unchecked,
                  color: Colors.white38, size: 20),
          onPressed: () => service.setQuality(q),
        );
      }).toList(),
    );
  }

  Widget _buildShuffleToggle(BuildContext context, AerialWallpaperService service) {
    return FocusableSettingsTile(
      leading: Icon(Icons.shuffle),
      title: Text(
        'Shuffle videos',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      trailing: Switch(
        value: service.shuffle,
        onChanged: (_) => service.toggleShuffle(),
      ),
      onPressed: () => service.toggleShuffle(),
    );
  }

  Widget _buildShowFpsToggle(BuildContext context, AerialWallpaperService service) {
    return FocusableSettingsTile(
      leading: Icon(Icons.speed),
      title: Text(
        'Show player debug',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      trailing: Switch(
        value: service.showFps,
        onChanged: (_) => service.toggleShowFps(),
      ),
      onPressed: () => service.toggleShowFps(),
    );
  }

  Widget _buildFilterSection(BuildContext context, AerialWallpaperService service) {
    final accentColor = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.filter_list, size: 20, color: accentColor),
              const SizedBox(width: 12),
              Text('Filters', style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 8),
          Text('Time of Day', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: TimeOfDay.values.where((t) => t != TimeOfDay.unknown).map((t) {
              final isSelected = service.timeOfDayFilter.contains(t);
              return _TvFilterChip(
                label: timeOfDayToString(t),
                isSelected: isSelected,
                accentColor: accentColor,
                onPressed: () {
                  if (isSelected) {
                    service.removeTimeOfDayFilter(t);
                  } else {
                    service.addTimeOfDayFilter(t);
                  }
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Text('Scene', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: SceneType.values.where((s) => s != SceneType.unknown).map((s) {
              final isSelected = service.sceneFilter.contains(s);
              return _TvFilterChip(
                label: sceneTypeToString(s),
                isSelected: isSelected,
                accentColor: accentColor,
                onPressed: () {
                  if (isSelected) {
                    service.removeSceneFilter(s);
                  } else {
                    service.addSceneFilter(s);
                  }
                },
              );
            }).toList(),
          ),
          if (service.selectedSources.contains(0)) ...[
            const SizedBox(height: 12),
            Text('Cities', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AerialWallpaperService.cities.map((city) {
                final isSelected = service.cityFilter.contains(city);
                return _TvFilterChip(
                  label: city,
                  isSelected: isSelected,
                  accentColor: accentColor,
                  onPressed: () {
                    if (isSelected) {
                      service.removeCityFilter(city);
                    } else {
                      service.addCityFilter(city);
                    }
                  },
                );
              }).toList(),
            ),
          ],
          if (service.timeOfDayFilter.isNotEmpty || service.sceneFilter.isNotEmpty || service.cityFilter.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _TvFilterChip(
                label: 'Clear all filters',
                isSelected: false,
                accentColor: accentColor,
                icon: Icons.clear_all,
                onPressed: () => service.clearFilters(),
              ),
            ),

        ],
      ),
    );
  }

  Future<void> _pickWallpaper(
      BuildContext context,
      Future<void> Function(File) action,
      bool isVideo) async {
    try {
      final path = await TvMediaPicker.show(
        context,
        mode: isVideo ? TvMediaPickerMode.video : TvMediaPickerMode.image,
      );

      if (path != null) {
        await action(File(path));
      }
    } on NoFileExplorerException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: Duration(seconds: 8),
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red),
                SizedBox(width: 8),
                Text(LocaleKeys.dialogTextNoFileExplorer.tr())
              ],
            ),
          ),
        );
      }
    }
  }
}

/// TV-optimized chip with clear focus/selected/focus+selected states.
/// Replaces FilterChip which has poor TV navigation visibility.
class _TvFilterChip extends StatefulWidget {
  final String label;
  final bool isSelected;
  final Color accentColor;
  final VoidCallback onPressed;
  final IconData? icon;

  const _TvFilterChip({
    required this.label,
    required this.isSelected,
    required this.accentColor,
    required this.onPressed,
    this.icon,
  });

  @override
  State<_TvFilterChip> createState() => _TvFilterChipState();
}

class _TvFilterChipState extends State<_TvFilterChip> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final isFocused = _focused;
    final isSelected = widget.isSelected;
    final accent = widget.accentColor;

    // Background: selected = semi-transparent accent, otherwise subtle white
    Color bgColor;
    if (isSelected && isFocused) {
      bgColor = accent.withValues(alpha: 0.35);
    } else if (isSelected) {
      bgColor = accent.withValues(alpha: 0.25);
    } else if (isFocused) {
      bgColor = Colors.white.withValues(alpha: 0.12);
    } else {
      bgColor = Colors.white.withValues(alpha: 0.06);
    }

    // Border: focused gets accent border, selected gets subtle accent
    Color borderColor;
    double borderWidth;
    if (isFocused) {
      borderColor = accent;
      borderWidth = 2.0;
    } else if (isSelected) {
      borderColor = accent.withValues(alpha: 0.5);
      borderWidth = 1.5;
    } else {
      borderColor = Colors.white.withValues(alpha: 0.1);
      borderWidth = 1.0;
    }

    // Text color: always readable
    final textColor = (isSelected || isFocused) ? Colors.white : Colors.white70;

    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => widget.onPressed()),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
            onInvoke: (_) => widget.onPressed()),
      },
      child: Focus(
        onFocusChange: (hasFocus) => setState(() => _focused = hasFocus),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor, width: borderWidth),
              boxShadow: isFocused
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.3),
                        blurRadius: 10,
                        spreadRadius: 0,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSelected) ...[
                  Icon(Icons.check, size: 16, color: accent),
                  const SizedBox(width: 6),
                ],
                if (widget.icon != null && !isSelected) ...[
                  Icon(widget.icon, size: 16, color: textColor),
                  const SizedBox(width: 6),
                ],
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: textColor,
                    fontWeight: (isSelected || isFocused)
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
