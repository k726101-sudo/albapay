import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_logic/shared_logic.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/store_info.dart';
import '../../services/boss_logout.dart';
import '../../services/worker_service.dart';
import '../login_screen.dart';

Future<void> _runSeedTestData(BuildContext context) async {
  if (!kDebugMode) return;
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || uid.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('로그인이 필요합니다.')),
    );
    return;
  }
  final storeId = await WorkerService.resolveStoreId();
  if (storeId.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('매장(storeId)을 찾을 수 없습니다.')),
    );
    return;
  }
  if (!context.mounted) return;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('테스트 데이터 생성'),
      content: const Text(
        'Firestore에 테스트 직원·근무표·출퇴근 샘플을 씁니다. (디버그 전용)\n'
        '알바 빠른 로그인: 초대코드 TST001, 전화 01000000001',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('생성')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    await TestDataSeeder(FirebaseFirestore.instance).seed(storeId: storeId);
    await WorkerService.syncFromFirebase();
    if (!context.mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('테스트 데이터를 생성했습니다.')),
    );
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('실패: $e')),
      );
    }
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _gpsEnabled = false;
  int _gpsRadius = 100;
  bool _gpsLoading = true;
  String? _storeId;

  @override
  void initState() {
    super.initState();
    _loadGpsSettings();
  }

  Future<void> _loadGpsSettings() async {
    try {
      final storeId = await WorkerService.resolveStoreId();
      if (storeId.isEmpty) {
        if (mounted) setState(() => _gpsLoading = false);
        return;
      }
      _storeId = storeId;
      final snap = await FirebaseFirestore.instance.collection('stores').doc(storeId).get();
      final data = snap.data() ?? {};
      if (mounted) {
        setState(() {
          _gpsEnabled = data['gpsAttendanceEnabled'] ?? false;
          _gpsRadius = (data['gpsRadius'] as num?)?.toInt() ?? 100;
          _gpsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  Future<void> _updateGpsSetting(String field, dynamic value) async {
    if (_storeId == null) return;
    await FirebaseFirestore.instance.collection('stores').doc(_storeId!).set(
      {field: value},
      SetOptions(merge: true),
    );
  }

  Future<void> _updateStoreLocationToCurrentPosition() async {
    if (_storeId == null) return;
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final req = await Geolocator.requestPermission();
        if (req == LocationPermission.denied || req == LocationPermission.deniedForever) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('위치 권한이 필요합니다. 설정에서 허용해 주세요.')),
            );
          }
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('위치 권한이 영구 거부되었습니다. 기기 설정에서 허용해 주세요.')),
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      await FirebaseFirestore.instance.collection('stores').doc(_storeId!).set(
        {'latitude': position.latitude, 'longitude': position.longitude},
        SetOptions(merge: true),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('매장 위치가 업데이트되었습니다. (${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)})')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('위치 가져오기 실패: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GPS 출퇴근 검증')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // ── GPS 출퇴근 검증 설정 ──
          if (_gpsLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            SwitchListTile(
              secondary: const Icon(Icons.location_on_outlined),
              title: const Text('GPS 출퇴근 검증'),
              subtitle: const Text('알바생 출근 시 매장 반경 내 위치 확인'),
              value: _gpsEnabled,
              onChanged: (v) {
                setState(() => _gpsEnabled = v);
                _updateGpsSetting('gpsAttendanceEnabled', v);
              },
            ),
            if (_gpsEnabled) ...[
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.radar, size: 20, color: Colors.blue),
                    const SizedBox(width: 8),
                    Text('허용 반경: ${_gpsRadius}m', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Slider(
                value: _gpsRadius.toDouble(),
                min: 50,
                max: 500,
                divisions: 18,
                label: '${_gpsRadius}m',
                onChanged: (v) => setState(() => _gpsRadius = v.round()),
                onChangeEnd: (v) => _updateGpsSetting('gpsRadius', v.round()),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text('50m', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    const Spacer(),
                    Text('500m', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OutlinedButton.icon(
                  onPressed: _updateStoreLocationToCurrentPosition,
                  icon: const Icon(Icons.my_location),
                  label: const Text('현재 위치를 매장 좌표로 설정'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 44),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.orange),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '매장에서 이 버튼을 눌러 좌표를 등록하세요.\n반경 밖 출근 시 사유 입력 후 허용됩니다.',
                          style: TextStyle(fontSize: 12, color: Colors.black87, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ],
        ],
      ),
    );
  }
}

class StoreAttendanceQrScreen extends StatefulWidget {
  const StoreAttendanceQrScreen({super.key});

  @override
  State<StoreAttendanceQrScreen> createState() => _StoreAttendanceQrScreenState();
}

class _StoreAttendanceQrScreenState extends State<StoreAttendanceQrScreen> {
  final GlobalKey _qrCaptureKey = GlobalKey();
  bool _busy = false;

  String _resolveStoreName() {
    final info = Hive.box<StoreInfo>('store').get('current');
    final name = info?.storeName.trim() ?? '';
    return name.isEmpty ? '파리바게뜨 개롱역점' : name;
  }

  String _resolveStoreId() {
    final workers = WorkerService.getAll();
    return workers
        .map((w) => w.storeId)
        .firstWhere((id) => id.trim().isNotEmpty, orElse: () => 'unknown_store');
  }

  String _buildQrUrl(String storeId) {
    final ts = AppClock.now().millisecondsSinceEpoch.toString();
    final seed = '$storeId|attendance|$ts|pb-manager-v1';
    final signature = sha256.convert(utf8.encode(seed)).toString().substring(0, 16);
    final uri = Uri(
      scheme: 'com.standard.albapay',
      host: 'attendance', // Custom App-only deep link
      queryParameters: {
        'storeId': storeId,
        'action': 'attendance',
        'ts': ts,
        'sig': signature,
      },
    );
    return uri.toString();
  }

  Future<Uint8List?> _captureQrPng() async {
    final context = _qrCaptureKey.currentContext;
    if (context == null) return null;
    final boundary = context.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3.0);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  Future<void> _saveToGallery(String storeName) async {
    setState(() => _busy = true);
    try {
      final bytes = await _captureQrPng();
      if (bytes == null) throw Exception('QR 캡처 실패');
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
        '${dir.path}/attendance_qr_${AppClock.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('QR 이미지 파일 저장 완료: ${file.path}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('저장에 실패했습니다. 다시 시도해 주세요.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareQr(String storeName) async {
    setState(() => _busy = true);
    try {
      final bytes = await _captureQrPng();
      if (bytes == null) throw Exception('QR 캡처 실패');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/attendance_qr_${AppClock.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes, flush: true);
      await SharePlus.instance.share(
        ShareParams(
          text: '$storeName 출퇴근용 QR 코드',
          files: [XFile(file.path)],
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _printA4QrCode(String storeName, String qrUrl) async {
    setState(() => _busy = true);
    try {
      final doc = pw.Document();
      final cmSq = 28.346;
      final cardWidth = 5.0 * cmSq;
      final cardHeight = 6.0 * cmSq;

      // 폰트는 NotoSansKR (로컬 에셋) 사용
      final fontData = await rootBundle.load("assets/fonts/NotoSansKR-Regular.ttf");
      final font = pw.Font.ttf(fontData);
      final boldFontData = await rootBundle.load("assets/fonts/NotoSansKR-Bold.ttf");
      final boldFont = pw.Font.ttf(boldFontData);

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.all(2 * cmSq),
          build: (pw.Context context) {
            
            pw.Widget buildCard() {
              return pw.Container(
                width: cardWidth,
                height: cardHeight,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(
                    color: const PdfColor.fromInt(0xFF999999), 
                    width: 0.5, 
                    style: pw.BorderStyle.dashed
                  ),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                padding: const pw.EdgeInsets.only(top: 14, left: 10, right: 10, bottom: 0),
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.start,
                  children: [
                    pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: qrUrl,
                      width: 100,
                      height: 100,
                    ),
                    pw.SizedBox(height: 12),
                    pw.Text(
                      storeName,
                      style: pw.TextStyle(font: boldFont, fontSize: 13),
                      maxLines: 1,
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      '카메라로 찍으면 즉시 출퇴근 기록이 됩니다',
                      style: pw.TextStyle(font: font, fontSize: 8.5, color: const PdfColor.fromInt(0xFF666666)),
                      textAlign: pw.TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            return pw.Center(
               child: pw.Wrap(
                 spacing: 2.5 * cmSq,   // 2.5cm 가로 간격
                 runSpacing: 2.5 * cmSq, // 2.5cm 세로 간격
                 alignment: pw.WrapAlignment.center,
                 crossAxisAlignment: pw.WrapCrossAlignment.center,
                 children: [buildCard(), buildCard(), buildCard(), buildCard()],
               ),
            );
          },
        ),
      );

      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => doc.save(),
        name: '출퇴근QR_$storeName.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('A4 인쇄 중 오류가 발생했습니다: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeName = _resolveStoreName();
    final storeId = _resolveStoreId();
    final qrUrl = _buildQrUrl(storeId);

    return Scaffold(
      appBar: AppBar(title: const Text('출퇴근용 QR 생성')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              RepaintBoundary(
                key: _qrCaptureKey,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x12000000),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      QrImageView(
                        data: qrUrl,
                        version: QrVersions.auto,
                        size: 240,
                        backgroundColor: Colors.white,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        storeName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '카메라로 찍으면 즉시 출퇴근 기록이 됩니다',
                        style: TextStyle(fontSize: 13, color: Colors.black54),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7FA),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'storeId: $storeId',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _saveToGallery(storeName),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('갤러리 저장'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : () => _shareQr(storeName),
                      icon: const Icon(Icons.share_rounded),
                      label: const Text('바로 공유'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _printA4QrCode(storeName, qrUrl),
                  icon: const Icon(Icons.print_rounded),
                  label: const Text('A4 용지로 인쇄하기 (QR 5x5cm 규격)'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
