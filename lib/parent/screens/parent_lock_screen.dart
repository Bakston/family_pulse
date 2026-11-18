import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/services/parent_security_service.dart';
import '../../features/auth/initial_session_wrapper.dart';

class ParentLockScreen extends StatefulWidget {
  final Widget childDashboard;
  final bool forcePinSetup;

  const ParentLockScreen({
    super.key,
    required this.childDashboard,
    this.forcePinSetup = false,
  });

  @override
  State<ParentLockScreen> createState() => _ParentLockScreenState();
}

class _ParentLockScreenState extends State<ParentLockScreen> {
  String _enteredPin = '';
  String? _errorText;
  bool _isHardwareBioSupported = false;
  bool _biometricEnabled = true;
  bool _isSettingNewPin = false;
  String? _firstPinDraft;

  @override
  void initState() {
    super.initState();
    _initSecurity();
  }

  Future<void> _initSecurity() async {
    final hasPin = await ParentSecurityService.hasPin();
    final bioAvailable = await ParentSecurityService.isBiometricAvailable();
    final bioEnabled = await ParentSecurityService.isBiometricEnabled();

    if (!mounted) return;
    final needSetup = widget.forcePinSetup || !hasPin;

    setState(() {
      _isHardwareBioSupported = bioAvailable;
      _biometricEnabled = bioEnabled;
      _isSettingNewPin = needSetup;
    });

    if (!needSetup && bioAvailable && bioEnabled) {
      _triggerBiometrics();
    }
  }

  Future<void> _triggerBiometrics() async {
    final ok = await ParentSecurityService.authenticateWithBiometrics();
    if (ok && mounted) {
      _openDashboard();
    }
  }

  void _openDashboard() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => widget.childDashboard),
    );
  }

  Future<void> _onDigitTap(String digit) async {
    if (_enteredPin.length >= 4) return;
    setState(() {
      _enteredPin += digit;
      _errorText = null;
    });

    if (_enteredPin.length == 4) {
      if (_isSettingNewPin) {
        if (_firstPinDraft == null) {
          setState(() {
            _firstPinDraft = _enteredPin;
            _enteredPin = '';
          });
        } else if (_firstPinDraft == _enteredPin) {
          await ParentSecurityService.savePin(_enteredPin);
          await ParentSecurityService.setBiometricEnabled(_biometricEnabled);
          if (mounted) _openDashboard();
        } else {
          setState(() {
            _firstPinDraft = null;
            _enteredPin = '';
            _errorText = 'ПИН-коды не совпали. Попробуйте снова';
          });
        }
      } else {
        final valid = await ParentSecurityService.verifyPin(_enteredPin);
        if (valid && mounted) {
          _openDashboard();
        } else {
          setState(() {
            _enteredPin = '';
            _errorText = 'Неверный ПИН-код';
          });
        }
      }
    }
  }

  Future<void> _switchToPasswordLogin() async {
    await ParentSecurityService.clearPin();
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const InitialSessionWrapper()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _isSettingNewPin
        ? (_firstPinDraft == null ? 'Создайте ПИН-код родителя' : 'Повторите ПИН-код')
        : 'Вход в панель родителя';

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/background_parents.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_outline, size: 48, color: Colors.white),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (i) {
                  final filled = i < _enteredPin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? Colors.white : Colors.white24,
                    ),
                  );
                }),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 12),
                Text(_errorText!, style: const TextStyle(color: Colors.redAccent)),
              ],
              if (_isSettingNewPin && _isHardwareBioSupported) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: SwitchListTile.adaptive(
                    value: _biometricEnabled,
                    onChanged: (val) => setState(() => _biometricEnabled = val),
                    title: const Text(
                      'Входить по отпечатку / Face ID',
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                    activeTrackColor: Colors.greenAccent,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              _buildKeypad(),
              const SizedBox(height: 20),
              if (!widget.forcePinSetup)
                TextButton(
                  onPressed: _switchToPasswordLogin,
                  child: const Text(
                    'Войти по логину и паролю',
                    style: TextStyle(
                      color: Colors.white70,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeypad() {
    final showBioButton = !_isSettingNewPin && _isHardwareBioSupported && _biometricEnabled;
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      [showBioButton ? 'BIO' : '', '0', 'DEL'],
    ];

    return Column(
      children: rows.map((row) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: row.map((key) {
            if (key.isEmpty) return const SizedBox(width: 84, height: 72);
            return Padding(
              padding: const EdgeInsets.all(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(36),
                onTap: () {
                  if (key == 'DEL') {
                    if (_enteredPin.isNotEmpty) {
                      setState(() => _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1));
                    }
                  } else if (key == 'BIO') {
                    _triggerBiometrics();
                  } else {
                    _onDigitTap(key);
                  }
                },
                child: Container(
                  width: 72,
                  height: 72,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                  child: key == 'DEL'
                      ? const Icon(Icons.backspace_outlined, color: Colors.white)
                      : key == 'BIO'
                          ? const Icon(Icons.fingerprint, size: 32, color: Colors.white)
                          : Text(key, style: const TextStyle(fontSize: 26, color: Colors.white)),
                ),
              ),
            );
          }).toList(),
        );
      }).toList(),
    );
  }
}