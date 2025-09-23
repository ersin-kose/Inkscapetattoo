import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'storage_keys.dart';
import 'services/premium_access.dart';
import 'revenuecat_keys.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({Key? key}) : super(key: key);

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  bool _isPremium = false;
  bool _loading = true;
  DateTime? _premiumExpiration;
  String? _priceString;
  Package? _monthlyPackage;

  @override
  void initState() {
    super.initState();
    _loadPremium();
  }

  Future<void> _loadPremium() async {
    // RevenueCat üzerinden güncel durumu oku
    final hasRcPremium = await PremiumAccess.instance.refreshEntitlementActive();

    // Fiyat bilgisini oku
    final pkg = await PremiumAccess.instance.getMonthlyPackage();
    String? price = pkg?.storeProduct.priceString;
    // RC offerings boş ise doğrudan ürün kimliğinden fiyat çekmeyi dene
    if (price == null && rcMonthlyProductId.isNotEmpty && !rcMonthlyProductId.startsWith('REPLACE')) {
      try {
        final prods = await Purchases.getProducts([rcMonthlyProductId]);
        if (prods.isNotEmpty) {
          price = prods.first.priceString;
        }
      } catch (_) {}
    }

    // Eski yerel flagleri geriye dönük uyumluluk için güncelleyelim
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageKeys.premiumFlag, hasRcPremium);

    if (!mounted) return;
    setState(() {
      _isPremium = hasRcPremium;
      _monthlyPackage = pkg;
      _priceString = price;
      _loading = false;
    });
  }

  Future<void> _activatePremium() async {
    final (ok, msg) = await PremiumAccess.instance.purchaseMonthly();
    if (!mounted) return;
    if (ok) {
      // Kullanım sayacını sıfırlayalım
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(StorageKeys.tattooUsageCount, 0);
      setState(() {
        _isPremium = true;
        _premiumExpiration = null; // RC yönetiyor
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Premium aktif! Keyfini çıkarın.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg ?? 'Satın alma başarısız')),
      );
    }
  }

  String? _formatExpiration(DateTime? expiry) {
    if (expiry == null) return null;
    final day = expiry.day.toString().padLeft(2, '0');
    final month = expiry.month.toString().padLeft(2, '0');
    return '$day.$month.${expiry.year}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final tsf = MediaQuery.of(context).textScaleFactor;
    final double heroMinHeight = 200 + (40 * (tsf - 1.0)).clamp(0, 80);
    final formattedExpiry = _formatExpiration(_premiumExpiration);
    final bool hasExpiredPremium = false; // RC ile süreyi biz tutmuyoruz

    return Scaffold(
      appBar: AppBar(
        title: const Text('Premium'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              constraints: BoxConstraints(minHeight: heroMinHeight),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFFC857), // amber-gold
                    Color(0xFFFF8C42), // orange
                  ],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: -10,
                    top: -10,
                    child: Icon(
                      Icons.stars_rounded,
                      size: 120,
                      color: Colors.white.withOpacity(0.12),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'INKSCAPE PREMIUM',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Create without limits. Save without watermarks.\nOnly ${_priceString ?? '\$1'}/month',
                          textAlign: TextAlign.left,
                          maxLines: 3,
                          softWrap: true,
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 22,
                            height: 1.25,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Card(
              color: colorScheme.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.check_circle, color: Colors.greenAccent),
                        SizedBox(width: 10),
                        Expanded(child: Text('Unlimited tattoo trials and saves')),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: const [
                        Icon(Icons.check_circle, color: Colors.greenAccent),
                        SizedBox(width: 10),
                        Expanded(child: Text('Export without watermarks')),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: const [
                        Icon(Icons.check_circle, color: Colors.greenAccent),
                        SizedBox(width: 10),
                        Expanded(child: Text('Realistic background-free tattoo collection')),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: const [
                        Icon(Icons.check_circle, color: Colors.greenAccent),
                        SizedBox(width: 10),
                        Expanded(child: Text('Priority support and new features')),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            Card(
              color: colorScheme.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Monthly',
                          style: TextStyle(fontSize: 16, color: Color(0xFFBDBDBD)),
                        ),
                        Text(
                          _priceString ?? '\$1',
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SubscribeButton(
                      isPremium: _isPremium,
                      onTap: _activatePremium,
                      priceText: _priceString,
                    ),
                    if (_isPremium && formattedExpiry != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Your Premium membership is active until $formattedExpiry.',
                        style: const TextStyle(fontSize: 14, color: Colors.white),
                        textAlign: TextAlign.center,
                      ),
                    ] else if (hasExpiredPremium && formattedExpiry != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Your Premium subscription ended on $formattedExpiry.',
                        style: const TextStyle(fontSize: 14, color: Color(0xFFBDBDBD)),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Subscribe again to regain unlimited access.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton(
                          onPressed: () async {
                            final (ok, msg) = await PremiumAccess.instance.restorePurchases();
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(ok ? 'Satın alımlar geri yüklendi' : (msg ?? 'Geri yükleme başarısız'))),
                            );
                            if (ok) setState(() => _isPremium = true);
                          },
                          child: const Text('Restore Purchases'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubscribeButton extends StatelessWidget {
  final bool isPremium;
  final VoidCallback onTap;
  final String? priceText;

  const _SubscribeButton({
    Key? key,
    required this.isPremium,
    required this.onTap,
    this.priceText,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isPremium) {
      return Container(
        height: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.green[700],
        ),
        child: const Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified, color: Colors.white),
              SizedBox(width: 8),
              Text('Premium active',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 54,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.star_rate_rounded),
        label: Text(
          'Go Premium (${priceText ?? '\$1'}/mo)',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFFFA000), // amber tone
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
        ),
      ),
    );
  }
}
