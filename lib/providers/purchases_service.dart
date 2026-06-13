// Copyright (C) 2026 akshaynexus / Akshay CM
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

enum PurchaseResult { success, cancelled, error }

/// Simple data class representing a purchase option for the UI.
class PurchaseOption {
  final String identifier;
  final String title;
  final String description;
  final String priceString;
  final String period;

  const PurchaseOption({
    required this.identifier,
    required this.title,
    required this.description,
    required this.priceString,
    required this.period,
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
      await Purchases.setLogLevel(LogLevel.debug);

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
            period = 'forever';
            break;
          default:
            period = '';
        }
        return PurchaseOption(
          identifier: package.identifier,
          title: product.title,
          description: product.description,
          priceString: product.priceString,
          period: period,
        );
      }).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading offerings: $e');
      _purchaseOptions = [];
      notifyListeners();
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

      final result = await Purchases.purchasePackage(package);
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
