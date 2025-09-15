import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PremiumScreen extends StatefulWidget {
  const PremiumScreen({Key? key}) : super(key: key);

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  bool _isPremium = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPremium();
  }

  Future<void> _loadPremium() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isPremium = prefs.getBool('is_premium') ?? false;
      _loading = false;
    });
  }

  Future<void> _activatePremium() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_premium', true);
    setState(() => _isPremium = true);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Premium etkinleştirildi. Keyfini çıkarın!')),
      );
    }
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Premium'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hero bölüm (modern gradient)
            Container(
              // Yüksekliği esnek: büyük yazı boyutlarında taşma olmasın
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
                  // Arka plan dekoru (daha küçük ve daha az bindirme yapacak şekilde konumlandırıldı)
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
                      children: const [
                        Text(
                          'INKSCAPE PREMIUM',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Sınırsızca yarat. Filigransız kaydet.\nAylık sadece 1\$',
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

            // Özellikler
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
                        Expanded(child: Text('Sınırsız dövme denemesi ve kaydetme')),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: const [
                        Icon(Icons.check_circle, color: Colors.greenAccent),
                        SizedBox(width: 10),
                        Expanded(child: Text('Filigran olmadan dışa aktarma')),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: const [
                        Icon(Icons.check_circle, color: Colors.greenAccent),
                        SizedBox(width: 10),
                        Expanded(child: Text('Öncelikli destek ve yeni özellikler')),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Fiyat kutusu + CTA
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
                      children: const [
                        Text(
                          'Aylık',
                          style: TextStyle(fontSize: 16, color: Color(0xFFBDBDBD)),
                        ),
                        Text('\$1',
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SubscribeButton(
                      isPremium: _isPremium,
                      onTap: _activatePremium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Bu ekran demo amaçlıdır. Gerçek sürümde App Store üzerinden abonelik sunulur.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF9E9E9E)),
                      textAlign: TextAlign.center,
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
    Key? key,
    required this.isPremium,
    required this.onTap,
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
              Text('Premium aktif',
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
        label: const Text(
          "Premium'a Geç (1 \$/ay)",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
