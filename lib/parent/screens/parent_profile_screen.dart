import 'package:material_ui/material_ui.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_theme.dart';
import '../../features/auth/initial_session_wrapper.dart';
import '../../features/widgets/profile_editor_card.dart';

const Color parentTextPrimary = Colors.white;

class ParentProfileScreen extends StatefulWidget {
  const ParentProfileScreen({super.key});

  @override
  State<ParentProfileScreen> createState() => _ParentProfileScreenState();
}

class _ParentProfileScreenState extends State<ParentProfileScreen> {
  String _uid = '';
  String _name = '';
  String _role = 'Папа';
  String _birthDate = '';
  String _login = '';
  String _password = '';
  String _savedDbPassword = '';
  String _pin = '';
  String _avatarHash = '';
  bool _hasPinInDb = false;

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProfileData();
  }

  Future<void> _loadProfileData() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('user_uid') ?? '';

    String name = prefs.getString('user_name') ?? '';
    String role = prefs.getString('user_role') ?? 'Папа';
    String birthDate = prefs.getString('user_birth_date') ?? '';
    String avatarHash = prefs.getString('user_avatar_hash') ?? '';
    String login = '';
    String password = '';
    String pin = prefs.getString('saved_device_pin') ?? '';
    bool hasPin = pin.isNotEmpty;

    if (uid.isNotEmpty) {
      try {
        final snapshot =
            await FirebaseDatabase.instance.ref('users/$uid').get();
        if (snapshot.exists && snapshot.value != null) {
          final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
          name = data['name']?.toString() ?? name;
          role = data['familyRole']?.toString() ?? role;
          birthDate = data['birthDate']?.toString() ?? birthDate;
          login = data['login']?.toString() ?? '';
          password = data['password']?.toString() ?? '';
          avatarHash = data['avatarHash']?.toString() ?? avatarHash;
          if (data.containsKey('pin')) {
            hasPin = true;
            pin = data['pin']?.toString() ?? pin;
          }
        }
      } catch (e) {
        debugPrint('Ошибка загрузки профиля из БД: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      _uid = uid;
      _name = name;
      _role = role;
      _birthDate = birthDate;
      _login = login;
      _password = password;
      _savedDbPassword = password;
      _pin = pin;
      _hasPinInDb = hasPin;
      _avatarHash = avatarHash;
      _isLoading = false;
    });
  }

  Future<void> _saveProfile() async {
    if (_uid.isEmpty) return;
    setState(() => _isSaving = true);

    try {
      final updateMap = <String, dynamic>{
        'name': _name.trim(),
        'familyRole': _role,
        'birthDate': _birthDate,
        'login': _login.trim(),
        'password': _password.trim(),
        'avatarHash': _avatarHash,
      };
      if (_hasPinInDb) {
        updateMap['pin'] = _pin.trim();
      }

      await FirebaseDatabase.instance.ref('users/$_uid').update(updateMap);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_name', _name.trim());
      await prefs.setString('user_role', _role);
      await prefs.setString('user_birth_date', _birthDate);
      await prefs.setString('user_avatar_hash', _avatarHash);
      await prefs.setString('saved_device_uid', _uid);

      if (_hasPinInDb && _pin.trim().isNotEmpty) {
        await prefs.setString('saved_device_pin', _pin.trim());
      } else {
        await prefs.remove('saved_device_pin');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Данные профиля успешно сохранены')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка сохранения: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Диалог удаления профиля с подтверждением по паролю аккаунта
  void _confirmDeleteProfileWithPassword() {
    final confirmController = TextEditingController();
    final bool hasPassword = _savedDbPassword.isNotEmpty;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Expanded(child: Text('Удаление профиля')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasPassword
                  ? 'Это действие необратимо удалит ваш аккаунт из базы данных. Для подтверждения введите пароль от аккаунта:'
                  : 'Пароль аккаунта ещё не задан. Для подтверждения удаления введите слово УДАЛИТЬ:',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: confirmController,
              autofocus: true,
              obscureText: hasPassword,
              decoration: InputDecoration(
                labelText: hasPassword ? 'Пароль аккаунта' : 'Введите УДАЛИТЬ',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final entered = confirmController.text.trim();
              if (hasPassword) {
                if (entered != _savedDbPassword) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Неверный пароль!')),
                  );
                  return;
                }
              } else {
                if (entered.toUpperCase() != 'УДАЛИТЬ') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Введите слово УДАЛИТЬ для подтверждения',
                      ),
                    ),
                  );
                  return;
                }
              }

              Navigator.pop(dialogContext);
              _performDeleteProfile();
            },
            child: const Text('Удалить навсегда'),
          ),
        ],
      ),
    ).whenComplete(confirmController.dispose);
  }

  Future<void> _performDeleteProfile() async {
    final prefs = await SharedPreferences.getInstance();

    if (_uid.isNotEmpty) {
      try {
        final db = FirebaseDatabase.instance.ref();
        final userSnapshot = await db.child('users/$_uid').get();
        if (userSnapshot.exists && userSnapshot.value != null) {
          final userData = Map<dynamic, dynamic>.from(
            userSnapshot.value as Map,
          );
          final linkedParentUid = userData['linkedParent'];
          if (linkedParentUid != null) {
            await db.child('users/$linkedParentUid/linkedParent').remove();
          }
        }

        await db.child('users/$_uid').remove();
      } catch (e) {
        debugPrint('Ошибка при удалении профиля из БД: $e');
      }

      await prefs.remove('parent_profile_ready_$_uid');
    }

    await prefs.remove('user_type');
    await prefs.remove('user_uid');
    await prefs.remove('user_name');
    await prefs.remove('user_role');
    await prefs.remove('user_birth_date');
    await prefs.remove('user_avatar_hash');
    await prefs.remove('saved_device_uid');
    await prefs.remove('saved_device_pin');

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const InitialSessionWrapper()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            AppTheme.parentBackgroundAsset,
            fit: BoxFit.cover,
          ),
        ),
        Positioned.fill(
          child: Container(color: Colors.black.withValues(alpha: 0.45)),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
            title: const Text(
              'Профиль',
              style: TextStyle(
                color: parentTextPrimary,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          body: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: parentTextPrimary),
                )
              : SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    child: ProfileEditorCard(
                      name: _name,
                      role: _role,
                      birthDate: _birthDate,
                      login: _login,
                      password: _password,
                      pin: _pin,
                      avatarHash: _avatarHash,
                      showPinField: _hasPinInDb,
                      availableRoles: const ['Мама', 'Папа'],
                      defaultDisplayName: 'Родитель',
                      fallbackAvatarIcon: Icons.person,
                      accentColor: Colors.blue.shade700,
                      initialBirthDate: DateTime(now.year - 30, 1, 1),
                      firstBirthDate: DateTime(1940),
                      lastBirthDate: DateTime(now.year - 14),
                      isSaving: _isSaving,
                      onNameChanged: (v) => setState(() => _name = v),
                      onRoleChanged: (v) => setState(() => _role = v),
                      onBirthDateChanged: (v) => setState(() => _birthDate = v),
                      onLoginChanged: (v) => setState(() => _login = v),
                      onPasswordChanged: (v) => setState(() => _password = v),
                      onPinChanged: (v) => setState(() => _pin = v),
                      onAvatarChanged: (v) => setState(() => _avatarHash = v),
                      onSave: _saveProfile,
                      onClose: () => Navigator.pop(context),
                      onDelete: _confirmDeleteProfileWithPassword,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}