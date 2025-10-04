import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:media_store_plus/media_store_plus.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:async';

import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'profile_screen.dart';
import 'premium_screen.dart';
import 'storage_keys.dart';
import 'services/premium_access.dart';
import 'pinterest_browser.dart';

// Silgi path'i ve boyutunu saklayan sınıf
class EraserPath {
  final Path path;
  final double strokeWidth;

  EraserPath({required this.path, required this.strokeWidth});
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Web'de satın alma/premium başlatma atlanır.
  if (!kIsWeb) {
    await PremiumAccess.instance.init();
  }
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isLoggedIn = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final currentUserEmail = prefs.getString('current_user_email');
    setState(() {
      _isLoggedIn = currentUserEmail != null;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return ScreenUtilInit(
        designSize: const Size(375, 812),
        minTextAdapt: true,
        splitScreenMode: true,
        builder: (context, child) {
          return const MaterialApp(
            home: Scaffold(
              body: Center(child: CircularProgressIndicator()),
            ),
          );
        },
      );
    }

    return ScreenUtilInit(
      designSize: const Size(375, 812),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp(
          title: 'Inkscape',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.dark(
              primary: Colors.grey[800]!,
              secondary: Colors.grey[600]!,
              surface: Colors.grey[900]!,
              background: Colors.black,
            ),
            scaffoldBackgroundColor: Colors.black,
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.black,
              elevation: 0,
            ),
          ),
          home: _isLoggedIn ? const ProfileScreen() : const MainScreen(),
        );
      },
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // --- Capture için RepaintBoundary key'i ---
  final GlobalKey _captureKey = GlobalKey();

  File? _selectedImage; // Arka plan fotoğrafı
  File? _selectedTattooImage; // Overlay (işlenecek)
  Uint8List? _tattooImageBytes; // Önceden yüklenmiş dövme görseli
  final ImagePicker _picker = ImagePicker();
  bool _isLoggedIn = false;
  static const int _freeTattooUsageLimit = 5;
  int _tattooUsageCount = 0;
  bool _isPremiumUser = false;
  DateTime? _premiumExpiration;

  // Dövme için transform değerleri
  double _tattooScale = 1.0;
  Offset _tattooPosition = Offset.zero;
  double _tattooRotation = 0.0; // Döndürme açısı (radyan)

  // Ölçeklendirme başlangıç değeri
  double _initialScale = 1.0;
  double _initialRotation = 0.0; // Döndürme başlangıç değeri

  // Silgi için path listeleri (UNDO/REDO destekli)
  List<EraserPath> _eraserPaths = [];
  List<EraserPath> _undoStack = []; // UNDO ile geri alınanlar (REDO için)
  Path? _currentPath;
  bool _isErasing = false;
  bool _isEraserMode = false; // Silme modu aktif mi?
  bool _isDraggingTattoo = false; // Tek parmakla taşıma
  int _lastPointerCount = 0; // Gesture pointer sayısını izlemek için
  double _eraserSize = 30.0; // Silgi boyutu
  final ValueNotifier<int> _repaintNotifier = ValueNotifier<int>(0);

  // Receive shared media/text (Pinterest share)
  StreamSubscription<List<SharedMediaFile>>? _mediaStreamSub;

  Future<void> _pickImage() async {
    // iOS'ta galeriye erişmeden önce sistem (Photos) izin kartını iste
    if (!kIsWeb && Platform.isIOS) {
      final perm = await PhotoManager.requestPermissionExtend();
      if (!perm.isAuth) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo access permission denied')),
        );
        return;
      }
    }

    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  Future<void> _takePhoto() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() {
        _selectedImage = File(image.path);
      });
    }
  }

  

  /// Parlak pikselleri şeffaf yapar (tek seferlik CPU işlemi)
  Future<void> _removeBackground() async {
    if (_selectedTattooImage == null) return;

    try {
      final Uint8List bytes = await _selectedTattooImage!.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Unable to process photo')));
        return;
      }

      img.Image im = img.Image.from(decoded);
      if (!im.hasAlpha) {
        im = im.convert(numChannels: 4);
      }

      final int w = im.width;
      final int h = im.height;
      final int totalPixels = w * h;

      double sumLum = 0.0;
      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final p = im.getPixel(x, y);
          final r = p.r / 255.0;
          final g = p.g / 255.0;
          final b = p.b / 255.0;
          sumLum += 0.2126 * r + 0.7152 * g + 0.0722 * b;
        }
      }
      final double avgLum = sumLum / totalPixels;

      final double lowerThreshold = avgLum * 0.6;
      final double upperThreshold = avgLum * 0.9;

      int transparentPixels = 0;
      int semiTransparentPixels = 0;

      for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
          final p = im.getPixel(x, y);
          final r = p.r / 255.0;
          final g = p.g / 255.0;
          final b = p.b / 255.0;

          final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;

          if (lum > upperThreshold) {
            im.setPixel(
              x,
              y,
              img.ColorRgba8(
                (r * 255).toInt(),
                (g * 255).toInt(),
                (b * 255).toInt(),
                0,
              ),
            );
            transparentPixels++;
          } else if (lum > lowerThreshold) {
            final double normalizedLum =
                (lum - lowerThreshold) / (upperThreshold - lowerThreshold);
            final int alpha = (255 * (1.0 - normalizedLum)).toInt();

            im.setPixel(
              x,
              y,
              img.ColorRgba8(
                (r * 255).toInt(),
                (g * 255).toInt(),
                (b * 255).toInt(),
                alpha,
              ),
            );
            semiTransparentPixels++;
          }
        }
      }

      final processedBytes = img.encodePng(im);

      final tempDir = Directory.systemTemp;
      final out = File(
        '${tempDir.path}/processed_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await out.writeAsBytes(processedBytes);

      final loadedBytes = await out.readAsBytes();

      setState(() {
        _selectedTattooImage = out;
        _tattooImageBytes = loadedBytes;

        _tattooScale = 1.0;
        final screenWidth = MediaQuery.of(context).size.width;
        final screenHeight = MediaQuery.of(context).size.height * 0.7;
        _tattooPosition = Offset(
          (screenWidth - 200) / 2,
          (screenHeight - 200) / 2,
        );
        _tattooRotation = 0.0;

        // Silgi durumlarını temizle
        _eraserPaths = [];
        _undoStack = [];
        _isEraserMode = false;
        _repaintNotifier.value++;
      });

      // ignore: avoid_print
      final size = await out.length();
      print(
        'avgLum=$avgLum  lowerThreshold=$lowerThreshold  upperThreshold=$upperThreshold  transparent=$transparentPixels  semiTransparent=$semiTransparentPixels/$totalPixels  bytes=$size',
      );

      
    } catch (e) {
      // no-op
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // --- UNDO / REDO işlemleri ---
  void _undoErase() {
    if (_eraserPaths.isEmpty) return;
    setState(() {
      final last = _eraserPaths.removeLast();
      _undoStack.add(last); // REDO için sakla
      _repaintNotifier.value++;
    });
  }

  void _redoErase() {
    if (_undoStack.isEmpty) return;
    setState(() {
      final redo = _undoStack.removeLast();
      _eraserPaths.add(redo);
      _repaintNotifier.value++;
    });
  }

  // --- Galeriye kaydetme ---
  Future<void> _saveToGallery() async {
    try {
      final boundary =
          _captureKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No capture area found')),
        );
        return;
      }
      // Cihazın piksel oranını kullanın
      final double devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
      final ui.Image uiImage = await boundary.toImage(pixelRatio: devicePixelRatio);

      final byteData = await uiImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to convert image')));
        return;
      }

      final bd = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bd == null) {
        /* hata göster */
        return;
      }

      img.Image im = img.Image.fromBytes(
        width: uiImage.width,
        height: uiImage.height,
        bytes: bd.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );

      // Boyutları hedef fiziksel piksele yuvarlayıp fazla şeffaf satır/sütunu kırp
      final int targetW = (boundary.size.width * devicePixelRatio).round();
      final int targetH = (boundary.size.height * devicePixelRatio).round();
      final int cropW = targetW.clamp(1, im.width);
      final int cropH = targetH.clamp(1, im.height);
      if (im.width != cropW || im.height != cropH) {
        im = img.copyCrop(im, x: 0, y: 0, width: cropW, height: cropH);
      }

      for (int y = 0; y < im.height; y++) {
        for (int x = 0; x < im.width; x++) {
          final p = im.getPixel(x, y);
          if (p.a != 255) {
            final a = p.a / 255.0;
            final r = ((p.r * a) + (255 * (1.0 - a))).round();
            final g = ((p.g * a) + (255 * (1.0 - a))).round();
            final b = ((p.b * a) + (255 * (1.0 - a))).round();
            im.setPixelRgba(x, y, r, g, b, 255);
          }
        }
      }

      final jpgBytes = img.encodeJpg(im, quality: 95);
      final name = 'inkscape_${DateTime.now().millisecondsSinceEpoch}.jpg';

      bool ok = false;

      if (!kIsWeb && Platform.isAndroid) {
        MediaStore.ensureInitialized();
        MediaStore.appFolder = 'InkScape';

        final tmpDir = await getTemporaryDirectory();
        final tmpFile = File('${tmpDir.path}/$name');
        await tmpFile.writeAsBytes(jpgBytes);

        final mediaStore = MediaStore();
        final info = await mediaStore.saveFile(
          tempFilePath: tmpFile.path,
          dirType: DirType.photo,
          dirName: DirName.pictures,
        );
        ok = info?.isSuccessful ?? false;
      } else if (!kIsWeb && Platform.isIOS) {
        final perm = await PhotoManager.requestPermissionExtend();
        if (!perm.isAuth) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Photo access permission denied')),
          );
          return;
        }

        await PhotoManager.editor.saveImage(
          jpgBytes,
          filename: name,
          title: 'InkScape',
        );
        ok = true;
      } else {
        // Web veya desteklenmeyen platformlarda galeriye kaydetme desteklenmiyor
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Save to gallery is not supported on this platform')),
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Saved to gallery ✅' : 'Save failed'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
    _initShareIntentHandling();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final currentUserEmail = prefs.getString('current_user_email');
    setState(() {
      _isLoggedIn = currentUserEmail != null;
    });
  }

  Future<void> _loadUsageState() async {
    final prefs = await SharedPreferences.getInstance();
    final usageCount = prefs.getInt(StorageKeys.tattooUsageCount) ?? 0;

    // RevenueCat üzerinden premium bilgisini güncelle
    final bool hasRcPremium = await PremiumAccess.instance.refreshEntitlementActive();
    await prefs.setBool(StorageKeys.premiumFlag, hasRcPremium);

    if (!mounted) return;
    setState(() {
      _tattooUsageCount = usageCount;
      _isPremiumUser = hasRcPremium;
      _premiumExpiration = null; // RC yönettiği için lokal tarih tutulmuyor
    });
  }

  Future<void> _incrementTattooUsage() async {
    final prefs = await SharedPreferences.getInstance();
    final nextCount = _tattooUsageCount + 1;
    await prefs.setInt(StorageKeys.tattooUsageCount, nextCount);
    if (!mounted) return;
    setState(() {
      _tattooUsageCount = nextCount;
    });
  }

  Future<bool> _ensureTattooAccess() async {
    await _loadUsageState();
    if (_isPremiumUser) {
      return true;
    }

    // 3. denemede (kullanım sayacı 2 iken) puan verme kartını göster
    if (_tattooUsageCount >= 2) {
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getBool(StorageKeys.ratingPromptCompleted) ?? false;
      if (!done) {
        final allowed = await _showRatingGateCard();
        if (allowed) {
          // Kullanıcı puanlama akışını onayladı; devam etmeye izin ver
          await prefs.setBool(StorageKeys.ratingPromptCompleted, true);
          // Not: Limit kontrolünü atlamamak için burada return etmiyoruz.
          // Aşağıdaki limit kontrolüne düşsün.
        } else {
          // Onay vermediyse bu denemeyi durdur
          return false;
        }
      }
    }

    if (_tattooUsageCount >= _freeTattooUsageLimit) {
      if (!mounted) return false;
      String message =
          'You have reached the free usage limit. Continue with Premium.';
      if (_premiumExpiration != null &&
          _premiumExpiration!.isBefore(DateTime.now())) {
        message =
            'Your Premium subscription has ended. Renew to continue unlimited usage.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
      await _openPremiumScreen();
      return false;
    }

    return true;
  }

  Future<bool> _showRatingGateCard() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (ctx) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 360,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Align(
                        alignment: Alignment.center,
                        child: Text(
                          'Do you like the app?',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Rate us to keep using for free.',
                        style: TextStyle(color: Color(0xFFBDBDBD), fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 42,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green[700],
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () async {
                            try {
                              final inAppReview = InAppReview.instance;
                              final avail = await inAppReview.isAvailable();
                              if (avail) {
                                await inAppReview.requestReview();
                              }
                              Navigator.of(ctx).pop(true);
                            } catch (_) {
                              Navigator.of(ctx).pop(true);
                            }
                          },
                          child: const Text(
                            'Rate to continue for free',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: () {
                            Navigator.of(ctx).pop(false);
                          },
                          child: const Text(
                            'Maybe later',
                            style: TextStyle(fontSize: 13),
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
      },
    );

    return result == true;
  }

  Future<void> _openPremiumScreen() async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PremiumScreen()),
    );
    if (!mounted) return;
    await _loadUsageState();
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('current_user_email');
    setState(() {
      _isLoggedIn = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Signed out')),
    );
  }

  @override
  void dispose() {
    _mediaStreamSub?.cancel();
    _repaintNotifier.dispose();
    super.dispose();
  }

  void _initShareIntentHandling() {
    // Stream for receiving media while the app is running
    _mediaStreamSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (List<SharedMediaFile> value) {
        _handleSharedMedia(value);
      },
      onError: (_) {},
    );

    // Check if app was launched via share (cold start)
    ReceiveSharingIntent.instance.getInitialMedia().then((value) {
      if (value.isNotEmpty) {
        _handleSharedMedia(value);
        // Reset so we don't get duplicates next time
        ReceiveSharingIntent.instance.reset();
      }
    });
  }

  Future<void> _handleSharedMedia(List<SharedMediaFile> media) async {
    if (media.isEmpty) return;

    // Try image first
    final image = media.firstWhere(
      (m) => m.type == SharedMediaType.image ||
          m.path.toLowerCase().endsWith('.png') ||
          m.path.toLowerCase().endsWith('.jpg') ||
          m.path.toLowerCase().endsWith('.jpeg'),
      orElse: () => SharedMediaFile(path: '', type: SharedMediaType.text),
    );

    if (image.path.isNotEmpty) {
      try {
        final file = File(image.path);
        if (!await file.exists()) return;

        final canUseTattoo = await _ensureTattooAccess();
        if (!canUseTattoo) return;

        if (!_isPremiumUser) {
          await _incrementTattooUsage();
        }

        setState(() {
          _selectedTattooImage = file;
          _tattooImageBytes = null;
        });
        await _removeBackground();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tattoo received from share')),
        );
        return;
      } catch (_) {}
    }

    // Fallback: check for a shared link/text
    final textItem = media.firstWhere(
      (m) => m.type == SharedMediaType.text,
      orElse: () => SharedMediaFile(path: '', type: SharedMediaType.text),
    );
    if (textItem.path.isNotEmpty) {
      _handleSharedText(textItem.path);
    }
  }

  Future<void> _handleSharedText(String text) async {
    // Accept Pinterest or any webpage link and try to resolve to a real image URL
    final link = text.trim();
    final uri = Uri.tryParse(link);
    if (uri == null) return;

    // Direct image link
    if (uri.path.toLowerCase().endsWith('.png') ||
        uri.path.toLowerCase().endsWith('.jpg') ||
        uri.path.toLowerCase().endsWith('.jpeg') ||
        uri.host.toLowerCase().contains('i.pinimg.com')) {
      await _tryLoadImageFromUrl(uri.toString());
      return;
    }

    // Try to extract image from the web page (Open Graph/Twitter tags), useful for Pinterest share links
    final resolved = await _resolveSharedLinkToImageUrl(uri.toString());
    if (resolved != null) {
      await _tryLoadImageFromUrl(resolved);
    }
  }

  Future<String?> _resolveSharedLinkToImageUrl(String url) async {
    try {
      final client = HttpClient();
      client.userAgent = 'Mozilla/5.0 (Flutter)';
      final req = await client.getUrl(Uri.parse(url));
      req.followRedirects = true;
      req.maxRedirects = 5;
      final resp = await req.close();
      if (resp.statusCode >= 300 && resp.statusCode < 400) {
        final loc = resp.headers.value(HttpHeaders.locationHeader);
        if (loc != null) {
          return await _resolveSharedLinkToImageUrl(loc);
        }
      }

      if (resp.statusCode != 200) return null;
      final bytes = await consolidateHttpClientResponseBytes(resp);
      final html = String.fromCharCodes(bytes);

      // Quick parse for common meta tags
      final candidates = <String?>[
        _extractMetaContent(html, 'property', 'og:image'),
        _extractMetaContent(html, 'name', 'og:image'),
        _extractMetaContent(html, 'property', 'twitter:image'),
        _extractMetaContent(html, 'name', 'twitter:image'),
      ].whereType<String>().toList();

      for (final c in candidates) {
        final u = Uri.tryParse(c);
        if (u != null) {
          // Prefer direct images
          if (u.path.toLowerCase().endsWith('.png') ||
              u.path.toLowerCase().endsWith('.jpg') ||
              u.path.toLowerCase().endsWith('.jpeg') ||
              u.host.toLowerCase().contains('i.pinimg.com')) {
            return u.toString();
          }
        }
      }

      // Fallback: find any <img ... src="...pinimg.com...">
      final imgRegex = RegExp(r'<img[^>]+src=["\"](.*?)["\"][^>]*>', caseSensitive: false);
      for (final m in imgRegex.allMatches(html)) {
        final src = m.group(1);
        if (src == null) continue;
        if (src.contains('i.pinimg.com') ||
            src.toLowerCase().endsWith('.png') ||
            src.toLowerCase().endsWith('.jpg') ||
            src.toLowerCase().endsWith('.jpeg')) {
          return src;
        }
      }
    } catch (_) {}
    return null;
  }

  String? _extractMetaContent(String html, String key, String value) {
    final re = RegExp(
      '<meta[^>]*$key=["\"]$value["\"][^>]*content=["\"]([^"\"]+)["\"][^>]*>',
      caseSensitive: false,
    );
    final match = re.firstMatch(html);
    return match?.group(1);
  }

  Future<void> _tryLoadImageFromUrl(String url) async {
    try {
      final canUseTattoo = await _ensureTattooAccess();
      if (!canUseTattoo) return;

      final client = HttpClient();
      client.userAgent = 'Mozilla/5.0 (Flutter)';
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close();
      if (resp.statusCode != 200) return;
      final bytes = await consolidateHttpClientResponseBytes(resp);
      final tempDir = Directory.systemTemp;
      final out = File(
        '${tempDir.path}/shared_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await out.writeAsBytes(bytes);

      if (!_isPremiumUser) {
        await _incrementTattooUsage();
      }

      setState(() {
        _selectedTattooImage = out;
        _tattooImageBytes = null;
      });
      await _removeBackground();
      if (!mounted) return;
      
    } catch (_) {}
  }

  // External Pinterest flow removed. Using in-app browser instead.

  Future<void> _openPinterestInApp() async {
    final canUseTattoo = await _ensureTattooAccess();
    if (!canUseTattoo) return;

    final selectedUrl = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const PinterestBrowserPage(),
        fullscreenDialog: true,
      ),
    );
    if (selectedUrl == null || selectedUrl.isEmpty) return;

    await _handleSharedText(selectedUrl);
    if (!mounted) return;
    if (_selectedTattooImage != null) {
      
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Görsel alınamadı. Pin sayfasını açıp tekrar deneyin.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canUndo = _eraserPaths.isNotEmpty;
    final canRedo = _undoStack.isNotEmpty;

    // iPhone benzeri genişlikte ölçek faktörü
    final double screenWidth = MediaQuery.of(context).size.width;
    const double designWidth = 375.0;
    final double uiScale = screenWidth / designWidth;
    final double tattooBoxSize = 200.0 * uiScale;

    return Scaffold(
      appBar: AppBar(
        leading: Transform.translate(
          offset: const Offset(0, -4),
          child: IconButton(
            icon: Icon(
              Icons.error_outline,
              color: Colors.white,
              size: 24,
            ),
            onPressed: () {
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    backgroundColor: Colors.grey[900],
                    title: const Text(
                      'About Inkscape',
                      style: const TextStyle(color: Colors.white),
                    ),
                    content: const Text(
                      'Inkscape is a digital tattoo application that allows you to apply tattoos to your photos. You can upload tattoo images, position them, scale them, and erase parts as needed.',
                      style: const TextStyle(color: Color(0xFFBDBDBD)),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        child: const Text(
                          'Close',
                          style: const TextStyle(color: Colors.blue),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        title:
            _isEraserMode
                ? Row(
                  children: [
                    Icon(Symbols.ink_eraser, color: Colors.green[400], size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: Colors.green[400],
                          inactiveTrackColor: Colors.grey[700],
                          thumbColor: Colors.green[400],
                          overlayColor: Colors.green[400]?.withOpacity(0.3),
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 8,
                          ),
                        ),
                        child: Slider(
                          value: _eraserSize,
                          min: 10,
                          max: 100,
                          divisions: 18,
                          onChanged: (value) {
                            setState(() {
                              _eraserSize = value;
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                )
                : Transform.translate(
                  offset: const Offset(0, -5),
                  child: Text(
                    'INKSCAPE',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1,
                    ),
                  ),
                ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.short_text_sharp,
              color: Colors.white,
              size: 30,
            ),
            color: Colors.grey[900],
            onSelected: (String result) async {
              switch (result) {
                case 'profile':
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ProfileScreen()),
                  );
                  break;
                case 'premium':
                  await _openPremiumScreen();
                  break;
                case 'help_support':
                  final Uri emailLaunchUri = Uri(
                    scheme: 'mailto',
                    path: 'tattoo11tattoo@gmail.com',
                    queryParameters: {
                      'subject': 'InkScape Help & Support'
                    }
                  );
                  await launchUrl(emailLaunchUri);
                  break;
                case 'about':
                  showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        backgroundColor: Colors.grey[900],
                        title: const Text(
                          'About',
                          style: TextStyle(color: Colors.white),
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'InkScape',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Version: 1.0.0',
                              style: TextStyle(color: const Color(0xFFBDBDBD)),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'InkScape lets you try digital tattoos on your photos. Upload tattoo designs, position them, scale, and erase as you like.',
                              style: TextStyle(color: const Color(0xFFBDBDBD)),
                            ),
                            SizedBox(height: 16),
                            Text(
                              '© 2024 InkScape',
                              style: TextStyle(color: const Color(0xFF9E9E9E)),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            child: const Text(
                              'Close',
                              style: TextStyle(color: Colors.blue),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                  break;
                case 'logout':
                  _logout();
                  break;
              }
            },
            itemBuilder:
                (BuildContext context) => <PopupMenuEntry<String>>[
                  const PopupMenuItem<String>(
                    value: 'profile',
                    child: const Text(
                      'Profile',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'premium',
                    child: const Text(
                      'Premium',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'help_support',
                    child: Text(
                      'Help & Support',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'about',
                    child: Text(
                      'About',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  if (_isLoggedIn) ...[
                    const PopupMenuDivider(),
                    const PopupMenuItem<String>(
                      value: 'logout',
                      child: const Text(
                        'Logout',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Görsel alanı - Ekranın %70'ini kaplayacak
          RepaintBoundary(
            key: _captureKey,
            child: Container(
              width: double.infinity,
              // Kesit yüksekliğini mantıksal pikselde tam sayıya yuvarla
              height: (MediaQuery.of(context).size.height * 0.7).floorToDouble(),
              decoration: BoxDecoration(color: Colors.black87),
              child: GestureDetector(
                onScaleStart: _selectedTattooImage != null ? (ScaleStartDetails details) {
                  _lastPointerCount = details.pointerCount;
                  if (details.pointerCount == 1) {
                    if (_selectedTattooImage != null) {
                      final localPosition = details.localFocalPoint;

                      // Dövme merkezine olan uzaklığa göre kabaca temas kontrolü
                      final double half = tattooBoxSize / 2;
                      final center = Offset(
                        _tattooPosition.dx + half,
                        _tattooPosition.dy + half,
                      );
                      final distance = (localPosition - center).distance;
                      final maxDistance = math.max(50.0, half * _tattooScale * 1.5);

                      if (_isEraserMode) {
                        // Silgi modu: path başlat
                        if (distance <= maxDistance) {
                          setState(() {
                            _isErasing = true;

                            final containerCenterX = _tattooPosition.dx + half;
                            final containerCenterY = _tattooPosition.dy + half;

                            final touchFromCenterX = localPosition.dx - containerCenterX;
                            final touchFromCenterY = localPosition.dy - containerCenterY;

                            final unscaledX = touchFromCenterX / _tattooScale;
                            final unscaledY = touchFromCenterY / _tattooScale;

                            final cos = math.cos(-_tattooRotation);
                            final sin = math.sin(-_tattooRotation);

                            final rotatedX = unscaledX * cos - unscaledY * sin;
                            final rotatedY = unscaledX * sin + unscaledY * cos;

                            final finalX = rotatedX + half;
                            final finalY = rotatedY + half;

                            _currentPath = Path()..moveTo(finalX, finalY);
                            _repaintNotifier.value++;
                          });
                        }
                      } else {
                        // Taşıma modu: tek parmakla sürüklemeyi aktif et (isabetliyse)
                        if (distance <= maxDistance) {
                          setState(() {
                            _isDraggingTattoo = true;
                          });
                        }
                      }
                    }
                  } else {
                    // Çok parmak - ölçeklendirme/döndürme için hazırlık
                    _initialScale = _tattooScale;
                    _initialRotation = _tattooRotation;
                    _isDraggingTattoo = false;
                  }
                } : null,
                onScaleUpdate: _selectedTattooImage != null ? (ScaleUpdateDetails details) {
                  // Pointer sayısı değiştiyse geçişleri yönet
                  if (details.pointerCount != _lastPointerCount) {
                    if (details.pointerCount > 1 && _lastPointerCount <= 1) {
                      // Tek parmak -> çok parmak geçişi: pinch için baz değerleri al
                      _initialScale = _tattooScale;
                      _initialRotation = _tattooRotation;
                      // Devam eden silme işlemi varsa path'i kaydet
                      if (_isErasing && _currentPath != null) {
                        final pathCopy = Path();
                        pathCopy.addPath(_currentPath!, Offset.zero);
                        _eraserPaths.add(
                          EraserPath(path: pathCopy, strokeWidth: _eraserSize),
                        );
                        _currentPath = null;
                        _isErasing = false;
                        _undoStack.clear();
                        _repaintNotifier.value++;
                      }
                      _isDraggingTattoo = false;
                    }
                    _lastPointerCount = details.pointerCount;
                  }

                  if (details.pointerCount == 1 &&
                      _isErasing &&
                      _currentPath != null) {
                    final localPosition = details.localFocalPoint;

                    setState(() {
                      final double half = tattooBoxSize / 2;
                      final containerCenterX = _tattooPosition.dx + half;
                      final containerCenterY = _tattooPosition.dy + half;

                      final touchFromCenterX =
                          localPosition.dx - containerCenterX;
                      final touchFromCenterY =
                          localPosition.dy - containerCenterY;

                      final unscaledX = touchFromCenterX / _tattooScale;
                      final unscaledY = touchFromCenterY / _tattooScale;

                      final cos = math.cos(-_tattooRotation);
                      final sin = math.sin(-_tattooRotation);

                      final rotatedX = unscaledX * cos - unscaledY * sin;
                      final rotatedY = unscaledX * sin + unscaledY * cos;

                      final finalX = rotatedX + half;
                      final finalY = rotatedY + half;

                      _currentPath!.lineTo(finalX, finalY);
                      _repaintNotifier.value++;
                    });
                  } else if (details.pointerCount == 1 && !_isEraserMode && _isDraggingTattoo) {
                    // Tek parmakla dövmeyi sürükle
                    setState(() {
                      _tattooPosition += details.focalPointDelta;
                    });
                  } else if (details.pointerCount > 1 && !_isErasing) {
                    setState(() {
                      // Ölçeklendirme
                      _tattooScale = (_initialScale * details.scale).clamp(
                        0.1,
                        5.0,
                      );

                      // Taşıma
                      _tattooPosition += details.focalPointDelta;

                      // Döndürme (2 parmak)
                      if (details.pointerCount == 2) {
                        final double rotationDelta = details.rotation;
                        _tattooRotation = _initialRotation + rotationDelta;
                      }
                    });
                  }
                } : null,
                onScaleEnd: _selectedTattooImage != null ? (ScaleEndDetails details) {
                  // Silme modundaysak, path'i kaydet
                  if (_isErasing && _currentPath != null) {
                    setState(() {
                      final pathCopy = Path();
                      pathCopy.addPath(_currentPath!, Offset.zero);

                      _eraserPaths.add(
                        EraserPath(path: pathCopy, strokeWidth: _eraserSize),
                      );
                      _currentPath = null;
                      _isErasing = false;

                      // Yeni bir darbe oluştuğu için REDO yığınını temizle
                      _undoStack.clear();

                      _repaintNotifier.value++;
                    });
                  } else {
                    _isDraggingTattoo = false;
                  }
                  _lastPointerCount = 0;
                } : null,
                child: Stack(
                  children: [
                    // Arka plan fotoğrafı
                    if (_selectedImage != null)
                      Image.file(
                        _selectedImage!,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        filterQuality: FilterQuality.high,
                      )
                    else
                      Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
        Icon(
          Icons.add_to_photos_outlined,
          size: 40,
          color: Colors.grey[600],
        ),
                            const SizedBox(height: 16),
                            Text(
                              'Try tattoo on your photo',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),

                    // Fotoğraf alanına dokununca Web’den içe aktar (yalnızca dövme yoksa ve arka plan fotoğrafı varsa)
                    if (_selectedTattooImage == null && _selectedImage != null)
                      Positioned.fill(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _openPinterestInApp,
                          ),
                        ),
                      ),

                    // İpucu metni: küçük alt bilgi
                    if (_selectedImage != null && _selectedTattooImage == null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 12,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.touch_app, size: 16, color: Colors.white70),
                                SizedBox(width: 6),
                                Text(
                                  'Dövme seçmek için fotoğrafa dokunun',
                                  style: TextStyle(fontSize: 12, color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // Overlay (şeffaf alanlı PNG) - İnteraktif dövme
                    if (_selectedTattooImage != null)
                      Positioned(
                        left: _tattooPosition.dx,
                        top: _tattooPosition.dy,
                        child: Transform.rotate(
                          angle: _tattooRotation,
                          alignment: Alignment.center,
                          child: Transform.scale(
                            scale: _tattooScale,
                            alignment: Alignment.center,
                            child: Container(
                              width: tattooBoxSize,
                              height: tattooBoxSize,
                              decoration: BoxDecoration(
                                border:
                                    _isEraserMode
                                        ? Border.all(
                                          color: Colors.green[500]!,
                                          width: 2,
                                        )
                                        : null,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child:
                                  _tattooImageBytes == null
                                      ? const Center(
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: ValueListenableBuilder<int>(
                                          valueListenable: _repaintNotifier,
                                          builder: (context, value, child) {
                                            return CustomPaint(
                                              key: ValueKey('eraser_$value'),
                                              size: Size(tattooBoxSize, tattooBoxSize),
                                              painter: EraserPainter(
                                                image: _tattooImageBytes!,
                                                eraserPaths: [
                                                  ..._eraserPaths,
                                                  if (_currentPath != null)
                                                    EraserPath(
                                                      path: _currentPath!,
                                                      strokeWidth: _eraserSize,
                                                    ),
                                                ],
                                                repaintNotifier:
                                                    _repaintNotifier,
                                              ),
                                              child: Container(),
                                            );
                                          },
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

          // Butonlar bölümü
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(height: _selectedTattooImage != null ? 10 : 20),

                  // Üst buton satırı
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (_selectedImage == null) ...[
                        ElevatedButton(
                          onPressed: _takePhoto,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[800],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            elevation: 3,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.camera_alt, size: 20),
                              SizedBox(width: 8),
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'CAMERA',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton(
                          onPressed: _pickImage,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[800],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            elevation: 3,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.photo_library, size: 20),
                              SizedBox(width: 8),
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'GALLERY',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else if (_selectedTattooImage == null) ...[
                        ElevatedButton(
                          onPressed: _openPinterestInApp,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green[900],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            elevation: 3,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.brush, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'TATTOO',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        // Dövme var: Silgi KAPALI ise sadece Silgi butonu; Silgi AÇIK ise Undo/Redo
                        if (!_isEraserMode) ...[
                          SizedBox(
                            width: 170,
                            child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _isEraserMode = !_isEraserMode;
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  _isEraserMode
                                      ? Colors.green[800]
                                      : Colors.grey[700],
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              elevation: 3,
                            ),
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Symbols.ink_eraser, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'ERASER',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          ),
                        ] else ...[
                          ElevatedButton.icon(
                            onPressed: canUndo ? _undoErase : null,
                            icon: const Icon(Icons.undo, size: 18),
                            label: const Text('UNDO'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[800],
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey[850],
                              disabledForegroundColor: Colors.grey[600],
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: canRedo ? _redoErase : null,
                            icon: const Icon(Icons.redo, size: 18),
                            label: const Text('REDO'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey[800],
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey[850],
                              disabledForegroundColor: Colors.grey[600],
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Alt buton satırı: Silgi KAPALI iken GALLERY + TATTOO + SAVE; Silgi AÇIK iken sadece Silgi
                  if (_selectedTattooImage != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (!_isEraserMode) ...[
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed: _pickImage,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey[800],
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  elevation: 3,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.photo_library, size: 20),
                                    SizedBox(width: 8),
                                    Flexible(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          'GALLERY',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed: _openPinterestInApp,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green[900],
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  elevation: 3,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.brush, size: 20),
                                    SizedBox(width: 8),
                                    Flexible(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          'TATTOO',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed: _saveToGallery,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue[800],
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  elevation: 3,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.file_download, size: 20),
                                    SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        'SAVE',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          const Spacer(flex: 1),
                          Expanded(
                            flex: 2,
                            child: SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _isEraserMode = !_isEraserMode;
                                  });
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      _isEraserMode
                                          ? Colors.green[800]
                                          : Colors.grey[700],
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  elevation: 3,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Symbols.ink_eraser, size: 20),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          'ERASER',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const Spacer(flex: 1),
                        ],
                      ],
                    ),
                  ],

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Silgi painter sınıfı
class EraserPainter extends CustomPainter {
  final Uint8List imageBytes;
  final List<EraserPath> eraserPaths;
  final ValueNotifier<int>? repaintNotifier;
  static final Map<int, ui.Image> _imageCache = {};

  EraserPainter({
    required Uint8List image,
    required this.eraserPaths,
    this.repaintNotifier,
  }) : imageBytes = image,
       super(repaint: repaintNotifier) {
    _loadImage();
  }

  void _loadImage() async {
    final key = imageBytes.hashCode;
    if (_imageCache.containsKey(key)) return;

    try {
      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();
      _imageCache[key] = frame.image;
      repaintNotifier?.value++;
    } catch (e) {
      // ignore: avoid_print
      print('Error loading image: $e');
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final key = imageBytes.hashCode;
    final image = _imageCache[key];

    if (image == null) {
      final loadingPaint = Paint()..color = Colors.grey.withOpacity(0.3);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        loadingPaint,
      );
      return;
    }

    final paint = Paint();
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );

    // Aspect ratio'yu koruyarak hedef alanı hesapla
    final double imageAspectRatio = image.width / image.height;
    final double canvasAspectRatio = size.width / size.height;

    double dstWidth, dstHeight, dstX, dstY;

    if (imageAspectRatio > canvasAspectRatio) {
      dstWidth = size.width;
      dstHeight = size.width / imageAspectRatio;
      dstX = 0;
      dstY = (size.height - dstHeight) / 2;
    } else {
      dstHeight = size.height;
      dstWidth = size.height * imageAspectRatio;
      dstX = (size.width - dstWidth) / 2;
      dstY = 0;
    }

    final dst = Rect.fromLTWH(dstX, dstY, dstWidth, dstHeight);

    canvas.saveLayer(null, Paint());
    canvas.drawImageRect(image, src, dst, paint);

    // Silgi path'lerini uygula
    if (eraserPaths.isNotEmpty) {
      for (final eraserPath in eraserPaths) {
        final eraserPaint =
            Paint()
              ..color = Colors.transparent
              ..blendMode = BlendMode.clear
              ..style = PaintingStyle.stroke
              ..strokeWidth = eraserPath.strokeWidth
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round;

        canvas.drawPath(eraserPath.path, eraserPaint);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(EraserPainter oldDelegate) {
    return true;
  }
}
