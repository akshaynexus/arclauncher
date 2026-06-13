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
      onPurchase: (option) async {
        Navigator.of(dialogContext).pop();
        final result = await purchasesService.purchase(option.identifier);
        if (!context.mounted) return;
        switch (result) {
          case PurchaseResult.success:
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Welcome to Pro!'),
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

    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.workspace_premium, color: accentColor, size: 28),
          const SizedBox(width: 12),
          const Text('Subscription', style: TextStyle(fontSize: 18)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow('Plan', plan),
          const SizedBox(height: 8),
          _infoRow('Status', 'Active'),
          if (period != null) ...[
            const SizedBox(height: 8),
            _infoRow('Period', period),
          ],
          if (expiry != null) ...[
            const SizedBox(height: 8),
            _infoRow('Expires', _formatDate(expiry)),
          ],
          if (isLifetime) ...[
            const SizedBox(height: 8),
            _infoRow('Type', 'Lifetime'),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: Actions(
              actions: {
                ActivateIntent: CallbackAction<ActivateIntent>(
                    onInvoke: (_) => _manage(context)),
                ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
                    onInvoke: (_) => _manage(context)),
              },
              child: Focus(
                child: FilledButton.icon(
                  onPressed: () => _manage(context),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Manage Subscription'),
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
                ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
                    onInvoke: (_) => _restore(context)),
              },
              child: Focus(
                child: OutlinedButton.icon(
                  onPressed: () => _restore(context),
                  icon: const Icon(Icons.restore),
                  label: const Text('Restore Purchases'),
                ),
              ),
            ),
          ),
          if (mgmtUrl != null) ...[
            const SizedBox(height: 12),
            Text(
              'Or visit:\n$mgmtUrl',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54)),
        Text(value, style: const TextStyle(color: Colors.white)),
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
}

class _SettingsPremiumDialog extends StatelessWidget {
  final Color accentColor;
  final List<PurchaseOption> options;
  final void Function(PurchaseOption) onPurchase;

  const _SettingsPremiumDialog({
    required this.accentColor,
    required this.options,
    required this.onPurchase,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.lock, size: 28),
          SizedBox(width: 12),
          Text('Unlock Pro', style: TextStyle(fontSize: 18)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Get access to stunning aerial video wallpapers and more.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            const Text('Choose your plan',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                )),
            const SizedBox(height: 12),
            ...options.map((option) => _SettingsOptionTile(
                  option: option,
                  accentColor: accentColor,
                  onTap: () => onPurchase(option),
                )),
            const SizedBox(height: 8),
            Center(
              child: _SettingsDialogTextButton(
                label: 'Maybe Later',
                onTap: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
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

  const _SettingsOptionTile({
    required this.option,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_SettingsOptionTile> createState() => _SettingsOptionTileState();
}

class _SettingsOptionTileState extends State<_SettingsOptionTile> {
  bool _focused = false;

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
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _focused ? accent : accent.withValues(alpha: 0.3),
                  width: _focused ? 2.5 : 2.0,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _focused
                      ? [
                          accent.withValues(alpha: 0.2),
                          accent.withValues(alpha: 0.1),
                        ]
                      : [
                          accent.withValues(alpha: 0.1),
                          accent.withValues(alpha: 0.05),
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
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        option.title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _focused ? Colors.white : null,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          option.description.contains('/')
                              ? option.description.split('/').last.trim()
                              : option.description,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    option.description,
                    style: const TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${option.priceString}${option.period.isNotEmpty ? ' / ${option.period}' : ''}',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: accent,
                    ),
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
