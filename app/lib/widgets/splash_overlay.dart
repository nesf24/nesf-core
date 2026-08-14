import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/splash_provider.dart';
import 'animated_splash_widget.dart';

class SplashOverlay extends StatelessWidget {
  final Widget child;

  const SplashOverlay({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Consumer<SplashProvider>(
          builder: (context, splashProvider, _) {
            if (!splashProvider.showSplash) {
              return SizedBox.shrink();
            }

            return Positioned.fill(
              child: Material(
                color: Colors.white,
                child: AnimatedSplashWidget(
                  duration: Duration(milliseconds: 1500), // Faster for loading
                  onComplete: () {
                    splashProvider.hide();
                  },
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
