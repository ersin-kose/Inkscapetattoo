import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'storage_keys.dart';
import 'services/premium_access.dart';
import 'revenuecat_keys.dart';
import 'brand_theme.dart';

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
    final formattedExpiry = _formatExpiration(_premiumExpiration);
    final bool hasExpiredPremium = false; // RC ile süreyi biz tutmuyoruz

    return Scaffold(
      appBar: AppBar(
        title: const Text('Premium'),
        centerTitle: true,
      ),
      bottomNavigationBar: !_isPremium
          ? _PurchaseBar(
              price: _priceString,
              onTap: _activatePremium,
            )
          : null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PremiumHero(price: _priceString),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
                color: colorScheme.surface.withOpacity(0.6),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.30),
                    blurRadius: 16,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _FeatureItem(
                      icon: Icons.auto_awesome,
                      text: 'Sınırsız deneme, sınırsız kayıt',
                    ),
                    const SizedBox(height: 10),
                    const _FeatureItem(
                      icon: Icons.water_drop_outlined,
                      text: 'Filigransız yüksek çözünürlüklü dışa aktarma',
                    ),
                    const SizedBox(height: 10),
                    const _FeatureItem(
                      icon: Icons.rocket_launch_outlined,
                      text: 'Öncelikli destek ve yeni özellikler',
                    ),

                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_circle_outline, size: 16, color: Color(0xFF9E9E9E)),
                        const SizedBox(width: 6),
                        Text(
                          'Otomatik yenilenir, istediğin zaman iptal',
                          style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.75)),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withOpacity(0.07)),
                          ),
                          child: const Text(
                            'Aylık',
                            style: TextStyle(fontSize: 13, color: Color(0xFFBDBDBD)),
                          ),
                        ),
                        Text(
                          _priceString ?? '\$1',
                          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),

                    // CTA sadeleştirildi: yalnızca alttaki sabit satın alma butonu

                    if (_isPremium && formattedExpiry != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Premium $formattedExpiry tarihine kadar aktif',
                        style: const TextStyle(fontSize: 13, color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    ] else if (hasExpiredPremium && formattedExpiry != null) ...[
                      const SizedBox(height: 12),
                      const Text(
                        'Premium aboneliğin sona erdi.',
                        style: TextStyle(fontSize: 14, color: Color(0xFFBDBDBD)),
                        textAlign: TextAlign.center,
                      ),
                    ],

                    const SizedBox(height: 8),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.lock_outline, size: 16, color: Color(0xFF9E9E9E)),
                        SizedBox(width: 6),
                        Text(
                          'Ödemeler mağaza üzerinden güvende',
                          style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            Center(
              child: TextButton.icon(
                onPressed: () async {
                  final (ok, msg) = await PremiumAccess.instance.restorePurchases();
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ok ? 'Satın alımlar geri yüklendi' : (msg ?? 'Geri yükleme başarısız'))),
                  );
                  if (ok) setState(() => _isPremium = true);
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white70,
                ),
                icon: const Icon(Icons.restore),
                label: const Text('Satın Alımları Geri Yükle'),
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

// --- UI PARTIALS ---

class _PremiumHero extends StatelessWidget {
  final String? price;
  const _PremiumHero({required this.price});

  @override
  Widget build(BuildContext context) {
    final tsf = MediaQuery.of(context).textScaleFactor;
    final double heroMinHeight = 220 + (36 * (tsf - 1.0)).clamp(0, 72);

    return Container(
      constraints: BoxConstraints(minHeight: heroMinHeight),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            BrandTheme.premiumStart,
            BrandTheme.premiumEnd,
          ],
        ),
      ),
      child: Stack(
        children: [
          // Minimal hero: no decorative icons
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Premium’a Geç',
                  style: TextStyle(
                    color: BrandTheme.onPremium,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Sınırsız tasarım, filigransız kayıt',
                  style: TextStyle(
                    color: BrandTheme.onPremium,
                    fontSize: 26,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Filigransız kayıt. Aylık ${price ?? '\$1'}',
                  style: const TextStyle(
                    color: BrandTheme.onPremium,
                    fontSize: 15,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String text;
  const _FeatureItem({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Icon(icon, size: 16, color: BrandTheme.accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 15, height: 1.2),
          ),
        ),
      ],
    );
  }
}

class _PurchaseBar extends StatelessWidget {
  final String? price;
  final VoidCallback onTap;

  const _PurchaseBar({required this.price, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          border: const Border(top: BorderSide(color: Color(0x1FFFFFFF))),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 20,
              offset: const Offset(0, -8),
            )
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: Colors.white.withOpacity(0.06),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_month, size: 16, color: Color(0xFFBDBDBD)),
                  const SizedBox(width: 6),
                  Text(
                    'Aylık ${price ?? '\$1'}',
                    style: const TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: onTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: BrandTheme.cta,
                    foregroundColor: BrandTheme.onCta,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 8,
                    shadowColor: BrandTheme.cta.withOpacity(0.45),
                  ),
                  child: const Text(
                    "Premium'a Geç",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
