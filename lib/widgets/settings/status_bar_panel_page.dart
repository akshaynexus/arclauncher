/*
 * FLauncher
 * Copyright (C) 2024 Oscar Rojas
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

import 'package:flauncher/widgets/rounded_switch_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flauncher/generated/locale_keys.g.dart';

import '../../providers/settings_service.dart';

class StatusBarPanelPage extends StatelessWidget {
  static const String routeName = "status_bar_panel";

  @override
  Widget build(BuildContext context) {
    final settingsService = Provider.of<SettingsService>(context, listen: false);

    return Column(
      children: [
        Text(LocaleKeys.statusBar.tr(),
            style: Theme.of(context).textTheme.titleLarge),
        const Divider(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              Selector<SettingsService, bool>(
                selector: (_, s) => s.autoHideAppBarEnabled,
                builder: (context, autoHide, _) => RoundedSwitchListTile(
                  autofocus: true,
                  value: autoHide,
                  onChanged: (value) =>
                      settingsService.setAutoHideAppBarEnabled(value),
                  title: Text(LocaleKeys.autoHideAppBar.tr(),
                      style: Theme.of(context).textTheme.bodyMedium),
                  secondary: const Icon(Icons.visibility_off_outlined),
                ),
              ),
              const Divider(),
              Selector<SettingsService, bool>(
                selector: (_, s) => s.showDateInStatusBar,
                builder: (context, showDate, _) => RoundedSwitchListTile(
                  value: showDate,
                  onChanged: (value) =>
                      settingsService.setShowDateInStatusBar(value),
                  title: Text(LocaleKeys.date.tr()),
                  secondary: const Icon(Icons.calendar_today_outlined),
                ),
              ),
              Selector<SettingsService, bool>(
                selector: (_, s) => s.showTimeInStatusBar,
                builder: (context, showTime, _) => RoundedSwitchListTile(
                  value: showTime,
                  onChanged: (value) =>
                      settingsService.setShowTimeInStatusBar(value),
                  title: Text(LocaleKeys.time.tr()),
                  secondary: const Icon(Icons.watch_later_outlined),
                ),
              ),
              Selector<SettingsService, bool>(
                selector: (_, s) => s.showWifiWidgetInStatusBar,
                builder: (context, showWifi, _) => RoundedSwitchListTile(
                  value: showWifi,
                  onChanged: (value) =>
                      settingsService.setShowWifiWidgetInStatusBar(value),
                  title: const Text('WiFi Usage'),
                  secondary: const Icon(Icons.wifi),
                ),
              ),
              Selector<SettingsService, bool>(
                selector: (_, s) => s.showNetworkIndicatorInStatusBar,
                builder: (context, showNetwork, _) => RoundedSwitchListTile(
                  value: showNetwork,
                  onChanged: (value) =>
                      settingsService.setShowNetworkIndicatorInStatusBar(value),
                  title: const Text('Network Indicator'),
                  secondary: const Icon(Icons.signal_wifi_4_bar),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
