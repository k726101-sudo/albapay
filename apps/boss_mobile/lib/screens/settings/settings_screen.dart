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

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          const ListTile(
            leading: Icon(Icons.person_outline),
            title: Text('내 프로필'),
          ),
          const ListTile(
            leading: Icon(Icons.notifications_none),
            title: Text('알림 설정'),
          ),
          ListTile(
            leading: const Icon(Icons.qr_code_2_rounded),
            title: const Text('출퇴근용 QR 생성'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const StoreAttendanceQrScreen()),
              );
            },
          ),
          const Divider(),
          if (kDebugMode) ...[
            ListTile(
              leading: const Icon(Icons.bug_report_outlined, color: Color(0xFF6D4C41)),
              title: const Text('테스트 데이터 생성'),
              subtitle: const Text('직원 5명·이번 주 근무표·지난주 출퇴근 20건을 Firestore에 넣습니다.'),
              onTap: () => _runSeedTestData(context),
            ),
          ],
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('로그아웃', style: TextStyle(color: Colors.red)),
            onTap: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('로그아웃'),
                  content: const Text('정말 로그아웃 하시겠습니까?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('확인', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );

              if (confirm == true) {
                await performBossLogout(authService);
                if (context.mounted) {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                    (route) => false,
                  );
                }
              }
            },
          ),
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
      scheme: 'https',
      host: 'standard-albapay.web.app',
      path: '/',
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
      // 1 cm = 약 28.346 points 이므로 5cm x 5cm 설정
      final qrSize = 5.0 * 28.346;
      // 로컬 에셋에서 폰트 로드 (PdfGoogleFonts 에러 방지 및 오프라인 지원)
      final fontData = await rootBundle.load("assets/fonts/NotoSansKR-Regular.ttf");
      final font = pw.Font.ttf(fontData);
      final boldFontData = await rootBundle.load("assets/fonts/NotoSansKR-Bold.ttf");
      final boldFont = pw.Font.ttf(boldFontData);

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(
                    storeName,
                    style: pw.TextStyle(font: boldFont, fontSize: 32),
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text(
                    '출퇴근 기록용 QR 코드',
                    style: pw.TextStyle(font: font, fontSize: 24),
                  ),
                  pw.SizedBox(height: 40),
                  // 정확히 5cm x 5cm 강제 고정
                  pw.Container(
                    width: qrSize,
                    height: qrSize,
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: qrUrl,
                      width: qrSize,
                      height: qrSize,
                    ),
                  ),
                  pw.SizedBox(height: 40),
                  pw.Text(
                    '알바급여정석 알바용 앱에서 카메라로 스캔하여 출퇴근을 기록하세요.',
                    style: pw.TextStyle(font: font, fontSize: 14, color: const PdfColor.fromInt(0xFF555555)),
                  ),
                ],
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
