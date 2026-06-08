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
