// Copyright (C) 2026 akshaynexus / Akshay CM
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flauncher/providers/purchases_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Shared premium / Pro UI.
///
/// This is the single source of truth for the paywall, the reverse-trial
/// offer, the purchase-error dialog and the focusable dialog buttons. Both the
/// wallpaper panel ("Aerial Views" gate) and the settings panel ("Unlock Pro")
/// drive the exact same components from here so the two entry points can never
/// drift apart.

const Color _kSurface = Color(0xFF1E1E1E);
const double _kDialogRadius = 24;

/// Visual style for [FocusableDialogButton].
enum DialogButtonStyle { filled, outlined, text }

/// Loads offerings (showing a spinner while the network call is in flight) and
/// then presents the paywall. Handles the empty / unavailable state gracefully.
///
/// This is the only entry point for the upgrade flow — call it from anywhere a
/// non-Pro user attempts a gated action.
Future<void> showPremiumPaywall(BuildContext context) async {
  final purchasesService = context.read<PurchasesService>();
  final accentColor = Theme.of(context).colorScheme.primary;
  final rootNavigator = Navigator.of(context, rootNavigator: true);

  // Show a lightweight loading dialog so the remote press feels acknowledged
  // on slow TV networks while offerings are fetched.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => Center(
      child: CircularProgressIndicator(color: accentColor),
    ),
  );

  await purchasesService.loadOfferings();
  if (!context.mounted) return;
  rootNavigator.pop(); // dismiss the loader

  final options = purchasesService.purchaseOptions;
  if (!context.mounted) return;

  if (options.isEmpty) {
    await _showPlansUnavailableDialog(context, accentColor);
    return;
  }

  showDialog<void>(
    context: context,
    builder: (dialogContext) => PremiumDialog(
      accentColor: accentColor,
      options: options,
      onReverseTrial: purchasesService.trialOption != null
          ? () {
              Navigator.of(dialogContext).pop();
              showReverseTrialOffer(context, purchasesService, accentColor);
            }
          : null,
      onPurchase: (option) async {
        // Don't pop before the purchase resolves: a user who cancels the native
        // sheet should land back on the paywall, not silently in settings.
        final result = await purchasesService.purchase(option.identifier);
        if (!context.mounted) return;
        switch (result) {
          case PurchaseResult.success:
            Navigator.of(dialogContext).pop();
            _showWelcomeSnackBar(context, option.hasFreeTrial);
          case PurchaseResult.cancelled:
            break; // stay on the paywall
          case PurchaseResult.error:
            await showPurchaseErrorDialog(context);
        }
      },
    ),
  );
}

/// Reverse-trial retention offer shown when a user declines the paywall.
Future<void> showReverseTrialOffer(BuildContext context,
    PurchasesService purchasesService, Color accentColor) async {
  final trialOption = purchasesService.trialOption;
  if (trialOption == null) return;
  final duration = trialOption.trialDuration;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: _kSurface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_kDialogRadius)),
      contentPadding: EdgeInsets.zero,
      content: ClipRRect(
        borderRadius: BorderRadius.circular(_kDialogRadius),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _GradientHeader(
              accentColor: accentColor,
              icon: Icons.card_giftcard,
              title: 'Enjoy Pro Free',
              subtitle:
                  'Try all premium features free for\n${duration ?? 'a limited time'}.\nNo commitment, cancel anytime.',
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Column(
                children: [
                  FocusableDialogButton(
                    label: 'Start ${duration ?? 'Free Trial'}',
                    accentColor: accentColor,
                    style: DialogButtonStyle.filled,
                    autofocus: true,
                    onPressed: () => Navigator.of(ctx).pop(true),
                  ),
                  const SizedBox(height: 8),
                  FocusableDialogButton(
                    label: 'No thanks',
                    accentColor: accentColor,
                    onPressed: () => Navigator.of(ctx).pop(false),
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
        _showWelcomeSnackBar(context, true);
      case PurchaseResult.cancelled:
        break;
      case PurchaseResult.error:
        await showPurchaseErrorDialog(context);
    }
  }
}

/// Shared purchase-failure dialog with a focusable, auto-focused dismiss.
Future<void> showPurchaseErrorDialog(BuildContext context) {
  final accentColor = Theme.of(context).colorScheme.primary;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: _kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Purchase Failed'),
      content: const Text(
          'There was an error processing your purchase. Please try again later.'),
      actions: [
        FocusableDialogButton(
          label: 'OK',
          accentColor: accentColor,
          autofocus: true,
          expand: false,
          onPressed: () => Navigator.of(ctx).pop(),
        ),
      ],
    ),
  );
}

Future<void> _showPlansUnavailableDialog(
    BuildContext context, Color accentColor) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: _kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('Plans unavailable'),
      content: const Text(
          'Subscription plans are temporarily unavailable. Please check your connection and try again.'),
      actions: [
        FocusableDialogButton(
          label: 'Close',
          accentColor: accentColor,
          expand: false,
          onPressed: () => Navigator.of(ctx).pop(),
        ),
        FocusableDialogButton(
          label: 'Try Again',
          accentColor: accentColor,
          style: DialogButtonStyle.filled,
          autofocus: true,
          expand: false,
          onPressed: () {
            Navigator.of(ctx).pop();
            showPremiumPaywall(context);
          },
        ),
      ],
    ),
  );
}

void _showWelcomeSnackBar(BuildContext context, bool hasFreeTrial) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(hasFreeTrial
          ? 'Welcome to Pro! Enjoy your free trial.'
          : 'Welcome to Pro!'),
      backgroundColor: Colors.green,
    ),
  );
}

/// The paywall. Presentational only — purchase / dismiss logic is injected.
class PremiumDialog extends StatelessWidget {
  final Color accentColor;
  final List<PurchaseOption> options;
  final void Function(PurchaseOption) onPurchase;
  final void Function()? onReverseTrial;

  const PremiumDialog({
    super.key,
    required this.accentColor,
    required this.options,
    required this.onPurchase,
    this.onReverseTrial,
  });

  bool get _anyHasTrial => options.any((o) => o.hasFreeTrial);

  String? get _trialDuration =>
      options.where((o) => o.hasFreeTrial).firstOrNull?.trialDuration;

  /// Computes "Save N%" for an annual plan vs. 12x the monthly plan, using the
  /// numeric [PurchaseOption.priceAmount] (locale-safe). Empty when there is no
  /// monthly plan to compare against or the annual plan isn't actually cheaper.
  String _savingsLabel(PurchaseOption annual) {
    final monthly = options.where((o) => o.period == 'month').firstOrNull;
    if (monthly == null) return '';
    final yearlyCost = monthly.priceAmount * 12;
    if (yearlyCost <= 0) return '';
    final savings = ((yearlyCost - annual.priceAmount) / yearlyCost * 100).round();
    if (savings <= 0) return '';
    return 'Save $savings%';
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    return AlertDialog(
      backgroundColor: _kSurface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_kDialogRadius)),
      contentPadding: EdgeInsets.zero,
      content: ClipRRect(
        borderRadius: BorderRadius.circular(_kDialogRadius),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _GradientHeader(
                  accentColor: accentColor,
                  icon: Icons.auto_awesome,
                  title: _anyHasTrial ? 'Try Pro Free' : 'Upgrade to Pro',
                  subtitle: _anyHasTrial
                      ? 'Enjoy full access for ${_trialDuration ?? 'a limited time'}.\nCancel anytime.'
                      : 'Unlock stunning aerial video wallpapers\nfrom around the world.',
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Column(
                          children: [
                            _ProFeatureRow('Multiple quality options'),
                            _ProFeatureRow('Smart shuffle & filters'),
                            _ProFeatureRow('Time, scene & city filters'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SectionLabel(
                        _anyHasTrial
                            ? 'Start your ${_trialDuration ?? ''} free trial'.trim()
                            : 'Choose your plan',
                      ),
                      const SizedBox(height: 12),
                      ...options.asMap().entries.map((e) {
                        final savings = e.value.period == 'year'
                            ? _savingsLabel(e.value)
                            : '';
                        return _PlanTile(
                          option: e.value,
                          accentColor: accentColor,
                          onTap: () => onPurchase(e.value),
                          autofocus: e.key == 0,
                          isLast: e.key == options.length - 1,
                          savingsLabel: savings.isEmpty ? null : savings,
                        );
                      }),
                      const SizedBox(height: 12),
                      // Honest dismiss. The reverse-trial offer (if any) is a
                      // separate, clearly-labelled choice rather than hiding
                      // behind "Maybe later".
                      if (onReverseTrial != null) ...[
                        Center(
                          child: FocusableDialogButton(
                            label: 'See free trial offer',
                            accentColor: accentColor,
                            expand: false,
                            onPressed: onReverseTrial!,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Center(
                        child: _SecondaryTextButton(
                          label: _anyHasTrial ? 'Maybe later' : 'Not now',
                          onTap: () => Navigator.of(context).pop(),
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
}

/// Shared gradient header used by every premium dialog.
class _GradientHeader extends StatelessWidget {
  final Color accentColor;
  final IconData icon;
  final String title;
  final String subtitle;

  const _GradientHeader({
    required this.accentColor,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withValues(alpha: 0.4),
            accentColor.withValues(alpha: 0.08),
            _kSurface,
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [accentColor, accentColor.withValues(alpha: 0.6)],
              ),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.4),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
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

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(height: 1, color: Colors.white12, width: 24),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white38,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 1, color: Colors.white12)),
      ],
    );
  }
}

class _ProFeatureRow extends StatelessWidget {
  final String text;

  const _ProFeatureRow(this.text);

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(Icons.check_circle, size: 18, color: accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: Colors.white, fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

/// Purchase option card. Doubles as the buy button: when focused it reveals a
/// filled accent CTA with a verb so the buy action reads unambiguously at 10ft.
class _PlanTile extends StatefulWidget {
  final PurchaseOption option;
  final Color accentColor;
  final VoidCallback onTap;
  final bool autofocus;
  final bool isLast;
  final String? savingsLabel;

  const _PlanTile({
    required this.option,
    required this.accentColor,
    required this.onTap,
    required this.autofocus,
    required this.isLast,
    this.savingsLabel,
  });

  @override
  State<_PlanTile> createState() => _PlanTileState();
}

class _PlanTileState extends State<_PlanTile> {
  bool _focused = false;

  // Emphasis is earned by proven savings, not merely by being the annual plan.
  bool get _isBestValue =>
      widget.savingsLabel != null && widget.savingsLabel!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final option = widget.option;
    final accent = widget.accentColor;

    return Padding(
      padding: EdgeInsets.only(bottom: widget.isLast ? 0 : 8),
      child: Actions(
        actions: {
          ActivateIntent:
              CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onTap()),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
              onInvoke: (_) => widget.onTap()),
        },
        child: Focus(
          autofocus: widget.autofocus,
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
                  color: _focused
                      ? accent
                      : Colors.white.withValues(alpha: 0.08),
                  width: _focused ? 2.5 : 1.0,
                ),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: _focused
                      ? [
                          accent.withValues(alpha: 0.15),
                          accent.withValues(alpha: 0.08),
                        ]
                      : [
                          accent.withValues(alpha: 0.06),
                          accent.withValues(alpha: 0.03),
                        ],
                ),
                boxShadow: _focused
                    ? [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.3),
                          blurRadius: 12,
                        ),
                      ]
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isBestValue) ...[
                    _BestValueBadge(accent: accent),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              option.title,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              option.description,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withValues(alpha: 0.5),
                              ),
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
                              color: accent,
                            ),
                          ),
                          if (option.period.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '/ ${option.period}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: accent.withValues(alpha: 0.7),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  if (widget.savingsLabel != null ||
                      option.hasFreeTrial) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (widget.savingsLabel != null)
                          _AccentChip(
                            accent: accent,
                            icon: Icons.savings_outlined,
                            label: widget.savingsLabel!,
                          ),
                        if (option.hasFreeTrial)
                          _AccentChip(
                            accent: accent,
                            icon: Icons.card_giftcard,
                            label: option.trialDuration != null
                                ? 'Free for ${option.trialDuration}'
                                : 'Free trial included',
                          ),
                      ],
                    ),
                  ],
                  // Dominant CTA appears on focus so the buy action is obvious.
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 150),
                    crossFadeState: _focused
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    firstChild: const SizedBox(width: double.infinity),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            option.hasFreeTrial
                                ? 'Start free trial'
                                : 'Subscribe',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
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

class _BestValueBadge extends StatelessWidget {
  final Color accent;

  const _BestValueBadge({required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star, size: 12, color: Colors.white),
          SizedBox(width: 4),
          Text('Best value',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
        ],
      ),
    );
  }
}

class _AccentChip extends StatelessWidget {
  final Color accent;
  final IconData icon;
  final String label;

  const _AccentChip({
    required this.accent,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: accent.withValues(alpha: 0.15),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: accent),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// A focusable, accent-styled button following the project's TV focus pattern
/// (border + glow). Used for primary/secondary actions across premium dialogs.
class FocusableDialogButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;
  final Color accentColor;
  final IconData? icon;
  final DialogButtonStyle style;
  final bool autofocus;

  /// When true (default) the button stretches to full width — appropriate for
  /// stacked dialog actions. Set false for inline / AlertDialog action rows.
  final bool expand;

  const FocusableDialogButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.accentColor,
    this.icon,
    this.style = DialogButtonStyle.text,
    this.autofocus = false,
    this.expand = true,
  });

  @override
  State<FocusableDialogButton> createState() => _FocusableDialogButtonState();
}

class _FocusableDialogButtonState extends State<FocusableDialogButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor;
    final filled = widget.style == DialogButtonStyle.filled;
    final outlined = widget.style == DialogButtonStyle.outlined;

    final Color background = filled
        ? accent
        : (_focused ? accent.withValues(alpha: 0.12) : Colors.transparent);
    final Color borderColor = filled
        ? accent
        : (_focused
            ? accent
            : (outlined ? accent.withValues(alpha: 0.5) : Colors.white12));
    final double borderWidth = _focused ? 2.5 : (outlined ? 1.5 : 1.0);
    final Color foreground = filled
        ? Colors.white
        : (_focused ? Colors.white : (outlined ? accent : Colors.white70));

    return Actions(
      actions: {
        ActivateIntent:
            CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onPressed()),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
            onInvoke: (_) => widget.onPressed()),
      },
      child: Focus(
        autofocus: widget.autofocus,
        onFocusChange: (hasFocus) => setState(() => _focused = hasFocus),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            width: widget.expand ? double.infinity : null,
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: borderColor, width: borderWidth),
              boxShadow: (_focused && !filled)
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.3),
                        blurRadius: 12,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 18, color: foreground),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Demoted text button for the inert "Maybe later" / "Not now" dismiss so it
/// never competes visually with the accent-bordered plan tiles.
class _SecondaryTextButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _SecondaryTextButton({required this.label, required this.onTap});

  @override
  State<_SecondaryTextButton> createState() => _SecondaryTextButtonState();
}

class _SecondaryTextButtonState extends State<_SecondaryTextButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _focused ? Colors.white24 : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                color: _focused ? Colors.white70 : Colors.white38,
                fontSize: 14,
                decoration:
                    _focused ? TextDecoration.underline : TextDecoration.none,
                decorationColor: Colors.white70,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
