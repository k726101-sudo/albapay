import 'package:flutter/material.dart';

import 'main_screen.dart';

/// Legacy entry kept for backward compatibility.
/// Current dashboard root is `MainScreen`.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const MainScreen();
  }
}
