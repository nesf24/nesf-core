import 'package:flutter/material.dart';

import '../theme.dart';

/// Shown while the stored session is restored. Deliberately minimal — it is on
/// screen for a fraction of a second on a warm start.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NesfColors.green,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Image.asset('assets/logo.png', width: 76, height: 76),
            ),
            const SizedBox(height: 22),
            const Text(
              'NESF Core',
              style: TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'The NE Sports Foundation',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13),
            ),
            const SizedBox(height: 34),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
