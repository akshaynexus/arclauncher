// Copyright (C) 2026 akshaynexus / Akshay CM
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

enum PurchaseResult { success, cancelled, error }

class PurchaseOption {
  final String identifier;
  final String title;
  final String description;
  final String priceString;

  /// Numeric price in the store currency, used for locale-safe savings math.
  /// Parsing the localized [priceString] is unreliable across currencies, so
  /// we carry the raw amount from the store product instead.
  final double priceAmount;
  final String period;
  final bool hasFreeTrial;
  final String? trialDuration;

  const PurchaseOption({
    required this.identifier,
    required this.title,
    required this.description,
    required this.priceString,
    required this.priceAmount,
    required this.period,
    this.hasFreeTrial = false,
    this.trialDuration,
  });
}

class PurchasesService extends ChangeNotifier {
  // TODO: Replace with production key before release
  static const _apiKeyAndroid = 'test_BOgRCbumeHtqEAvpzSPEukDYZtC';

  CustomerInfo? _customerInfo;
  bool _isPro = false;
  bool _initialized = false;
  List<PurchaseOption> _purchaseOptions = [];

  CustomerInfo? get customerInfo => _customerInfo;
  bool get isPro => _isPro;
  bool get initialized => _initialized;
  List<PurchaseOption> get purchaseOptions => _purchaseOptions;

  Future<void> initialize(String? appUserId) async {
    try {
      if (kDebugMode) {
        await Purchases.setLogLevel(LogLevel.debug);
      }

      PurchasesConfiguration config;
      config = PurchasesConfiguration(_apiKeyAndroid);

      if (appUserId != null) {
        config = config..appUserID = appUserId;
      }

      await Purchases.configure(config);
      _customerInfo = await Purchases.getCustomerInfo();
      _isPro = _hasProEntitlement(_customerInfo!);
      _initialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error initializing RevenueCat: $e');
      _initialized = true;
      notifyListeners();
    }
  }

  bool _hasProEntitlement(CustomerInfo customerInfo) {
    return customerInfo.entitlements.active.isNotEmpty;
  }

  Future<bool> restorePurchases() async {
    try {
      final customerInfo = await Purchases.restorePurchases();
      _customerInfo = customerInfo;
      _isPro = _hasProEntitlement(customerInfo);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error restoring purchases: $e');
      return false;
    }
  }

  Future<void> loadOfferings() async {
    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      if (current == null) {
        _purchaseOptions = [];
        notifyListeners();
        return;
      }

      _purchaseOptions = current.availablePackages.map((package) {
        final product = package.storeProduct;
        String period;
        switch (package.packageType) {
          case PackageType.annual:
            period = 'year';
            break;
          case PackageType.monthly:
            period = 'month';
            break;
          case PackageType.weekly:
            period = 'week';
            break;
          case PackageType.lifetime:
            // Lifetime has no recurring cadence; leave the period empty so the
            // UI doesn't render a nonsensical "/ forever" suffix.
            period = '';
            break;
          default:
            period = '';
        }
        final intro = product.introductoryPrice;
        return PurchaseOption(
          identifier: package.identifier,
          title: product.title,
          description: product.description,
          priceString: product.priceString,
          priceAmount: product.price,
          period: period,
          hasFreeTrial: intro != null && intro.price == '0.00',
          trialDuration: intro != null && intro.price == '0.00'
              ? '${intro.periodNumberOfUnits} ${intro.periodUnit.name}'
              : null,
        );
      }).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading offerings: $e');
      _purchaseOptions = [];
      notifyListeners();
    }
  }

  EntitlementInfo? get activeEntitlement {
    if (_customerInfo == null) return null;
    return _customerInfo!.entitlements.active.values.isNotEmpty
        ? _customerInfo!.entitlements.active.values.first
        : null;
  }

  bool get isTrialActive {
    final entitlement = activeEntitlement;
    if (entitlement == null) return false;
    return entitlement.periodType == PeriodType.trial;
  }

  int get trialDaysRemaining {
    final entitlement = activeEntitlement;
    if (entitlement == null || !isTrialActive) return 0;
    final expStr = entitlement.expirationDate;
    if (expStr == null) return 0;
    final exp = DateTime.tryParse(expStr);
    if (exp == null) return 0;
    // Round UP remaining time: inDays truncates, so a trial with <24h left
    // would otherwise read "0 days remaining" (looks expired) on its last day.
    final secs = exp.difference(DateTime.now()).inSeconds;
    return secs <= 0 ? 0 : (secs / 86400).ceil().clamp(0, 365);
  }

  DateTime? get trialEndDate {
    final entitlement = activeEntitlement;
    if (entitlement == null || !isTrialActive) return null;
    final expStr = entitlement.expirationDate;
    if (expStr == null) return null;
    return DateTime.tryParse(expStr);
  }

  String? get trialEndDateFormatted {
    final date = trialEndDate;
    if (date == null) return null;
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  String? get activePlanTitle {
    final entitlement = activeEntitlement;
    if (entitlement == null) return null;
    final productId = entitlement.productIdentifier;
    final matches = _purchaseOptions.where((o) => o.identifier == productId);
    return matches.isNotEmpty ? matches.first.title : productId;
  }

  String? get activePeriod {
    final id = activeEntitlement?.productIdentifier;
    if (id == null) return null;
    final matches = _purchaseOptions.where((o) => o.identifier == id);
    return matches.isNotEmpty ? matches.first.period : null;
  }

  bool get isLifetime {
    final entitlement = activeEntitlement;
    if (entitlement == null) return false;
    return entitlement.expirationDate == null;
  }

  PurchaseOption? get trialOption =>
      _purchaseOptions.cast<PurchaseOption?>().firstWhere(
            (o) => o!.hasFreeTrial,
            orElse: () => null,
          );

  String? get managementUrl => _customerInfo?.managementURL;

  Future<bool> manageSubscription() async {
    final url = _customerInfo?.managementURL;
    if (url == null) return false;
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error opening management URL: $e');
      return false;
    }
  }

  Future<PurchaseResult> purchase(String identifier) async {
    try {
      final offerings = await Purchases.getOfferings();
      final current = offerings.current;
      if (current == null) return PurchaseResult.error;

      final package = current.availablePackages.firstWhere(
        (p) => p.identifier == identifier,
        orElse: () => throw Exception('Package not found'),
      );

      final result = await Purchases.purchase(PurchaseParams.package(package));
      _customerInfo = result.customerInfo;
      _isPro = _hasProEntitlement(result.customerInfo);
      notifyListeners();
      return PurchaseResult.success;
    } on PlatformException catch (e) {
      final code = PurchasesErrorHelper.getErrorCode(e);
      if (code == PurchasesErrorCode.purchaseCancelledError) {
        debugPrint('Purchase cancelled by user');
        return PurchaseResult.cancelled;
      }
      debugPrint('Error purchasing: $e');
      return PurchaseResult.error;
    } catch (e) {
      debugPrint('Error purchasing: $e');
      return PurchaseResult.error;
    }
  }
}
