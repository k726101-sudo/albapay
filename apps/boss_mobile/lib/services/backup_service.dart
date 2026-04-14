import 'dart:io';
import 'package:archive/archive.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_logic/shared_logic.dart';

class BackupService {
  static const String _backupFileName = 'albapay_backup.enc';
  static const String _backupPassword = 'albapay_boss_secure_key'; 

  // --- Test Flags ---
  static bool isTestMode = false;
  static bool testMockExportFailure = false;
  static List<Map<String, dynamic>> testExportedLogs = [];

  /// 수동 백업: 로컬 DB를 압축 및 암호화하여 공유(저장)합니다.
  static Future<void> runBackup({bool silent = false}) async {
    final prefs = await SharedPreferences.getInstance();

    try {
      final zipBytes = await _createBackupZip();
      final encryptedBytes = _encryptData(zipBytes, _backupPassword);

      final tempDir = await getTemporaryDirectory();
      final file = File(p.join(tempDir.path, _backupFileName));
      await file.writeAsBytes(encryptedBytes);

      if (!silent) {
        // OS 기본 공유 다이얼로그 호출 (파일 저장, 카카오톡 전송 등 가능)
        final result = await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            text: '알바급여정석 백업 파일입니다. 안전한 곳에 보관해 주세요.',
          ),
        );
        
        if (result.status == ShareResultStatus.success) {
          await prefs.setString('last_backup_success', AppClock.now().toIso8601String());
          await prefs.setInt('backup_failure_count', 0);
          debugPrint('Backup shared successfully');
        } else {
          throw Exception('백업 파일 저장이 취소되었거나 실패했습니다.');
        }
      } else {
        // 무음 백업은 문서 디렉토리에 조용히 저장합니다 (단기 보관용)
        final docDir = await getApplicationDocumentsDirectory();
        final docFile = File(p.join(docDir.path, _backupFileName));
        if (await docFile.exists()) await docFile.delete();
        await file.copy(docFile.path);
        
        await prefs.setString('last_backup_success', AppClock.now().toIso8601String());
        await prefs.setInt('backup_failure_count', 0);
      }
    } catch (e) {
      final failureCount = (prefs.getInt('backup_failure_count') ?? 0) + 1;
      await prefs.setInt('backup_failure_count', failureCount);
      debugPrint('Backup failed ($failureCount): $e');
      rethrow;
    }
  }

  /// 수동 복원: 사장님이 폰에 저장된 백업 파일(.enc)을 직접 선택하여 복원합니다.
  static Future<void> restoreFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any, // .enc 확장은 any로 잡아야 안전함
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) {
      throw Exception('파일 선택이 취소되었습니다.');
    }

    final filePath = result.files.first.path;
    if (filePath == null) {
      throw Exception('파일의 경로를 읽을 수 없습니다.');
    }

    final file = File(filePath);
    final encryptedBytes = await file.readAsBytes();

    final zipBytes = _decryptData(encryptedBytes, _backupPassword);
    await _restoreFromZip(zipBytes);
  }

  /// 서버 만료 데이터 내보내기용 (내부 스토리지 보관 방식)
  static Future<void> exportData(Uint8List bytes, String fileName) async {
    if (testMockExportFailure) throw Exception("Testing scenario: Simulated Export Failure");
    if (isTestMode) {
      testExportedLogs.add({"fileName": fileName, "bytes": bytes});
      return;
    }

    final encryptedBytes = _encryptData(bytes, _backupPassword);
    final docDir = await getApplicationDocumentsDirectory();
    final archiveDir = Directory(p.join(docDir.path, 'archives'));
    if (!await archiveDir.exists()) {
      await archiveDir.create();
    }
    
    final targetFile = File(p.join(archiveDir.path, fileName));
    await targetFile.writeAsBytes(encryptedBytes);
  }

  static Future<Uint8List> _createBackupZip() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final files = appDocDir.listSync(recursive: false);
    
    final archive = Archive();
    for (var file in files) {
      if (file is File && (file.path.endsWith('.hive') || file.path.endsWith('.lock'))) {
        final bytes = file.readAsBytesSync();
        final fileName = p.basename(file.path);
        archive.addFile(ArchiveFile(fileName, bytes.length, bytes));
      }
    }
    
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  static Uint8List _encryptData(Uint8List data, String password) {
    final key = enc.Key.fromUtf8(password.padRight(32).substring(0, 32));
    final iv = enc.IV.fromLength(16);
    final encrypter = enc.Encrypter(enc.AES(key));
    final encrypted = encrypter.encryptBytes(data, iv: iv);
    final combined = Uint8List(iv.bytes.length + encrypted.bytes.length);
    combined.setAll(0, iv.bytes);
    combined.setAll(iv.bytes.length, encrypted.bytes);
    return combined;
  }

  static Uint8List _decryptData(Uint8List combined, String password) {
    final key = enc.Key.fromUtf8(password.padRight(32).substring(0, 32));
    final iv = enc.IV(combined.sublist(0, 16));
    final encryptedBytes = combined.sublist(16);
    final encrypter = enc.Encrypter(enc.AES(key));
    return Uint8List.fromList(encrypter.decryptBytes(enc.Encrypted(encryptedBytes), iv: iv));
  }

  static Future<void> _restoreFromZip(Uint8List zipBytes) async {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final appDocDir = await getApplicationDocumentsDirectory();

    for (final file in archive) {
      final filename = file.name;
      final data = file.content as List<int>;
      File(p.join(appDocDir.path, filename)).writeAsBytesSync(data);
    }
  }
}
