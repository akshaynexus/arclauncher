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
import 'package:flauncher/l10n/app_localizations.dart';

import 'package:flauncher/widgets/rounded_switch_list_tile.dart';

class WallpaperPanelPage extends StatelessWidget {
  static const String routeName = "wallpaper_panel";

  @override
  Widget build(BuildContext context) {
    AppLocalizations localizations = AppLocalizations.of(context)!;

    return Column(
      children: [
        Text(localizations.wallpaper,
            style: Theme.of(context).textTheme.titleLarge),
        Divider(),
        // Aerial Views toggle
        Consumer<AerialWallpaperService>(builder: (_, aerialService, __) {
          return RoundedSwitchListTile(
            title: Text(localizations.aerialViews),
            secondary: Icon(Icons.flight),
            value: aerialService.feed.isNotEmpty,
            onChanged: (value) => _toggleAerial(context, value),
          );
        }),
        // Aerial Views settings (shown when enabled)
        Consumer<AerialWallpaperService>(builder: (_, aerialService, __) {
          if (aerialService.feed.isEmpty) return SizedBox.shrink();
          return Column(
            children: [
              _buildSourceDropdown(context, aerialService),
              _buildQualityDropdown(context, aerialService),
              _buildShuffleToggle(context, aerialService),
              _buildFilterChips(context, aerialService),
            ],
          );
        }),
        Consumer<SettingsService>(builder: (_, settings, __) {
          return RoundedSwitchListTile(
            title: Text(localizations.timeBasedWallpaper),
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
                  title: Text(localizations.pickDayWallpaper),
                  onPressed: () => _pickWallpaper(
                      context, wallpaperService.setWallpaperDay, false, localizations),
                ),
                FocusableSettingsTile(
                  leading: Icon(Icons.videocam_outlined),
                  title: Text(localizations.pickDayVideoWallpaper),
                  onPressed: () => _pickWallpaper(
                      context, wallpaperService.setVideoWallpaperDay, true, localizations),
                ),
                FocusableSettingsTile(
                  leading: Icon(Icons.nights_stay),
                  title: Text(localizations.pickNightWallpaper),
                  onPressed: () => _pickWallpaper(
                      context, wallpaperService.setWallpaperNight, false, localizations),
                ),
                FocusableSettingsTile(
                  leading: Icon(Icons.videocam_outlined),
                  title: Text(localizations.pickNightVideoWallpaper),
                  onPressed: () => _pickWallpaper(
                      context, wallpaperService.setVideoWallpaperNight, true, localizations),
                ),
              ],
            );
          } else {
            return Column(
              children: [
                FocusableSettingsTile(
                  autofocus: true,
                  leading: Icon(Icons.gradient),
                  title: Text(localizations.gradient,
                      style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: () => Navigator.of(context)
                      .pushNamed(GradientPanelPage.routeName),
                ),
                FocusableSettingsTile(
                  leading: Icon(Icons.insert_drive_file_outlined),
                  title: Text(localizations.picture,
                      style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: () => _pickWallpaper(
                      context, wallpaperService.setWallpaper, false, localizations),
                ),
                FocusableSettingsTile(
                  leading: Icon(Icons.videocam_outlined),
                  title: Text(localizations.video,
                      style: Theme.of(context).textTheme.bodyMedium),
                  onPressed: () => _pickWallpaper(
                      context, wallpaperService.setVideoWallpaper, true, localizations),
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
    if (enabled) {
      await aerialService.initialize();
    } else {
      // Clear the feed
      aerialService.refreshFeed();
    }
  }

  Widget _buildSourceDropdown(BuildContext context, AerialWallpaperService service) {
    final accentColor = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.source, size: 20, color: accentColor),
          const SizedBox(width: 12),
          Text('Source:', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButton<int>(
                value: service.selectedSourceIndex,
                dropdownColor: const Color(0xFF2A2A4E),
                style: const TextStyle(color: Colors.white),
                underline: const SizedBox(),
                isDense: true,
                isExpanded: true,
                items: List.generate(AerialWallpaperService.sources.length, (i) {
                  final source = AerialWallpaperService.sources[i];
                  return DropdownMenuItem(
                    value: i,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(source.icon, size: 16, color: accentColor),
                        const SizedBox(width: 8),
                        Text(source.name, style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                  );
                }),
                onChanged: (index) {
                  if (index != null) service.setSource(index);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQualityDropdown(BuildContext context, AerialWallpaperService service) {
    final accentColor = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.high_quality, size: 20, color: accentColor),
          const SizedBox(width: 12),
          Text('Quality:', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(8),
              ),
              child: DropdownButton<VideoQuality>(
                value: service.selectedQuality,
                dropdownColor: const Color(0xFF2A2A4E),
                style: const TextStyle(color: Colors.white),
                underline: const SizedBox(),
                isDense: true,
                isExpanded: true,
                items: AerialWallpaperService.qualities.map((q) {
                  return DropdownMenuItem(
                    value: q,
                    child: Text(qualityToString(q), style: const TextStyle(fontSize: 13)),
                  );
                }).toList(),
                onChanged: (q) {
                  if (q != null) service.setQuality(q);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShuffleToggle(BuildContext context, AerialWallpaperService service) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.shuffle, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Shuffle videos', style: Theme.of(context).textTheme.bodyMedium),
          ),
          Switch(
            value: service.shuffle,
            onChanged: (_) => service.toggleShuffle(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(BuildContext context, AerialWallpaperService service) {
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
              Text('Time of Day:', style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: TimeOfDay.values.where((t) => t != TimeOfDay.unknown).map((t) {
              final isSelected = service.timeOfDayFilter.contains(t);
              return FilterChip(
                label: Text(timeOfDayToString(t), style: const TextStyle(fontSize: 12)),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    service.addTimeOfDayFilter(t);
                  } else {
                    service.removeTimeOfDayFilter(t);
                  }
                },
                backgroundColor: Colors.white10,
                selectedColor: accentColor,
                checkmarkColor: Colors.white,
                labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.landscape, size: 20, color: accentColor),
              const SizedBox(width: 12),
              Text('Scene:', style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: SceneType.values.where((s) => s != SceneType.unknown).map((s) {
              final isSelected = service.sceneFilter.contains(s);
              return FilterChip(
                label: Text(sceneTypeToString(s), style: const TextStyle(fontSize: 12)),
                selected: isSelected,
                onSelected: (selected) {
                  if (selected) {
                    service.addSceneFilter(s);
                  } else {
                    service.removeSceneFilter(s);
                  }
                },
                backgroundColor: Colors.white10,
                selectedColor: accentColor,
                checkmarkColor: Colors.white,
                labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70),
              );
            }).toList(),
          ),
          if (service.timeOfDayFilter.isNotEmpty || service.sceneFilter.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: TextButton(
                onPressed: () => service.clearFilters(),
                child: Text('Clear all filters'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickWallpaper(
      BuildContext context,
      Future<void> Function(File) action,
      bool isVideo,
      AppLocalizations? localizations) async {
    try {
      final path = await TvMediaPicker.show(
        context,
        mode: isVideo ? TvMediaPickerMode.video : TvMediaPickerMode.image,
      );

      if (path != null) {
        await action(File(path));
      }
    } on NoFileExplorerException {
      if (localizations != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: Duration(seconds: 8),
            content: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red),
                SizedBox(width: 8),
                Text(localizations.dialogTextNoFileExplorer)
              ],
            ),
          ),
        );
      }
    }
  }
}
