import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'storage_keys.dart';
import 'services/premium_access.dart';
import 'revenuecat_keys.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  bool _isPremium = false;
  bool _loading = true;
  DateTime? _premiumExpiration;
  String? _priceString;

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

    // Ekranda her zaman sabit 1$ göster.
    price = '1\$';

    // Eski yerel flagleri geriye dönük uyumluluk için güncelleyelim
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(StorageKeys.premiumFlag, hasRcPremium);

    if (!mounted) return;
    setState(() {
      _isPremium = hasRcPremium;
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

    final tsf = MediaQuery.of(context).textScaler.scale(1.0);
    final double heroMinHeight = 220 + (40 * (tsf - 1.0)).clamp(0, 80);
    // Premium için modern minimal palet
    const bgDark = Color(0xFF0B0F14);
    const cardStroke = Color(0x14FFFFFF);
    const textMuted = Color(0xFF9CA3AF);
    final formattedExpiry = _formatExpiration(_premiumExpiration);
    // RC ile süreyi biz tutmuyoruz

    return Scaffold(
      backgroundColor: bgDark,
      appBar: AppBar(
        backgroundColor: bgDark,
        elevation: 0,
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
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF12151B), Color(0xFF0E1116)],
                ),
                border: Border.all(color: cardStroke),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x33000000),
                    blurRadius: 20,
                    offset: Offset(0, 12),
                  ),
                ],
              ),
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text(
                          'INKSCAPE PREMIUM',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.0,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Create without limits. Save without watermarks.\nOnly ${_priceString ?? '1\$'}/month',
                          textAlign: TextAlign.left,
                          maxLines: 3,
                          softWrap: true,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            height: 1.25,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Card(
              color: const Color(0x0DFFFFFF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: cardStroke),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: const [
                        Icon(Icons.check_circle, color: Color(0xFF10B981)),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Unlimited tattoo trials and saves',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: const [
                        Icon(Icons.check_circle, color: Color(0xFF10B981)),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Export without watermarks',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: const [
                        Icon(Icons.check_circle, color: Color(0xFF10B981)),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Realistic background-free tattoo collection',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: const [
                        Icon(Icons.check_circle, color: Color(0xFF10B981)),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Priority support and new features',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            Card(
              color: const Color(0x0DFFFFFF),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: cardStroke),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Monthly',
                          style: TextStyle(fontSize: 16, color: textMuted),
                        ),
                        Text(
                          _priceString ?? '1\$',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Cancel anytime. One tap to manage in your store account.',
                      style: TextStyle(fontSize: 12, color: textMuted),
                    ),
                    const SizedBox(height: 12),
                    _SubscribeButton(
                      isPremium: _isPremium,
                      onTap: _activatePremium,
                    ),
                    if (_isPremium && formattedExpiry != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Your Premium membership is active until $formattedExpiry.',
                        style: const TextStyle(fontSize: 14, color: textMuted),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TextButton.icon(
                          onPressed: () async {
                            final (ok, msg) = await PremiumAccess.instance.restorePurchases();
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(ok ? 'Satın alımlar geri yüklendi' : (msg ?? 'Geri yükleme başarısız'))),
                            );
                            if (ok) setState(() => _isPremium = true);
                          },
                          icon: const Icon(Icons.restore_outlined),
                          label: const Text('Restore Purchases'),
                          style: TextButton.styleFrom(foregroundColor: Colors.white),
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

  const _SubscribeButton({
    required this.isPremium,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (isPremium) {
      return Container(
        height: 54,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: const Color(0xFF10B981),
        ),
        child: const Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified, color: Colors.white),
              SizedBox(width: 8),
              Text(
                'Premium active',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 54,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: const Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_rate_rounded, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Go Premium',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
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
