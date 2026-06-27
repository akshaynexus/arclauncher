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

import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/providers/purchases_service.dart';
import 'package:flauncher/providers/update_service.dart';
import 'package:flauncher/widgets/settings/applications_panel_page.dart';
import 'package:flauncher/widgets/settings/flauncher_about_dialog.dart';
import 'package:flauncher/widgets/settings/interface_settings_page.dart';
import 'package:flauncher/widgets/settings/premium_dialog.dart';
import 'package:flauncher/widgets/settings/update_dialogs.dart';
import 'package:flauncher/widgets/settings/general_settings_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flauncher/generated/locale_keys.g.dart';

import 'focusable_settings_tile.dart';

class SettingsPanelPage extends StatelessWidget {
  static const String routeName = "settings_panel";

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(LocaleKeys.settings.tr(),
          style: Theme.of(context).textTheme.titleLarge),
      const Divider(),
      Expanded(
          child: SingleChildScrollView(
              child: Column(children: [
        FocusableSettingsTile(
          autofocus: true,
          leading: const Icon(Icons.apps),
          title: Text(LocaleKeys.applications.tr(),
              style: Theme.of(context).textTheme.bodyMedium),
          onPressed: () =>
              Navigator.of(context).pushNamed(ApplicationsPanelPage.routeName),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.auto_awesome_mosaic_outlined),
          title:
              Text('Interface', style: Theme.of(context).textTheme.bodyMedium),
          onPressed: () =>
              Navigator.of(context).pushNamed(InterfaceSettingsPage.routeName),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.settings_suggest_outlined),
          title: Text('System', style: Theme.of(context).textTheme.bodyMedium),
          onPressed: () =>
              Navigator.of(context).pushNamed(GeneralSettingsPage.routeName),
        ),
        const Divider(),
        FocusableSettingsTile(
          leading: const Icon(Icons.settings_outlined),
          title: Text(LocaleKeys.systemSettings.tr(),
              style: Theme.of(context).textTheme.bodyMedium),
          onPressed: () => context.read<AppsService>().openSettings(),
        ),
        FocusableSettingsTile(
          leading: const Icon(Icons.system_update_alt),
          title: Text(LocaleKeys.updateCheck.tr(),
              style: Theme.of(context).textTheme.bodyMedium),
          onPressed: () => _checkForUpdates(context),
        ),
        Consumer<PurchasesService>(
          builder: (context, purchasesService, _) {
            // Everything is free for now, so there's nothing to upsell — hide
            // the "Unlock Pro" entry until premium-only features ship. Existing
            // subscribers keep "Manage Subscription" so they can restore/cancel.
            if (purchasesService.isPro) {
              return FocusableSettingsTile(
                leading: const Icon(Icons.workspace_premium),
                title: Text('Manage Subscription',
                    style: Theme.of(context).textTheme.bodyMedium),
                onPressed: () => _showSubscriptionDialog(context),
              );
            }
            return const SizedBox.shrink();
          },
        ),
        FocusableSettingsTile(
            leading: const Icon(Icons.info_outline),
            title: Text(LocaleKeys.aboutFlauncher.tr(),
                style: Theme.of(context).textTheme.bodyMedium),
            onPressed: () => showDialog(
                context: context,
                builder: (_) => FutureBuilder<PackageInfo>(
                      future: PackageInfo.fromPlatform(),
                      builder: (context, snapshot) => snapshot
                                      .connectionState ==
                                  ConnectionState.done &&
                              snapshot.hasData
                          ? LTvLauncherAboutDialog(packageInfo: snapshot.data!)
                          : Container(),
                    )))
      ])))
    ]);
  }
}

Future<void> _checkForUpdates(BuildContext context) async {
  final updateService = UpdateService();
  final navigator = Navigator.of(context, rootNavigator: true);

  showUpdateProgressDialog(
    context,
    label: LocaleKeys.updateCheck.tr(),
  );

  try {
    final update = await updateService.checkForUpdate();
    if (navigator.canPop()) {
      navigator.pop();
    }
    if (!context.mounted) {
      return;
    }

    if (!update.updateAvailable) {
      await showNoUpdateDialog(
        context,
        currentVersion: update.currentVersion,
      );
      return;
    }

    final download = await showUpdateAvailableDialog(
      context,
      latestVersion: update.latestVersion,
      currentVersion: update.currentVersion,
    );

    if (!download) {
      return;
    }

    showUpdateProgressDialog(
      context,
      label: LocaleKeys.updateDownloadButton.tr(),
    );

    final downloadedApk = await updateService.downloadApk(update);
    if (navigator.canPop()) {
      navigator.pop();
    }
    if (!context.mounted) {
      return;
    }

    final install = await showReadyToInstallDialog(
      context,
      latestVersion: downloadedApk.version,
    );

    if (!install) {
      return;
    }

    final installerOpened = await updateService.installApk(downloadedApk.path);
    if (!context.mounted || installerOpened) {
      return;
    }

    await showInstallPermissionDialog(
      context,
      onOpenPermissionSettings: () =>
          updateService.requestInstallUnknownAppsPermission(),
    );
  } catch (_) {
    if (navigator.canPop()) {
      navigator.pop();
    }
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(LocaleKeys.updateErrorGeneric.tr())),
    );
  }
}

Future<void> _showSubscriptionDialog(BuildContext context) async {
  final purchasesService = context.read<PurchasesService>();
  final accentColor = Theme.of(context).colorScheme.primary;
  showDialog(
    context: context,
    builder: (ctx) => _SubscriptionDialog(
      accentColor: accentColor,
      purchasesService: purchasesService,
    ),
  );
}

/// Upgrade entry point for the "Unlock Pro" tile — delegates to the single
/// shared paywall so this flow can never diverge from the wallpaper-panel gate.
Future<void> _showUpgradeDialog(BuildContext context) => showPremiumPaywall(context);

class _SubscriptionDialog extends StatefulWidget {
  final Color accentColor;
  final PurchasesService purchasesService;

  const _SubscriptionDialog({
    required this.accentColor,
    required this.purchasesService,
  });

  @override
  State<_SubscriptionDialog> createState() => _SubscriptionDialogState();
}

class _SubscriptionDialogState extends State<_SubscriptionDialog> {
  Color get accentColor => widget.accentColor;
  PurchasesService get purchasesService => widget.purchasesService;

  @override
  Widget build(BuildContext context) {
    final plan = purchasesService.activePlanTitle ?? 'Pro';
    final isLifetime = purchasesService.isLifetime;
    final period = purchasesService.activePeriod;
    final mgmtUrl = purchasesService.managementUrl;
    final expiryStr = purchasesService.activeEntitlement?.expirationDate;
    final expiry = expiryStr != null ? DateTime.tryParse(expiryStr) : null;
    final isTrial = purchasesService.isTrialActive;
    final trialDays = purchasesService.trialDaysRemaining;
    final trialEnd = purchasesService.trialEndDateFormatted;
    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      contentPadding: EdgeInsets.zero,
      content: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(context),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _infoRow('Plan', plan),
                      const SizedBox(height: 12),
                      // Single, non-redundant status line.
                      if (isTrial) ...[
                        _infoRow('Status',
                            'Trial — $trialDays day${trialDays == 1 ? '' : 's'} remaining'),
                        if (trialEnd != null) ...[
                          const SizedBox(height: 12),
                          _infoRow('Trial ends', trialEnd),
                        ],
                      ] else ...[
                        _infoRow('Status', 'Active'),
                        if (period != null) ...[
                          const SizedBox(height: 12),
                          _infoRow('Period', period),
                        ],
                        if (expiry != null) ...[
                          const SizedBox(height: 12),
                          _infoRow('Expires', _formatDate(expiry)),
                        ],
                      ],
                      if (isLifetime) ...[
                        const SizedBox(height: 12),
                        _infoRow('Type', 'Lifetime'),
                      ],
                      const SizedBox(height: 24),
                      FocusableDialogButton(
                        label: 'Manage Subscription',
                        icon: Icons.open_in_new,
                        accentColor: accentColor,
                        style: DialogButtonStyle.outlined,
                        autofocus: true,
                        onPressed: () => _manage(context),
                      ),
                      const SizedBox(height: 8),
                      FocusableDialogButton(
                        label: 'Restore Purchases',
                        icon: Icons.restore,
                        accentColor: accentColor,
                        onPressed: () => _restore(context),
                      ),
                      if (kDebugMode) ...[
                        const SizedBox(height: 16),
                        const Divider(color: Colors.white12),
                        const SizedBox(height: 8),
                        FocusableDialogButton(
                          label: 'Preview Upgrade Flow (Debug)',
                          icon: Icons.bug_report,
                          accentColor: accentColor,
                          onPressed: () => _previewUpgrade(context),
                        ),
                      ],
                      if (mgmtUrl != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          'Or visit:\n$mgmtUrl',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Center(
                        child: FocusableDialogButton(
                          label: 'Close',
                          accentColor: accentColor,
                          expand: false,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final isTrial = purchasesService.isTrialActive;
    final trialDays = purchasesService.trialDaysRemaining;
    final trialEndFormatted = purchasesService.trialEndDateFormatted;
    final String subtitle;
    if (isTrial) {
      final remaining =
          '$trialDays day${trialDays == 1 ? '' : 's'} remaining.';
      subtitle = trialEndFormatted != null
          ? '$remaining\nEnds $trialEndFormatted'
          : remaining;
    } else {
      subtitle = 'Manage your subscription and\nrestore previous purchases.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
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
            width: 44,
            height: 44,
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
            child: Icon(isTrial ? Icons.free_breakfast : Icons.workspace_premium,
                color: Colors.white, size: 20),
          ),
          const SizedBox(height: 10),
          Text(
            isTrial ? 'Free Trial' : 'Pro Subscription',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.6),
              height: 1.4,
            ),
          ),
          if (isTrial) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$trialDays day${trialDays == 1 ? '' : 's'} left',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: accentColor,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 14)),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Future<void> _manage(BuildContext context) async {
    final opened = await purchasesService.manageSubscription();
    if (context.mounted && !opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open subscription manager')),
      );
    }
  }

  Future<void> _restore(BuildContext context) async {
    final success = await purchasesService.restorePurchases();
    if (!mounted) return;
    // Refresh the dialog so Plan / Status / Trial reflect the restored state
    // instead of the snapshot captured when the dialog opened.
    setState(() {});
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? 'Purchases restored successfully'
              : 'Failed to restore purchases'),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  void _previewUpgrade(BuildContext context) {
    Navigator.of(context).pop();
    _showUpgradeDialog(context);
  }
}

