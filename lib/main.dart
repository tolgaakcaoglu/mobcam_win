import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

// --- Yapılandırma ---
const String SERVER_DIRECTORY = r'server';
const String VIEWER_WS_URL = 'ws://localhost:8081';
const String NODE_DOWNLOAD_URL = 'https://nodejs.org/en/download/';
const String ICON_PATH = 'assets/icon.ico';
// --------------------

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(800, 700),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  runApp(const DesktopApp());
}

class DesktopApp extends StatelessWidget {
  const DesktopApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Mobcam PC İstemcisi',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blueGrey,
        scaffoldBackgroundColor: const Color(0xFF1f2937),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Colors.white70),
          titleLarge: TextStyle(color: Colors.white),
        ),
      ),
      home: const ControlScreen(),
    );
  }
}

class ControlScreen extends StatefulWidget {
  const ControlScreen({super.key});
  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> with WindowListener {
  // Durum Yönetimi
  bool _isNodeInstalled = false;
  bool _isCheckingNode = true;
  bool _isServerRunning = false;
  Process? _nodeProcess;
  Process? _adbProcess;
  final List<String> _serverLogs = [];
  final ScrollController _logScrollController = ScrollController();
  WebSocketChannel? _channel;
  ui.Image? _latestImage;
  final SystemTray _systemTray = SystemTray();
  final Menu _menu = Menu();

  // --- YENİ: Performans Sayaçları ---
  int _frameCount = 0; // 1 saniyede işlenen kare sayısı
  int _fps = 0; // UI'da gösterilecek FPS
  int _droppedFrames = 0; // PC'de işlenemediği için atlanan kare sayısı
  Timer? _fpsTimer; // FPS hesaplayıcı zamanlayıcı
  bool _isProcessingFrameWindows = false; // PC'nin kare işleme kilidi
  // --- YENİ SON ---

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _checkNodeJsInstallation();
    _initSystemTray();

    // --- YENİ: FPS Zamanlayıcısını Başlat ---
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _fps = _frameCount; // FPS'i güncelle
          _frameCount = 0; // Sayacı sıfırla
        });
      }
    });
    // --- YENİ SON ---
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _systemTray.destroy();
    _stopServer();
    _logScrollController.dispose();
    _fpsTimer?.cancel(); // <-- YENİ: Zamanlayıcıyı iptal et
    super.dispose();
  }

  // ... ( _initSystemTray, onWindowClose, _showWindow, _hideWindow, _toggleWindowVisibility, _exitApp, _checkNodeJsInstallation, _launchNodeDownloadUrl, _startServer ) ...
  // Bu fonksiyonlarda değişiklik yok.

  Future<void> _initSystemTray() async {
    if (!Platform.isWindows) return;
    try {
      await _systemTray.initSystemTray(
        toolTip: "Webcam PC İstemcisi",
        iconPath: ICON_PATH,
      );
    } catch (e) {
      _addLog("HATA: Sistem tepsisi ikonu yüklenemedi. $e");
      return;
    }
    await _menu.buildFrom([
      MenuItemLabel(
        label: 'Kontrol Panelini Göster',
        onClicked: (menuItem) => _showWindow(),
      ),
      MenuItemLabel(
        label: 'Servisleri Durdur',
        onClicked: (menuItem) {
          if (_isServerRunning) {
            _stopServer();
          }
        },
      ),
      MenuSeparator(),
      MenuItemLabel(label: 'Çıkış Yap', onClicked: (menuItem) => _exitApp()),
    ]);
    await _systemTray.setContextMenu(_menu);
    _systemTray.registerSystemTrayEventHandler((eventName) {
      if (eventName == kSystemTrayEventClick) {
        _toggleWindowVisibility();
      } else if (eventName == kSystemTrayEventRightClick) {
        _systemTray.popUpContextMenu();
      }
    });
  }

  @override
  void onWindowClose() => _hideWindow();
  void _showWindow() {
    windowManager.show();
    windowManager.focus();
  }

  void _hideWindow() => windowManager.hide();
  void _toggleWindowVisibility() async {
    bool isVisible = await windowManager.isVisible();
    isVisible ? _hideWindow() : _showWindow();
  }

  Future<void> _exitApp() async {
    await _stopServer();
    await _systemTray.destroy();
    await windowManager.destroy();
  }

  Future<void> _checkNodeJsInstallation() async {
    setState(() {
      _isCheckingNode = true;
      _addLog('Node.js kontrol ediliyor...');
    });
    try {
      final result = await Process.run('node', ['--version']);
      if (result.exitCode == 0) {
        setState(() => _isNodeInstalled = true);
        _addLog('Node.js bulundu: ${result.stdout.toString().trim()}');
      } else {
        throw Exception('Node.js bulunamadı');
      }
    } catch (e) {
      setState(() => _isNodeInstalled = false);
      _addLog('HATA: Node.js PATH üzerinde bulunamadı.');
    } finally {
      setState(() => _isCheckingNode = false);
    }
  }

  Future<void> _launchNodeDownloadUrl() async {
    if (!await launchUrl(Uri.parse(NODE_DOWNLOAD_URL))) {
      _addLog('HATA: Node.js indirme sayfası açılamadı.');
    }
  }

  Future<void> _startServer() async {
    if (_isServerRunning) return;
    setState(() {
      _isServerRunning = true;
      _serverLogs.clear();
      _addLog('Servisler başlatılıyor...');
    });

    try {
      _nodeProcess = await Process.start(
        'node',
        ['server.js'],
        workingDirectory: SERVER_DIRECTORY,
        runInShell: true,
      );
      _addLog('Node.js sunucusu başlatıldı (PID: ${_nodeProcess!.pid}).');
      _nodeProcess!.stdout
          .transform(utf8.decoder)
          .listen((data) => _addLog('[NODE]: ${data.trim()}'));
      _nodeProcess!.stderr
          .transform(utf8.decoder)
          .listen((data) => _addLog('[NODE HATA]: ${data.trim()}'));
    } catch (e) {
      _addLog('HATA: Node sunucusu başlatılamadı. $e');
      setState(() => _isServerRunning = false);
      return;
    }

    try {
      _adbProcess = await Process.start('adb', [
        'reverse',
        'tcp:8080',
        'tcp:8080',
      ], runInShell: true);
      _addLog('ADB reverse komutu çalıştırıldı (PID: ${_adbProcess!.pid}).');
      _adbProcess!.stdout
          .transform(utf8.decoder)
          .listen((data) => _addLog('[ADB]: ${data.trim()}'));
      _adbProcess!.stderr
          .transform(utf8.decoder)
          .listen((data) => _addLog('[ADB HATA]: ${data.trim()}'));
    } catch (e) {
      _addLog('HATA: ADB reverse başlatılamadı. "adb" PATH üzerinde mi? $e');
      _stopServer();
      return;
    }

    await Future.delayed(const Duration(seconds: 1));
    _connectToWebSocket();
  }

  Future<void> _stopServer() async {
    if (!_isServerRunning) return;
    _addLog('Servisler durduruluyor...');
    _channel?.sink.close();
    _channel = null;

    if (_adbProcess != null) {
      bool adbKilled = _adbProcess!.kill();
      _addLog('ADB sonlandırıldı: $adbKilled');
    }
    if (_nodeProcess != null) {
      bool nodeKilled = false;
      if (Platform.isWindows) {
        try {
          final result = await Process.run('taskkill', [
            '/F',
            '/T',
            '/PID',
            _nodeProcess!.pid.toString(),
          ]);
          nodeKilled = result.exitCode == 0;
        } catch (e) {
          nodeKilled = _nodeProcess!.kill();
        }
      } else {
        nodeKilled = _nodeProcess!.kill();
      }
      _addLog('Node.js sonlandırıldı (Başarı: $nodeKilled)');
    }
    _nodeProcess = null;
    _adbProcess = null;
    if (mounted) {
      setState(() {
        _isServerRunning = false;
        _latestImage = null;
        // --- YENİ: Sayaçları Sıfırla ---
        _fps = 0;
        _frameCount = 0;
        _droppedFrames = 0;
        // --- YENİ SON ---
      });
    }
  }

  void _connectToWebSocket() {
    _addLog('WebSocket görüntüleyiciye bağlanılıyor: $VIEWER_WS_URL');
    try {
      _channel = WebSocketChannel.connect(Uri.parse(VIEWER_WS_URL));
      _channel!.stream.listen(
        (message) {
          // --- YENİ: PC Taraflı Kare Atlama Kontrolü ---
          if (_isProcessingFrameWindows) {
            // PC hala bir önceki kareyi işliyor, bu kareyi atla.
            if (mounted) {
              setState(() {
                _droppedFrames++; // Kayıp kare sayacını artır
              });
            }
            return; // Kareyi işleme
          }
          _isProcessingFrameWindows = true; // Kilitle
          // --- YENİ SON ---

          // --- YENİ: FPS Sayacını Artır ---
          // (Sadece işleme alınan kareleri say)
          _frameCount++;
          // --- YENİ SON ---

          String jsonString;
          if (message is String) {
            jsonString = message;
          } else if (message is Uint8List) {
            jsonString = utf8.decode(message);
          } else {
            _addLog('HATA: Bilinmeyen veri tipi: ${message.runtimeType}');
            _isProcessingFrameWindows = false; // Kilidi aç
            return;
          }
          _processFrame(jsonString); // İşlemeye gönder
        },
        onDone: () {
          _addLog('WebSocket bağlantısı kapandı.');
          if (_isServerRunning) {
            _addLog('Yeniden bağlanılıyor...');
            _connectToWebSocket();
          }
        },
        onError: (error) => _addLog('WebSocket Hatası: $error'),
      );
    } catch (e) {
      _addLog('WebSocket bağlantı hatası: $e');
    }
  }

  // --- DEĞİŞİKLİK: HİBRİT İŞLEME (Kilit Açma Eklendi) ---
  void _processFrame(String message) {
    // Kilit _connectToWebSocket'ta 'true' yapıldı
    try {
      final Map<String, dynamic> frameData = jsonDecode(message);

      if (frameData['type'] == 'jpeg' && frameData['frame'] != null) {
        final Uint8List jpegBytes = base64Decode(frameData['frame']);
        ui.decodeImageFromList(jpegBytes, (ui.Image img) {
          if (mounted && _isServerRunning) {
            setState(() => _latestImage = img);
          }
          _isProcessingFrameWindows = false; // <-- YENİ: Kilidi Aç (JPEG)
        });
      } else if (frameData['type'] == 'yuv') {
        _processYuvFrame(frameData); // Bu fonksiyon kendi kilidini açacak
      } else {
        _addLog('HATA: Beklenmedik JSON formatı.');
        _isProcessingFrameWindows = false; // <-- YENİ: Kilidi Aç (Hata)
      }
    } catch (e) {
      _addLog('HATA: Görüntü karesi işlenemedi. $e');
      _isProcessingFrameWindows = false; // <-- YENİ: Kilidi Aç (Hata)
    }
  }

  // --- DEĞİŞİKLİK: YUV İŞLEME (Kilit Açma Eklendi) ---
  void _processYuvFrame(Map<String, dynamic> frameData) {
    try {
      final int width = frameData['width'];
      final int height = frameData['height'];
      final int uvWidth = frameData['uvWidth'];
      final Uint8List yBytes = base64Decode(frameData['yData']);
      final Uint8List uBytes = base64Decode(frameData['uData']);
      final Uint8List vBytes = base64Decode(frameData['vData']);
      final Uint8List rgbaBytes = Uint8List(width * height * 4);

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int yIndex = (y * width) + x;
          final int uvX = x ~/ 2;
          final int uvY = y ~/ 2;
          final int uvIndex = (uvY * uvWidth) + uvX;
          final int yValue = yBytes[yIndex];
          final int uValue = uBytes[uvIndex];
          final int vValue = vBytes[uvIndex];
          final double r = yValue + 1.402 * (vValue - 128);
          final double g =
              yValue - 0.344136 * (uValue - 128) - 0.714136 * (vValue - 128);
          final double b = yValue + 1.772 * (uValue - 128);
          final int pixelIndex = yIndex * 4;
          rgbaBytes[pixelIndex] = r.clamp(0, 255).toInt();
          rgbaBytes[pixelIndex + 1] = g.clamp(0, 255).toInt();
          rgbaBytes[pixelIndex + 2] = b.clamp(0, 255).toInt();
          rgbaBytes[pixelIndex + 3] = 255;
        }
      }

      ui.decodeImageFromPixels(
        rgbaBytes,
        width,
        height,
        ui.PixelFormat.rgba8888,
        (ui.Image img) {
          if (mounted && _isServerRunning) {
            setState(() => _latestImage = img);
          }
          _isProcessingFrameWindows = false; // <-- YENİ: Kilidi Aç (YUV)
        },
      );
    } catch (e) {
      _addLog("YUV İşleme Hatası: $e");
      _isProcessingFrameWindows = false; // <-- YENİ: Kilidi Aç (Hata)
    }
  }

  void _addLog(String log) {
    if (mounted) {
      setState(() => _serverLogs.add(log));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logScrollController.hasClients) {
          _logScrollController.animateTo(
            _logScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  void _showObsInfoDialog() {
    const String obsUrl = 'http://localhost:3000';
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF2d3748),
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.white),
              SizedBox(width: 10),
              Text(
                'OBS Studio Kurulum Talimatı',
                style: TextStyle(color: Colors.white),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Telefon görüntüsünü OBS\'e aktarmak için:'),
                const SizedBox(height: 16),
                const Text(
                  '1. OBS\'te "Kaynaklar" (Sources) paneline \'+\' ile tıklayın.',
                ),
                const Text('2. "Tarayıcı" (Browser) kaynağı seçin.'),
                const SizedBox(height: 16),
                const Text(
                  '3. URL kısmına aşağıdaki adresi yapıştırın:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1a202c),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: SelectableText(
                          obsUrl,
                          style: TextStyle(
                            fontFamily: 'Consolas',
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 18),
                        tooltip: 'Adresi Kopyala',
                        onPressed: () {
                          Clipboard.setData(const ClipboardData(text: obsUrl));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('URL Kopyalandı!'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  '4. Genişlik: 1920, Yükseklik: 1080 girin (veya akış çözünürlüğü).',
                ),
                const Text('5. OBS\'te "Sanal Kamerayı Başlat"a tıklayın.'),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Kapat'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PC İstemcisi ve Sunucu Kontrol Paneli'),
        backgroundColor: const Color(0xFF374151),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildControlPanel(),
            const SizedBox(height: 16),
            Expanded(flex: 3, child: _buildVideoViewer()),

            // --- YENİ BÖLÜM ---
            const SizedBox(height: 16),
            _buildStatsPanel(), // <-- İstatistik paneli eklendi
            const SizedBox(height: 8),

            // --- YENİ BÖLÜM SONU ---
            Expanded(flex: 2, child: _buildLogPanel()),
          ],
        ),
      ),
    );
  }

  Widget _buildControlPanel() {
    if (_isCheckingNode) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_isNodeInstalled) {
      return Card(
        color: Colors.red.shade900,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 16),
              const Expanded(
                child: Text(
                  'HATA: Node.js sisteminizde bulunamadı. Lütfen kurun.',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: _launchNodeDownloadUrl,
                child: const Text('Node.js İndir'),
              ),
            ],
          ),
        ),
      );
    }
    return Row(
      children: [
        ElevatedButton.icon(
          onPressed: _isServerRunning ? _stopServer : _startServer,
          icon: Icon(_isServerRunning ? Icons.stop : Icons.play_arrow),
          label: Text(_isServerRunning ? 'Servisi Durdur' : 'Servisi Başlat'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _isServerRunning ? Colors.red : Colors.green,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            textStyle: const TextStyle(fontSize: 16),
          ),
        ),
        const SizedBox(width: 20),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _isServerRunning
                ? Colors.green.shade700
                : Colors.red.shade700,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            _isServerRunning ? 'DURUM: AKTİF' : 'DURUM: KAPALI',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.info_outline, color: Colors.white70),
          tooltip: 'OBS Kurulum Bilgisi',
          onPressed: _showObsInfoDialog,
        ),
      ],
    );
  }

  // --- YENİ WIDGET ---
  Widget _buildStatsPanel() {
    String qualityTag;
    Color tagColor;

    // FPS'e göre kaliteyi belirle
    if (_fps >= 25) {
      qualityTag = 'Harika';
      tagColor = Colors.green.shade400;
    } else if (_fps >= 15) {
      qualityTag = 'Orta';
      tagColor = Colors.orange.shade400;
    } else {
      qualityTag = 'Kötü';
      tagColor = Colors.red.shade400;
    }

    if (!_isServerRunning) {
      qualityTag = 'Çevrimdışı';
      tagColor = Colors.grey.shade600;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF374151), // AppBar rengiyle aynı
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Sol Taraf: FPS ve Kalite
          Row(
            children: [
              Text(
                'Akış Hızı: $_fps FPS',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: tagColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  qualityTag,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          // Sağ Taraf: Kaybedilen Kareler
          Text(
            'Kaybedilen (PC): $_droppedFrames',
            style: const TextStyle(fontSize: 14, color: Colors.white70),
          ),
        ],
      ),
    );
  }
  // --- YENİ WIDGET SONU ---

  Widget _buildVideoViewer() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.blueGrey, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: _latestImage == null
            ? const Text(
                'Akış bekleniyor...\n(Telefondan akışı başlattınız mı?)',
                textAlign: TextAlign.center,
              )
            : FittedBox(
                fit: BoxFit.contain,
                child: CustomPaint(
                  size: Size(
                    _latestImage!.width.toDouble(),
                    _latestImage!.height.toDouble(),
                  ),
                  painter: VideoPainter(_latestImage!),
                ),
              ),
      ),
    );
  }

  Widget _buildLogPanel() {
    return Container(
      padding: const EdgeInsets.all(10.0),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        border: Border.all(color: Colors.grey.shade700, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sunucu Logları:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.white,
            ),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              controller: _logScrollController,
              itemCount: _serverLogs.length,
              itemBuilder: (context, index) {
                final log = _serverLogs[index];
                Color logColor = Colors.grey.shade400;
                if (log.startsWith('HATA') || log.contains('HATA')) {
                  logColor = Colors.red.shade300;
                } else if (log.startsWith('[NODE]: [WS-')) {
                  logColor = Colors.cyan.shade300;
                }
                return Text(
                  log,
                  style: TextStyle(
                    fontFamily: 'Consolas',
                    fontSize: 12,
                    color: logColor,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class VideoPainter extends CustomPainter {
  final ui.Image image;
  final Paint _paint = Paint();
  VideoPainter(this.image);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, size.width, size.height),
      _paint,
    );
  }

  @override
  bool shouldRepaint(covariant VideoPainter oldDelegate) =>
      oldDelegate.image != image;
}
