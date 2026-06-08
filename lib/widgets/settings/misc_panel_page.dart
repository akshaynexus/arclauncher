import 'package:flauncher/providers/settings_service.dart';
import 'package:flauncher/widgets/rounded_switch_list_tile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flauncher/generated/locale_keys.g.dart';

class MiscPanelPage extends StatelessWidget {
  static const String routeName = "misc_panel";

  const MiscPanelPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    SettingsService settingsService = Provider.of(context);

    return Column(
      children: [
        Text("Miscellaneous", style: Theme.of(context).textTheme.titleLarge),
        const Divider(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              RoundedSwitchListTile(
                autofocus: true,
                value: settingsService.appHighlightAnimationEnabled,
                onChanged: (value) =>
                    settingsService.setAppHighlightAnimationEnabled(value),
                title: Text(LocaleKeys.appCardHighlightAnimation.tr(),
                    style: Theme.of(context).textTheme.bodyMedium),
                secondary: Icon(Icons.filter_center_focus),
              ),
              RoundedSwitchListTile(
                value: settingsService.appKeyClickEnabled,
                onChanged: (value) =>
                    settingsService.setAppKeyClickEnabled(value),
                title: Text(LocaleKeys.appKeyClick.tr(),
                    style: Theme.of(context).textTheme.bodyMedium),
                secondary: Icon(Icons.notifications_active),
              ),
              RoundedSwitchListTile(
                value: settingsService.showCategoryTitles,
                onChanged: (value) =>
                    settingsService.setShowCategoryTitles(value),
                title: Text(LocaleKeys.showCategoryTitles.tr(),
                    style: Theme.of(context).textTheme.bodyMedium),
                secondary: Icon(Icons.abc),
              ),
              RoundedSwitchListTile(
                value: settingsService.showAppNamesBelowIcons,
                onChanged: (value) =>
                    settingsService.setShowAppNamesBelowIcons(value),
                title: Text("Show App Names Below Icons",
                    style: Theme.of(context).textTheme.bodyMedium),
                secondary: Icon(Icons.subtitles),
              ),
              RoundedSwitchListTile(
                value: settingsService.dockBackdropFilterDisabled,
                onChanged: (value) =>
                    settingsService.setDockBackdropFilterDisabled(value),
                title: Text("Disable Dock Backdrop Blur",
                    style: Theme.of(context).textTheme.bodyMedium),
                secondary: Icon(Icons.blur_off),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
