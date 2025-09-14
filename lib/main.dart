import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:media_store_plus/media_store_plus.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'profile_screen.dart';

// Silgi path'i ve boyutunu saklayan sınıf
class EraserPath {
  final Path path;
  final double strokeWidth;

  EraserPath({required this.path, required this.strokeWidth});
}

void main() {
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
          title: 'InkScape',
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
  bool _isProcessing = false;
  bool _isLoggedIn = false;

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
  double _eraserSize = 30.0; // Silgi boyutu
  final ValueNotifier<int> _repaintNotifier = ValueNotifier<int>(0);

  Future<void> _pickImage() async {
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

  Future<void> _pickTattooImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedTattooImage = File(image.path);
        _tattooImageBytes = null; // Önceki görseli temizle
      });

      // Dövme yüklendikten sonra otomatik olarak arka plan temizleme işlemini başlat
      _removeBackground();
    }
  }

  /// Parlak pikselleri şeffaf yapar (tek seferlik CPU işlemi)
  Future<void> _removeBackground() async {
    if (_selectedTattooImage == null) return;

    setState(() => _isProcessing = true);

    try {
      final Uint8List bytes = await _selectedTattooImage!.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Fotoğraf çözümlenemedi')));
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
        _isProcessing = false;

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

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Arka plan kaldırıldı'),
          duration: Duration(seconds: 3),
        ),
      );
    } catch (e) {
      setState(() => _isProcessing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
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
          const SnackBar(content: Text('Kaydedilecek alan bulunamadı')),
        );
        return;
      }

      final ui.Image uiImage = await boundary.toImage(pixelRatio: 3.0);

      final byteData = await uiImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Görsel dönüştürülemedi')));
        return;
      }

      final bd = await uiImage.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bd == null) {
        /* hata göster */
        return;
      }

      final img.Image im = img.Image.fromBytes(
        width: uiImage.width,
        height: uiImage.height,
        bytes: bd.buffer,
        numChannels: 4,
        order: img.ChannelOrder.rgba,
      );

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

      if (Platform.isAndroid) {
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
      } else if (Platform.isIOS) {
        final perm = await PhotoManager.requestPermissionExtend();
        if (!perm.isAuth) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fotoğraf erişim izni verilmedi')),
          );
          return;
        }

        final entity = await PhotoManager.editor.saveImage(
          jpgBytes,
          filename: name,
          title: 'InkScape',
        );
        ok = entity != null;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? 'Galeriye kaydedildi ✅' : 'Kaydetme başarısız'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

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
    });
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('current_user_email');
    setState(() {
      _isLoggedIn = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Çıkış yapıldı')),
    );
  }

  @override
  void dispose() {
    _repaintNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canUndo = _eraserPaths.isNotEmpty;
    final canRedo = _undoStack.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        leading: Transform.translate(
          offset: const Offset(0, -4),
          child: IconButton(
            icon: Icon(
              Icons.error_outline,
              color: Colors.white,
              size: 22.sp,
            ),
            onPressed: () {
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    backgroundColor: Colors.grey[900],
                    title: const Text(
                      'About InkScape',
                      style: const TextStyle(color: Colors.white),
                    ),
                    content: const Text(
                      'InkScape is a digital tattoo application that allows you to apply tattoos to your photos. You can upload tattoo images, position them, scale them, and erase parts as needed.',
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
                    Icon(Icons.brush, color: Colors.red[400], size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '${_eraserSize.toInt()}px',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: Colors.red[400],
                          inactiveTrackColor: Colors.grey[700],
                          thumbColor: Colors.red[400],
                          overlayColor: Colors.red[400]?.withOpacity(0.3),
                          trackHeight: 4,
                          thumbShape: RoundSliderThumbShape(
                            enabledThumbRadius: 8.r,
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
                      fontSize: 16.sp,
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
                case 'help_support':
                  final Uri emailLaunchUri = Uri(
                    scheme: 'mailto',
                    path: 'tattoo11tattoo@gmail.com',
                    queryParameters: {
                      'subject': 'InkScape Yardım & Destek'
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
                          'Hakkında',
                          style: const TextStyle(color: Colors.white),
                        ),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'InkScape',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18.sp,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 8.h),
          Text(
            'Versiyon: 1.0.0',
            style: const TextStyle(color: Color(0xFFBDBDBD)),
          ),
          SizedBox(height: 8.h),
          Text(
            'InkScape, fotoğraflarınıza dijital dövme uygulaması yapmanızı sağlayan bir uygulamadır. Dövme görsellerini yükleyin, konumlandırın, ölçeklendirin ve silin.',
            style: const TextStyle(color: Color(0xFFBDBDBD)),
          ),
          SizedBox(height: 16.h),
          Text(
            '© 2024 InkScape',
            style: const TextStyle(color: Color(0xFF9E9E9E)),
          ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            child: const Text(
                              'Kapat',
                              style: const TextStyle(color: Colors.blue),
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
                    value: 'help_support',
                    child: const Text(
                      'Yardım & Destek',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'about',
                    child: const Text(
                      'Hakkında',
                      style: const TextStyle(color: Colors.white),
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
              height: MediaQuery.of(context).size.height * 0.7,
              decoration: BoxDecoration(color: Colors.black87),
              child: GestureDetector(
                onScaleStart: (ScaleStartDetails details) {
                  if (details.pointerCount == 1) {
                    // Tek parmak - silme modu kontrolü
                    if (_selectedTattooImage != null && _isEraserMode) {
                      final localPosition = details.localFocalPoint;

                      // Basit içeri-dışarı kontrol (döndürmeyi yaklaşık kabul)
                      final center = Offset(
                        _tattooPosition.dx + 100,
                        _tattooPosition.dy + 100,
                      );
                      final distance = (localPosition - center).distance;
                      final maxDistance = math.max(
                        50.0,
                        100 * _tattooScale * 1.5,
                      );

                      if (distance <= maxDistance) {
                        setState(() {
                          _isErasing = true;

                          final containerCenterX = _tattooPosition.dx + 100;
                          final containerCenterY = _tattooPosition.dy + 100;

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

                          final finalX = rotatedX + 100;
                          final finalY = rotatedY + 100;

                          _currentPath = Path()..moveTo(finalX, finalY);
                          _repaintNotifier.value++;
                        });
                      }
                    }
                  } else {
                    // Çok parmak - ölçeklendirme/döndürme için hazırlık
                    _initialScale = _tattooScale;
                    _initialRotation = _tattooRotation;
                  }
                },
                onScaleUpdate: (ScaleUpdateDetails details) {
                  if (details.pointerCount == 1 &&
                      _isErasing &&
                      _currentPath != null) {
                    final localPosition = details.localFocalPoint;

                    setState(() {
                      final containerCenterX = _tattooPosition.dx + 100;
                      final containerCenterY = _tattooPosition.dy + 100;

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

                      final finalX = rotatedX + 100;
                      final finalY = rotatedY + 100;

                      _currentPath!.lineTo(finalX, finalY);
                      _repaintNotifier.value++;
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
                },
                onScaleEnd: (ScaleEndDetails details) {
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
                  }
                },
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
          size: 50,
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
                              width: 200,
                              height: 200,
                              decoration: BoxDecoration(
                                border:
                                    _isEraserMode
                                        ? Border.all(
                                          color: Colors.red,
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
                                              size: const Size(200, 200),
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
                  const SizedBox(height: 20),

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
                              Icon(Icons.camera_alt, size: 20.sp),
                              SizedBox(width: 8.w),
                              Text(
                                'CAMERA',
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.bold,
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
                              Icon(Icons.photo_library, size: 20.sp),
                              SizedBox(width: 8.w),
                              Text(
                                'GALLERY',
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else if (_selectedTattooImage == null) ...[
                        ElevatedButton(
                          onPressed: _pickTattooImage,
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
                              Icon(Icons.brush, size: 20.sp),
                              SizedBox(width: 8.w),
                              Text(
                                'TATTOO',
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        // Dövme var: Eraser OFF ise Gallery+Tattoo; Eraser ON ise Undo+Redo
                        if (!_isEraserMode) ...[
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
                              Icon(Icons.photo_library, size: 20.sp),
                              SizedBox(width: 8.w),
                              Text(
                                'GALLERY',
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          ),
                          ElevatedButton(
                            onPressed: _pickTattooImage,
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
                              Icon(Icons.brush, size: 20.sp),
                              SizedBox(width: 8.w),
                              Text(
                                'TATTOO',
                                style: TextStyle(
                                  fontSize: 14.sp,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
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

                  // Silme modu kontrolü (UNDO/REDO üst sırada)
                  if (_selectedTattooImage != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _isEraserMode = !_isEraserMode;
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                _isEraserMode
                                    ? Colors.red[800]
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
                          child: Row(
                            children: [
                              Icon(
                                _isEraserMode
                                    ? Icons.brush
                                    : Icons.brush_outlined,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _isEraserMode ? 'ERASER ON' : 'ERASER OFF',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _saveToGallery,
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
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.camera_alt, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Save to Gallery',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
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
