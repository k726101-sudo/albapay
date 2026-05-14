import 'package:flutter/material.dart';
import '../theme/verify_theme.dart';

/// 전역 메타 데이터 홀더 — 4개 탭에서 공유
class VerifyMeta {
  static String firmName = '';
  static String workerName = '';
  static String workerNumber = '';
}

/// 업체명/직원명/사원번호 공통 입력 위젯
class VerifyMetaHeader extends StatefulWidget {
  const VerifyMetaHeader({super.key});

  @override
  State<VerifyMetaHeader> createState() => _VerifyMetaHeaderState();
}

class _VerifyMetaHeaderState extends State<VerifyMetaHeader> {
  final _firmCtrl = TextEditingController(text: VerifyMeta.firmName);
  final _nameCtrl = TextEditingController(text: VerifyMeta.workerName);
  final _numCtrl = TextEditingController(text: VerifyMeta.workerNumber);

  @override
  void dispose() {
    _firmCtrl.dispose();
    _nameCtrl.dispose();
    _numCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: VerifyTheme.bgCard.withValues(alpha: 0.6),
        border: Border(bottom: BorderSide(color: VerifyTheme.borderColor)),
      ),
      child: Row(
        children: [
          const Icon(Icons.business, size: 16, color: VerifyTheme.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: _miniField('업체명', _firmCtrl, (v) => VerifyMeta.firmName = v)),
          const SizedBox(width: 12),
          const Icon(Icons.person_outline, size: 16, color: VerifyTheme.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: _miniField('직원이름', _nameCtrl, (v) => VerifyMeta.workerName = v)),
          const SizedBox(width: 12),
          const Icon(Icons.badge_outlined, size: 16, color: VerifyTheme.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: _miniField('사원번호', _numCtrl, (v) => VerifyMeta.workerNumber = v)),
        ],
      ),
    );
  }

  Widget _miniField(String hint, TextEditingController ctrl, ValueChanged<String> onChanged) {
    return SizedBox(
      height: 36,
      child: TextField(
        controller: ctrl,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: VerifyTheme.textSecondary.withValues(alpha: 0.5), fontSize: 12),
          filled: true,
          fillColor: VerifyTheme.bgCardLight,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: VerifyTheme.borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: VerifyTheme.borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: VerifyTheme.accentPrimary),
          ),
        ),
      ),
    );
  }
}
