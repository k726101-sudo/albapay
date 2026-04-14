import 'package:flutter/widgets.dart';
import '../services/health_certificate_alert_service.dart';

class HealthCertificateAlertRunner extends StatefulWidget {
  final String storeId;
  const HealthCertificateAlertRunner({super.key, required this.storeId});

  @override
  State<HealthCertificateAlertRunner> createState() =>
      _HealthCertificateAlertRunnerState();
}

class _HealthCertificateAlertRunnerState
    extends State<HealthCertificateAlertRunner> {
  bool _ran = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ran) return;
    _ran = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await HealthCertificateAlertService().syncAlerts(storeId: widget.storeId);
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

