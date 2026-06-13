import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flauncher/generated/locale_keys.g.dart';

Future<void> showUpdateProgressDialog(
  BuildContext context, {
  required String label,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => AlertDialog(
      content: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(label)),
        ],
      ),
    ),
  );
}

Future<void> showNoUpdateDialog(
  BuildContext context, {
  required String currentVersion,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(LocaleKeys.updateNoUpdateTitle.tr()),
      content: Text(LocaleKeys.updateNoUpdateBody.tr(args: [currentVersion])),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(MaterialLocalizations.of(dialogContext).okButtonLabel),
        ),
      ],
    ),
  );
}

Future<bool> showUpdateAvailableDialog(
  BuildContext context, {
  required String latestVersion,
  required String currentVersion,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(LocaleKeys.updateAvailableTitle.tr()),
          content: Text(LocaleKeys.updateAvailableBody
              .tr(args: [latestVersion, currentVersion])),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                  MaterialLocalizations.of(dialogContext).cancelButtonLabel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(LocaleKeys.updateDownloadButton.tr()),
            ),
          ],
        ),
      ) ??
      false;
}

Future<bool> showReadyToInstallDialog(
  BuildContext context, {
  required String latestVersion,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(LocaleKeys.updateReadyToInstallTitle.tr()),
          content: Text(
              LocaleKeys.updateReadyToInstallBody.tr(args: [latestVersion])),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                  MaterialLocalizations.of(dialogContext).cancelButtonLabel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(LocaleKeys.updateInstallButton.tr()),
            ),
          ],
        ),
      ) ??
      false;
}

Future<void> showInstallPermissionDialog(
  BuildContext context, {
  required VoidCallback onOpenPermissionSettings,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(LocaleKeys.updateInstallPermissionTitle.tr()),
      content: Text(LocaleKeys.updateInstallPermissionBody.tr()),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child:
              Text(MaterialLocalizations.of(dialogContext).cancelButtonLabel),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            onOpenPermissionSettings();
          },
          child: Text(LocaleKeys.updateOpenPermissionSettingsButton.tr()),
        ),
      ],
    ),
  );
}
