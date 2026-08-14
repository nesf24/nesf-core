import 'package:flutter/foundation.dart';

class SplashProvider extends ChangeNotifier {
  bool _showSplash = false;

  bool get showSplash => _showSplash;

  void show() {
    _showSplash = true;
    notifyListeners();
  }

  void hide() {
    _showSplash = false;
    notifyListeners();
  }
}
