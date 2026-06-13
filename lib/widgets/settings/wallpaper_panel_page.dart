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
import 'package:flauncher/providers/purchases_service.dart';
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
        // Aerial Views toggle (gated behind premium)
        Consumer<AerialWallpaperService>(builder: (_, aerialService, __) {
          return Consumer<PurchasesService>(builder: (_, purchasesService, __) {
            final isPro = purchasesService.isPro;
            return FocusableSettingsTile(
              title: Text(LocaleKeys.aerialViews.tr()),
              leading: Icon(Icons.flight),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isPro)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Icon(Icons.lock, size: 16, color: Colors.white38),
                    ),
                  Switch(
                    value: aerialService.enabled,
                    onChanged: (value) {
                      if (value && !isPro) {
                        _showPremiumDialog(context);
                        return;
                      }
                      _toggleAerial(context, value);
                    },
                  ),
                ],
              ),
              onPressed: () {
                final newValue = !aerialService.enabled;
                if (newValue && !isPro) {
                  _showPremiumDialog(context);
                  return;
                }
                _toggleAerial(context, newValue);
              },
            );
          });
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

  Future<void> _showReverseTrialOffer(BuildContext context,
      PurchasesService purchasesService, Color accentColor) async {
    final trialOption = purchasesService.trialOption;
    if (trialOption == null) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        contentPadding: EdgeInsets.zero,
        content: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      accentColor.withValues(alpha: 0.4),
                      accentColor.withValues(alpha: 0.08),
                      const Color(0xFF1E1E1E),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            accentColor,
                            accentColor.withValues(alpha: 0.6),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.4),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.card_giftcard,
                          color: Colors.white, size: 28),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Enjoy Pro Free',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Try all premium features free for\n${trialOption.trialDuration ?? 'a limited time'}.\nNo commitment, cancel anytime.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withValues(alpha: 0.6),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  children: [
                    Actions(
                      actions: {
                        ActivateIntent: CallbackAction<ActivateIntent>(
                            onInvoke: (_) => Navigator.of(ctx).pop(true)),
                        ButtonActivateIntent:
                            CallbackAction<ButtonActivateIntent>(
                                onInvoke: (_) => Navigator.of(ctx).pop(true)),
                      },
                      child: Focus(
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            style: FilledButton.styleFrom(
                              backgroundColor: accentColor,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                            child: Text(
                              'Start ${trialOption.trialDuration ?? 'Free Trial'}',
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Actions(
                      actions: {
                        ActivateIntent: CallbackAction<ActivateIntent>(
                            onInvoke: (_) => Navigator.of(ctx).pop(false)),
                        ButtonActivateIntent:
                            CallbackAction<ButtonActivateIntent>(
                                onInvoke: (_) => Navigator.of(ctx).pop(false)),
                      },
                      child: Focus(
                        child: TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('No thanks'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (accepted == true && context.mounted) {
      final result =
          await purchasesService.purchase(trialOption.identifier);
      if (!context.mounted) return;
      switch (result) {
        case PurchaseResult.success:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Welcome to Pro! Enjoy your free trial.'),
              backgroundColor: Colors.green,
            ),
          );
        case PurchaseResult.cancelled:
          break;
        case PurchaseResult.error:
          if (context.mounted) {
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: const Color(0xFF1E1E1E),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                title: const Text('Purchase Failed'),
                content: const Text(
                    'There was an error processing your purchase.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }
      }
    }
  }

  Future<void> _showPremiumDialog(BuildContext context) async {
    final purchasesService = context.read<PurchasesService>();
    final accentColor = Theme.of(context).colorScheme.primary;

    await purchasesService.loadOfferings();
    if (!context.mounted) return;

    final options = purchasesService.purchaseOptions;

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (dialogContext) => _PremiumDialog(
        accentColor: accentColor,
        options: options,
        onReverseTrial: purchasesService.trialOption != null
            ? () {
                Navigator.of(dialogContext).pop();
                _showReverseTrialOffer(context, purchasesService, accentColor);
              }
            : null,
        onPurchase: (option) async {
          Navigator.of(dialogContext).pop();
          final result = await purchasesService.purchase(option.identifier);
          if (!context.mounted) return;
          switch (result) {
            case PurchaseResult.success:
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(option.hasFreeTrial
                      ? 'Welcome to Pro! Enjoy your free trial.'
                      : 'Welcome to Pro!'),
                  backgroundColor: Colors.green,
                ),
              );
            case PurchaseResult.cancelled:
              break;
            case PurchaseResult.error:
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1E1E1E),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  title: const Text('Purchase Failed'),
                  content: const Text(
                      'There was an error processing your purchase. Please try again later.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
          }
        },
      ),
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

  Widget _buildSourceTiles(
      BuildContext context, AerialWallpaperService service) {
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

  Widget _buildQualityTiles(
      BuildContext context, AerialWallpaperService service) {
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

  Widget _buildShuffleToggle(
      BuildContext context, AerialWallpaperService service) {
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

  Widget _buildShowFpsToggle(
      BuildContext context, AerialWallpaperService service) {
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

  Widget _buildFilterSection(
      BuildContext context, AerialWallpaperService service) {
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
            children:
                TimeOfDay.values.where((t) => t != TimeOfDay.unknown).map((t) {
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
            children:
                SceneType.values.where((s) => s != SceneType.unknown).map((s) {
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
          if (service.timeOfDayFilter.isNotEmpty ||
              service.sceneFilter.isNotEmpty ||
              service.cityFilter.isNotEmpty)
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

  Future<void> _pickWallpaper(BuildContext context,
      Future<void> Function(File) action, bool isVideo) async {
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
        ActivateIntent:
            CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onPressed()),
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

class _PremiumDialog extends StatelessWidget {
  final Color accentColor;
  final List<PurchaseOption> options;
  final void Function(PurchaseOption) onPurchase;
  final void Function()? onReverseTrial;

  const _PremiumDialog({
    required this.accentColor,
    required this.options,
    required this.onPurchase,
    this.onReverseTrial,
  });

  String _savingsPercent(PurchaseOption annual) {
    if (options.length < 2) return '';
    final monthly = options.where((o) => o.period == 'month').firstOrNull;
    if (monthly == null) return '';
    final annualPrice = double.tryParse(annual.priceString.replaceAll(RegExp(r'[^0-9.]'), ''));
    final monthlyPrice = double.tryParse(monthly.priceString.replaceAll(RegExp(r'[^0-9.]'), ''));
    if (annualPrice == null || monthlyPrice == null || monthlyPrice == 0) return '';
    final yearlyCost = monthlyPrice * 12;
    final savings = ((yearlyCost - annualPrice) / yearlyCost * 100).round();
    if (savings <= 0) return '';
    return 'Save $savings%';
  }

  bool get _anyHasTrial => options.any((o) => o.hasFreeTrial);
  String? get _trialDuration => options.firstWhere((o) => o.hasFreeTrial, orElse: () => options.first).trialDuration;
  bool get _hasMonthly => options.any((o) => o.period == 'month');

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      contentPadding: EdgeInsets.zero,
      content: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          const _ProFeatureRow('Apple TV aerial videos'),
                          const _ProFeatureRow('Multiple quality options'),
                          const _ProFeatureRow('Smart shuffle & filters'),
                          const _ProFeatureRow('Time, scene & city filters'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Container(height: 1, color: Colors.white12, width: 24),
                        const SizedBox(width: 8),
                        Text(
                          _anyHasTrial ? 'Start your ${_trialDuration ?? ''} free trial' : 'Choose your plan',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white38,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Container(height: 1, color: Colors.white12)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ...options.asMap().entries.map((e) => _DialogOptionTile(
                          option: e.value,
                          accentColor: accentColor,
                          onTap: () => onPurchase(e.value),
                          index: e.key,
                          total: options.length,
                          savingsLabel: e.value.period == 'year' && _hasMonthly
                              ? _savingsPercent(e.value)
                              : null,
                        )),
                    const SizedBox(height: 12),
                    Center(
                      child: _DialogTextButton(
                        label: _anyHasTrial ? 'Maybe later' : 'Not now',
                        onTap: () {
                          if (onReverseTrial != null) {
                            onReverseTrial!();
                          } else {
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withValues(alpha: 0.4),
            accentColor.withValues(alpha: 0.08),
            const Color(0xFF1E1E1E),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  accentColor,
                  accentColor.withValues(alpha: 0.6),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.4),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            _anyHasTrial ? 'Try Pro Free' : 'Upgrade to Pro',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _anyHasTrial
                ? 'Enjoy full access for $_trialDuration.\nCancel anytime.'
                : 'Unlock stunning aerial video wallpapers\nfrom around the world.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.6),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// A focusable text button for TV remote navigation.
class _DialogTextButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _DialogTextButton({
    required this.label,
    required this.onTap,
  });

  @override
  State<_DialogTextButton> createState() => _DialogTextButtonState();
}

class _DialogTextButtonState extends State<_DialogTextButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent:
            CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onTap()),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
            onInvoke: (_) => widget.onTap()),
      },
      child: Focus(
        onFocusChange: (hasFocus) => setState(() => _focused = hasFocus),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _focused ? accent : Colors.white12,
                width: _focused ? 2.0 : 1.0,
              ),
              color:
                  _focused ? accent.withValues(alpha: 0.1) : Colors.transparent,
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                color: _focused ? Colors.white : Colors.white54,
                fontSize: 15,
                fontWeight: _focused ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProFeatureRow extends StatelessWidget {
  final String text;

  const _ProFeatureRow(this.text);

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(Icons.check_circle, size: 18, color: accent),
          const SizedBox(width: 12),
          Text(text,
              style: const TextStyle(color: Colors.white, fontSize: 14)),
        ],
      ),
    );
  }
}

/// Leanback-optimized purchase option tile for dialogs.
/// Uses Focus with visible border/glow for TV remote navigation.
class _DialogOptionTile extends StatefulWidget {
  final PurchaseOption option;
  final Color accentColor;
  final VoidCallback onTap;
  final int index;
  final int total;
  final String? savingsLabel;

  const _DialogOptionTile({
    required this.option,
    required this.accentColor,
    required this.onTap,
    this.index = 0,
    this.total = 1,
    this.savingsLabel,
  });

  @override
  State<_DialogOptionTile> createState() => _DialogOptionTileState();
}

class _DialogOptionTileState extends State<_DialogOptionTile> {
  bool _focused = false;

  bool get _isBestValue => widget.option.period == 'year';

  @override
  Widget build(BuildContext context) {
    final option = widget.option;
    final accent = widget.accentColor;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Actions(
        actions: {
          ActivateIntent:
              CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onTap()),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
              onInvoke: (_) => widget.onTap()),
        },
        child: Focus(
          onFocusChange: (hasFocus) => setState(() => _focused = hasFocus),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isBestValue
                      ? (_focused ? accent : accent)
                      : (_focused ? accent : Colors.white.withValues(alpha: 0.08)),
                  width: _isBestValue ? 2.0 : (_focused ? 2.5 : 1.0),
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _isBestValue
                      ? [
                          accent.withValues(alpha: _focused ? 0.25 : 0.15),
                          accent.withValues(alpha: _focused ? 0.12 : 0.06),
                        ]
                      : [
                          accent.withValues(alpha: _focused ? 0.15 : 0.06),
                          accent.withValues(alpha: _focused ? 0.08 : 0.03),
                        ],
                ),
                boxShadow: _focused
                    ? [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.3),
                          blurRadius: 12,
                          spreadRadius: 0,
                        ),
                      ]
                    : (_isBestValue
                        ? [
                            BoxShadow(
                              color: accent.withValues(alpha: 0.15),
                              blurRadius: 8,
                              spreadRadius: 0,
                            ),
                          ]
                        : null),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isBestValue)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star, size: 12, color: Colors.white),
                          const SizedBox(width: 4),
                          const Text('Best value',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white)),
                        ],
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              option.title,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: _focused ? Colors.white : Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              option.description,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            option.priceString,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: accent,
                            ),
                          ),
                          if (option.period.isNotEmpty && !_isBestValue)
                            Text(
                              '/ ${option.period}',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.4),
                              ),
                            ),
                          if (_isBestValue)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '/ ${option.period}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: accent.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  if (widget.savingsLabel != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: accent.withValues(alpha: 0.15),
                      ),
                      child: Text(
                        widget.savingsLabel!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                  if (option.hasFreeTrial) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.card_giftcard,
                            size: 12,
                            color: Colors.white.withValues(alpha: 0.4)),
                        const SizedBox(width: 4),
                        Text(
                          'Free trial available',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
