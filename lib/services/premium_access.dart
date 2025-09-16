import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../revenuecat_keys.dart';

class PremiumAccess {
  PremiumAccess._();
  static final PremiumAccess instance = PremiumAccess._();

  bool _initialized = false;
  bool _enabled = false;
  bool _isPremium = false;
  Offerings? _offeringsCache;
  Package? _monthlyPackage;

  final ValueNotifier<bool> isPremiumNotifier = ValueNotifier(false);

  Future<void> init() async {
    if (_initialized) return;
    final String? apiKey = Platform.isIOS
        ? rcApiKeyIos
        : Platform.isAndroid
            ? rcApiKeyAndroid
            : null;

    if (apiKey == null || apiKey.startsWith('REPLACE_')) {
      // Anahtar yoksa yine de uygulama çalışsın; sadece premium false kalır.
      debugPrint('[PremiumAccess] RevenueCat API key missing or placeholder.');
      _initialized = true;
      _enabled = false;
      return;
    }

    // Geliştirme sırasında detaylı log alalım (sadece debug'da).
    await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.warn);
    final config = PurchasesConfiguration(apiKey);
    await Purchases.configure(config);

    Purchases.addCustomerInfoUpdateListener((customerInfo) {
      final active = customerInfo.entitlements.active.containsKey(rcEntitlementId);
      _setPremium(active);
    });

    // İlk durumu çek
    await refreshEntitlementActive();
    // Teklifleri önceden al (bekletmeden başlat)
    _preloadOfferings();

    _initialized = true;
    _enabled = true;
  }

  bool get isPremium => _isPremium;

  Future<bool> refreshEntitlementActive() async {
    try {
      final info = await Purchases.getCustomerInfo();
      final active = info.entitlements.active.containsKey(rcEntitlementId);
      _setPremium(active);
      return active;
    } catch (e) {
      debugPrint('[PremiumAccess] getCustomerInfo error: $e');
      return _isPremium;
    }
  }

  void _setPremium(bool value) {
    if (_isPremium != value) {
      _isPremium = value;
      isPremiumNotifier.value = value;
    }
  }

  Future<void> _preloadOfferings() async {
    try {
      _offeringsCache = await Purchases.getOfferings();
      _monthlyPackage = _findMonthlyPackage(_offeringsCache);
    } catch (e) {
      debugPrint('[PremiumAccess] preload offerings error: $e');
    }
  }

  Package? _findMonthlyPackage(Offerings? offerings) {
    if (offerings == null) return null;

    // Eğer belirli bir ürün kimliği verildiyse, tüm paketlerde ara
    if (rcMonthlyProductId.isNotEmpty &&
        !rcMonthlyProductId.startsWith('REPLACE')) {
      for (final off in offerings.all.values) {
        for (final p in off.availablePackages) {
          final id = p.storeProduct.identifier;
          if (id == rcMonthlyProductId) {
            return p;
          }
        }
      }
    }

    // Aksi halde current offering içinde monthly tipe bak
    final off = offerings.current ?? offerings.all.values.firstOrNull;
    if (off == null) return null;
    for (final p in off.availablePackages) {
      if (p.packageType == PackageType.monthly ||
          p.identifier.toLowerCase().contains('month')) {
        return p;
      }
    }
    // Bulunamazsa ilk paket
    return off.availablePackages.firstOrNull;
  }

  Future<Package?> getMonthlyPackage({bool refresh = false}) async {
    if (!refresh && _monthlyPackage != null) return _monthlyPackage;
    try {
      _offeringsCache = await Purchases.getOfferings();
      _monthlyPackage = _findMonthlyPackage(_offeringsCache);
      return _monthlyPackage;
    } catch (e) {
      debugPrint('[PremiumAccess] getMonthlyPackage error: $e');
      // StoreKit Test kullanımı için doğrudan ürün kimliğiyle düşelim.
      try {
        if (rcMonthlyProductId.isNotEmpty && !rcMonthlyProductId.startsWith('REPLACE')) {
          final prods = await Purchases.getProducts([rcMonthlyProductId]);
          if (prods.isNotEmpty) {
            debugPrint('[PremiumAccess] Fallback store product bulundu: '
                '${prods.first.identifier} price=${prods.first.priceString}');
          }
        }
      } catch (_) {}
      return null;
    }
  }

  Future<(bool success, String? message)> purchaseMonthly() async {
    try {
      if (!_enabled) {
        return (false, 'RevenueCat anahtarları ayarlı değil');
      }
      final pkg = await getMonthlyPackage(refresh: true);
      if (pkg == null) {
        // Teklif yoksa doğrudan StoreProduct üzerinden satın almayı dene
        if (rcMonthlyProductId.isEmpty || rcMonthlyProductId.startsWith('REPLACE')) {
          return (false, 'Ürün kimliği tanımlı değil');
        }
        final prods = await Purchases.getProducts([rcMonthlyProductId]);
        if (prods.isEmpty) {
          return (false, 'Ürün bulunamadı (StoreKit config kontrol edin)');
        }
        final result = await Purchases.purchaseStoreProduct(prods.first);
        final info = result.customerInfo;
        final active = info.entitlements.active.containsKey(rcEntitlementId);
        _setPremium(active);
        return (active, active ? null : 'Abonelik etkinleşmedi');
      } else {
        final result = await Purchases.purchasePackage(pkg);
        final info = result.customerInfo;
        final active = info.entitlements.active.containsKey(rcEntitlementId);
        _setPremium(active);
        return (active, active ? null : 'Abonelik etkinleşmedi');
      }
    } on PurchasesErrorCode catch (code) {
      return (false, code.name);
    } catch (e) {
      return (false, e.toString());
    }
  }

  Future<(bool success, String? message)> restorePurchases() async {
    try {
      if (!_enabled) {
        return (false, 'RevenueCat anahtarları ayarlı değil');
      }
      final info = await Purchases.restorePurchases();
      final active = info.entitlements.active.containsKey(rcEntitlementId);
      _setPremium(active);
      return (active, active ? null : 'Aktif abonelik bulunamadı');
    } catch (e) {
      return (false, e.toString());
    }
  }
}

extension _FirstOrNull<K, V> on Iterable<V> {
  V? get firstOrNull => isEmpty ? null : first;
}
