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

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'animated_character.dart';

class DateTimeWidget extends StatefulWidget {
  final Duration?   updateInterval;
  final String      _dateTimeFormatString;
  final TextStyle?  textStyle;
  final bool        animate;

  const DateTimeWidget(String dateTimeFormatString, {
    super.key,
    this.updateInterval,
    this.textStyle,
    this.animate = false,
  }) :
      _dateTimeFormatString = dateTimeFormatString;

  @override
  State<DateTimeWidget> createState() => _DateTimeWidgetState();
}

class _DateTimeWidgetState extends State<DateTimeWidget> {
  late DateFormat _dateFormat;
  late DateTime   _now;
  late Timer      _timer;
  late String     _formattedText;

  @override
  void initState() {
    super.initState();

    _dateFormat = DateFormat(widget._dateTimeFormatString, Platform.localeName);
    _now = DateTime.now();
    _formattedText = _dateFormat.format(_now);
    _timer = Timer.periodic(widget.updateInterval ?? _defaultInterval(), (_) => _refreshTime());
  }

  /// Returns 1-second interval if format contains seconds, otherwise 1-minute.
  Duration _defaultInterval() {
    final fmt = widget._dateTimeFormatString;
    return (fmt.contains('s') || fmt.contains('S'))
        ? const Duration(seconds: 1)
        : const Duration(minutes: 1);
  }

  @override
  void didUpdateWidget(DateTimeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    final formatChanged = oldWidget._dateTimeFormatString != widget._dateTimeFormatString;
    final intervalChanged = oldWidget.updateInterval != widget.updateInterval;

    if (formatChanged) {
      _dateFormat = DateFormat(widget._dateTimeFormatString, Platform.localeName);
    }

    if (formatChanged || intervalChanged) {
      _timer.cancel();
      _timer = Timer.periodic(widget.updateInterval ?? _defaultInterval(), (_) => _refreshTime());
      
      final now = DateTime.now();
      final newFormattedText = _dateFormat.format(now);
      if (newFormattedText != _formattedText) {
        setState(() {
          _now = now;
          _formattedText = newFormattedText;
        });
      }
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.animate) {
      return AnimatedTimeDisplay(
        displayText: _formattedText,
        textStyle: widget.textStyle,
      );
    }
    
    return Text(_formattedText, style: widget.textStyle);
  }

  void _refreshTime() {
    final now = DateTime.now();
    final newFormattedText = _dateFormat.format(now);
    if (newFormattedText != _formattedText) {
      setState(() {
        _now = now;
        _formattedText = newFormattedText;
      });
    }
  }
}
