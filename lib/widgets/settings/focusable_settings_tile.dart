import 'package:flutter/material.dart';

class FocusableSettingsTile extends StatefulWidget {
  final Widget title;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onPressed;
  final bool autofocus;

  const FocusableSettingsTile({
    Key? key,
    required this.title,
    this.leading,
    this.trailing,
    this.onPressed,
    this.autofocus = false,
  }) : super(key: key);

  @override
  State<FocusableSettingsTile> createState() => _FocusableSettingsTileState();
}

class _FocusableSettingsTileState extends State<FocusableSettingsTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accentColor = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: RepaintBoundary(
        child: Actions(
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onPressed?.call()),
            ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(onInvoke: (_) => widget.onPressed?.call()),
          },
          child: Focus(
            autofocus: widget.autofocus,
            onFocusChange: (hasFocus) => setState(() => _focused = hasFocus),
            child: InkWell(
              onTap: widget.onPressed,
              borderRadius: BorderRadius.circular(12),
              focusColor: Colors.transparent,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                padding: EdgeInsets.symmetric(
                  horizontal: _focused ? 18 : 16,
                  vertical: _focused ? 14 : 12,
                ),
                decoration: BoxDecoration(
                  color: _focused
                      ? accentColor.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _focused ? accentColor : Colors.transparent,
                    width: _focused ? 2.5 : 2,
                  ),
                  boxShadow: _focused
                      ? [
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.3),
                            blurRadius: 12,
                            spreadRadius: 0,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    if (widget.leading != null) ...[
                      IconTheme(
                        data: IconThemeData(
                          color: _focused ? accentColor : Colors.white70,
                        ),
                        child: widget.leading!,
                      ),
                      const SizedBox(width: 16),
                    ],
                    Expanded(
                      child: DefaultTextStyle.merge(
                        style: TextStyle(
                          color: _focused ? Colors.white : Colors.white70,
                          fontWeight: _focused ? FontWeight.w600 : FontWeight.normal,
                        ),
                        child: widget.title,
                      ),
                    ),
                    if (widget.trailing != null) ...[
                      const SizedBox(width: 16),
                      widget.trailing!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
