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
            if (purchasesService.isPro) {
              return FocusableSettingsTile(
                leading: const Icon(Icons.workspace_premium),
                title: Text('Manage Subscription',
                    style: Theme.of(context).textTheme.bodyMedium),
                onPressed: () => _showSubscriptionDialog(context),
              );
            }
            return FocusableSettingsTile(
              leading: const Icon(Icons.workspace_premium),
              title: Text('Unlock Pro',
                  style: Theme.of(context).textTheme.bodyMedium),
              onPressed: () => _showUpgradeDialog(context),
            );
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
                                fontSize: 16, fontWeight: FontWeight.bold),
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
    final result = await purchasesService.purchase(trialOption.identifier);
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
              content:
                  const Text('There was an error processing your purchase.'),
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

Future<void> _showUpgradeDialog(BuildContext context) async {
  final purchasesService = context.read<PurchasesService>();
  final accentColor = Theme.of(context).colorScheme.primary;

  await purchasesService.loadOfferings();
  if (!context.mounted) return;
  final options = purchasesService.purchaseOptions;

  if (!context.mounted) return;
  showDialog(
    context: context,
    builder: (dialogContext) => _SettingsPremiumDialog(
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
                content:
                    const Text('There was an error processing your purchase.'),
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

class _SubscriptionDialog extends StatelessWidget {
  final Color accentColor;
  final PurchasesService purchasesService;

  const _SubscriptionDialog({
    required this.accentColor,
    required this.purchasesService,
  });

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
                    _infoRow('Plan', plan),
                    const SizedBox(height: 12),
                    if (isTrial) ...[
                      _infoRow('Status',
                          'Trial — $trialDays day${trialDays == 1 ? '' : 's'} remaining'),
                      const SizedBox(height: 12),
                      if (trialEnd != null) ...[
                        _infoRow('Trial ends', trialEnd),
                        const SizedBox(height: 12),
                      ],
                    ],
                    _infoRow('Status', isTrial ? 'Active (Trial)' : 'Active'),
                    if (period != null && !isTrial) ...[
                      const SizedBox(height: 12),
                      _infoRow('Period', period),
                    ],
                    if (expiry != null && !isTrial) ...[
                      const SizedBox(height: 12),
                      _infoRow('Expires', _formatDate(expiry)),
                    ],
                    if (isLifetime) ...[
                      const SizedBox(height: 12),
                      _infoRow('Type', 'Lifetime'),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: Actions(
                        actions: {
                          ActivateIntent: CallbackAction<ActivateIntent>(
                              onInvoke: (_) => _manage(context)),
                          ButtonActivateIntent:
                              CallbackAction<ButtonActivateIntent>(
                                  onInvoke: (_) => _manage(context)),
                        },
                        child: Focus(
                          child: OutlinedButton.icon(
                            onPressed: () => _manage(context),
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Manage Subscription'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: accentColor,
                              side: BorderSide(color: accentColor),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: Actions(
                        actions: {
                          ActivateIntent: CallbackAction<ActivateIntent>(
                              onInvoke: (_) => _restore(context)),
                          ButtonActivateIntent:
                              CallbackAction<ButtonActivateIntent>(
                                  onInvoke: (_) => _restore(context)),
                        },
                        child: Focus(
                          child: TextButton.icon(
                            onPressed: () => _restore(context),
                            icon: const Icon(Icons.restore),
                            label: const Text('Restore Purchases'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white70,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (kDebugMode) ...[
                      const SizedBox(height: 16),
                      const Divider(color: Colors.white12),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: Actions(
                          actions: {
                            ActivateIntent: CallbackAction<ActivateIntent>(
                                onInvoke: (_) => _previewUpgrade(context)),
                            ButtonActivateIntent:
                                CallbackAction<ButtonActivateIntent>(
                                    onInvoke: (_) => _previewUpgrade(context)),
                          },
                          child: Focus(
                            child: TextButton.icon(
                              onPressed: () => _previewUpgrade(context),
                              icon: const Icon(Icons.bug_report, size: 18),
                              label:
                                  const Text('Preview Upgrade Flow (Debug)'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.orange,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (mgmtUrl != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Or visit:\n$mgmtUrl',
                        style: TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
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
    final isTrial = purchasesService.isTrialActive;
    final trialDays = purchasesService.trialDaysRemaining;
    final trialEndFormatted = purchasesService.trialEndDateFormatted;

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
            child: Icon(isTrial ? Icons.free_breakfast : Icons.workspace_premium,
                color: Colors.white, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            isTrial ? 'Free Trial' : 'Pro Subscription',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isTrial
                ? '$trialDays day${trialDays == 1 ? '' : 's'} remaining.\n${trialEndFormatted != null ? "Ends $trialEndFormatted" : ''}'
                : 'Manage your subscription and\nrestore previous purchases.',
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

class _SettingsPremiumDialog extends StatelessWidget {
  final Color accentColor;
  final List<PurchaseOption> options;
  final void Function(PurchaseOption) onPurchase;
  final void Function()? onReverseTrial;

  const _SettingsPremiumDialog({
    required this.accentColor,
    required this.options,
    required this.onPurchase,
    this.onReverseTrial,
  });

  bool get _anyHasTrial => options.any((o) => o.hasFreeTrial);
  String? get _trialDuration =>
      options.firstWhere((o) => o.hasFreeTrial, orElse: () => options.first).trialDuration;
  bool get _hasMonthly => options.any((o) => o.period == 'month');

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
                          _settingsProFeatureRow('Apple TV aerial videos'),
                          _settingsProFeatureRow('Multiple quality options'),
                          _settingsProFeatureRow('Smart shuffle & filters'),
                          _settingsProFeatureRow('Time, scene & city filters'),
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
                    ...options.asMap().entries.map((e) => _SettingsOptionTile(
                          option: e.value,
                          accentColor: accentColor,
                          onTap: () => onPurchase(e.value),
                          index: e.key,
                          total: options.length,
                          savingsLabel:
                              e.value.period == 'year' && _hasMonthly ? _savingsPercent(e.value) : null,
                        )),
                    const SizedBox(height: 12),
                    Center(
                      child: _SettingsDialogTextButton(
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

  Widget _settingsProFeatureRow(String text) {
    final accent = accentColor;
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

class _SettingsDialogTextButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _SettingsDialogTextButton({
    required this.label,
    required this.onTap,
  });

  @override
  State<_SettingsDialogTextButton> createState() =>
      _SettingsDialogTextButtonState();
}

class _SettingsDialogTextButtonState extends State<_SettingsDialogTextButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Actions(
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

class _SettingsOptionTile extends StatefulWidget {
  final PurchaseOption option;
  final Color accentColor;
  final VoidCallback onTap;
  final int index;
  final int total;
  final String? savingsLabel;

  const _SettingsOptionTile({
    required this.option,
    required this.accentColor,
    required this.onTap,
    required this.index,
    required this.total,
    this.savingsLabel,
  });

  @override
  State<_SettingsOptionTile> createState() => _SettingsOptionTileState();
}

class _SettingsOptionTileState extends State<_SettingsOptionTile> {
  bool _focused = false;

  bool get _isBestValue => widget.option.period == 'year';

  @override
  Widget build(BuildContext context) {
    final option = widget.option;
    final accent = widget.accentColor;

    return Padding(
      padding: EdgeInsets.only(
        bottom: widget.index < widget.total - 1 ? 12 : 0,
      ),
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
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _focused ? Colors.white : accent.withValues(alpha: 0.3),
                  width: _focused ? 2.0 : 1.0,
                ),
                color: _focused
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.03),
                boxShadow: _focused
                    ? [
                        BoxShadow(
                          color: Colors.white.withValues(alpha: 0.08),
                          blurRadius: 16,
                          spreadRadius: 0,
                        ),
                      ]
                    : null,
              ),
              child: Stack(
                children: [
                  if (_isBestValue)
                    Positioned(
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFFFFD700),
                              const Color(0xFFFFA500),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome,
                                size: 12, color: Colors.black87),
                            const SizedBox(width: 4),
                            const Text('Best value',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87)),
                          ],
                        ),
                      ),
                    ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
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
                                    color: _focused ? Colors.white : null,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  option.description.contains('/')
                                      ? option.description.split('/').first.trim()
                                      : option.description,
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                option.priceString,
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: _focused ? accent : Colors.white70,
                                ),
                              ),
                              if (option.period.isNotEmpty)
                                Text(
                                  '/${option.period}',
                                  style: const TextStyle(
                                      color: Colors.white38, fontSize: 12),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
