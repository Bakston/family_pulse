import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ParentSecurityService {
  static const String _pinKey = 'parent_security_pin';
  static const String _biometricEnabledKey = 'parent_biometric_enabled';

  static final LocalAuthentication _auth = LocalAuthentication();

  /// Флаг живёт только в оперативной памяти: при смахивании приложения
  /// процесс убивается, и при следующем запуске флаг снова равен false.
  static bool isSessionUnlocked = false;

  static Future<bool> hasPin() async {
    final prefs = await SharedPreferences.getInstance();
    final pin = prefs.getString(_pinKey);
    return pin != null && pin.length == 4;
  }

  static Future<void> savePin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pinKey, pin);
    isSessionUnlocked = true;
  }

  static Future<bool> verifyPin(String inputPin) async {
    final prefs = await SharedPreferences.getInstance();
    final savedPin = prefs.getString(_pinKey);
    if (savedPin != null && savedPin == inputPin) {
      isSessionUnlocked = true;
      return true;
    }
    return false;
  }

  static Future<void> clearPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pinKey);
    isSessionUnlocked = false;
  }

  static Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _auth.canCheckBiometrics;
      final isSupported = await _auth.isDeviceSupported();
      return canCheck && isSupported;
    } on PlatformException {
      return false;
    }
  }

  static Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricEnabledKey) ?? true;
  }

  static Future<void> setBiometricEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_biometricEnabledKey, value);
  }

  static Future<bool> authenticateWithBiometrics() async {
    try {
      final didAuthenticate = await _auth.authenticate(
        localizedReason: 'Подтвердите личность для входа в панель родителя',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
      if (didAuthenticate) {
        isSessionUnlocked = true;
      }
      return didAuthenticate;
    } on PlatformException {
      return false;
    }
  }
}