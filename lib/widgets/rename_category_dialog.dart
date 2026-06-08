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

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flauncher/generated/locale_keys.g.dart';

class AddCategoryDialog extends StatelessWidget {
  final String initialValue;

  AddCategoryDialog({
    required this.initialValue,
  });

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      insetPadding: EdgeInsets.only(bottom: 120),
      contentPadding: EdgeInsets.all(24),
      title: Text(LocaleKeys.renameCategory.tr()),
      children: [
        TextFormField(
          autofocus: true,
          initialValue: initialValue,
          decoration: InputDecoration(labelText: LocaleKeys.name.tr()),
          validator: (value) =>
              value!.trim().isEmpty ? LocaleKeys.mustNotBeEmpty.tr() : null,
          autovalidateMode: AutovalidateMode.always,
          keyboardType: TextInputType.text,
          textCapitalization: TextCapitalization.sentences,
          onFieldSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              Navigator.of(context).pop(value);
            }
          },
        )
      ],
    );
  }
}
