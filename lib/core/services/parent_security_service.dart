import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ParentSecurityService {
  static const String _pinKey = 'parent_security_pin';
  static const String _backupPinKey = 'saved_device_pin';
  static const String _biometricEnabledKey = 'parent_biometric_enabled';

  static final LocalAuthentication _auth = LocalAuthentication();

  /// Флаг живёт только в оперативной памяти: при смахивании приложения
  /// процесс убивается, и при следующем запуске флаг снова равен false.
  static bool isSessionUnlocked = false;

  static Future<bool> hasPin() async {
    final prefs = await SharedPreferences.getInstance();
    var pin = prefs.getString(_pinKey);
    if (pin == null || pin.length != 4) {
      final backupPin = prefs.getString(_backupPinKey);
      if (backupPin != null && backupPin.length == 4) {
        await prefs.setString(_pinKey, backupPin);
        pin = backupPin;
      }
    }
    return pin != null && pin.length == 4;
  }

  static Future<void> savePin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pinKey, pin);
    await prefs.setString(_backupPinKey, pin);
    isSessionUnlocked = true;
  }

  static Future<bool> verifyPin(String inputPin) async {
    final prefs = await SharedPreferences.getInstance();
    final savedPin = prefs.getString(_pinKey) ?? prefs.getString(_backupPinKey);
    if (savedPin != null && savedPin == inputPin) {
      await prefs.setString(_pinKey, savedPin);
      isSessionUnlocked = true;
      return true;
    }
    return false;
  }

  static Future<void> clearPin({bool clearBackup = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pinKey);
    if (clearBackup) {
      await prefs.remove(_backupPinKey);
    }
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
        localizedReason: '',
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'Вход в FamilyPulse',
            biometricRequiredTitle: '',
            biometricHint: '',
            cancelButton: 'Отмена',
          ),
        ],
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