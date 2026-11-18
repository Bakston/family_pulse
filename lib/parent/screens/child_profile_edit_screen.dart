import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_theme.dart';
import '../../features/widgets/profile_editor_card.dart';

const Color parentTextPrimary = Colors.white;

class ChildProfileEditScreen extends StatefulWidget {
  final String childId;

  const ChildProfileEditScreen({
    super.key,
    required this.childId,
  });

  @override
  State<ChildProfileEditScreen> createState() => _ChildProfileEditScreenState();
}

class _ChildProfileEditScreenState extends State<ChildProfileEditScreen> {
  String _name = '';
  String _role = 'Сын';
  String _birthDate = '';
  String _login = '';
  String _password = '';
  String _pin = '';
  String _avatarHash = '';
  bool _hasPinInDb = false;

  String _parentUid = '';
  String _parentPassword = '';

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadChildData();
  }

  Future<void> _loadChildData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentParentUid = prefs.getString('user_uid') ?? '';

      final snapshot = await FirebaseDatabase.instance
          .ref('children/${widget.childId}')
          .get();

      if (snapshot.exists && snapshot.value != null) {
        final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
        final ownerParentUid = currentParentUid.isNotEmpty
            ? currentParentUid
            : (data['parentUid']?.toString() ?? '');

        String parentPwd = '';
        if (ownerParentUid.isNotEmpty) {
          final parentSnap = await FirebaseDatabase.instance
              .ref('users/$ownerParentUid/password')
              .get();
          if (parentSnap.exists && parentSnap.value != null) {
            parentPwd = parentSnap.value.toString();
          }
        }

        if (!mounted) return;
        setState(() {
          _name = data['name']?.toString() ?? '';
          _role = data['familyRole']?.toString() ?? 'Сын';
          _birthDate = data['birthDate']?.toString() ?? '';
          _login = data['login']?.toString() ?? '';
          _password = data['password']?.toString() ?? '';
          _avatarHash = data['avatarHash']?.toString() ?? '';
          _hasPinInDb = data.containsKey('pin') &&
              data['pin'] != null &&
              data['pin'].toString().isNotEmpty;
          _pin = _hasPinInDb ? data['pin'].toString() : '';
          _parentUid = ownerParentUid;
          _parentPassword = parentPwd;
          _isLoading = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('Ошибка загрузки профиля ребёнка: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveChildProfile() async {
    if (_name.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Имя ребёнка не может быть пустым')),
      );
      return;
    }

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

      await FirebaseDatabase.instance
          .ref('children/${widget.childId}')
          .update(updateMap);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Профиль ребёнка успешно обновлён')),
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

  /// Диалог удаления профиля ребёнка с подтверждением по паролю родителя
  void _confirmDeleteChild() {
    final confirmController = TextEditingController();
    final bool hasParentPassword =
        _parentUid.isNotEmpty && _parentPassword.isNotEmpty;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Expanded(child: Text('Удаление профиля ребёнка')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              hasParentPassword
                  ? 'Профиль «$_name» и вся история привязки будут удалены из семьи. Для подтверждения введите пароль родителя:'
                  : 'Профиль «$_name» и вся история привязки будут удалены из семьи. Для подтверждения введите слово УДАЛИТЬ:',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: confirmController,
              autofocus: true,
              obscureText: hasParentPassword,
              decoration: InputDecoration(
                labelText:
                    hasParentPassword ? 'Пароль родителя' : 'Введите УДАЛИТЬ',
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
            onPressed: () async {
              final entered = confirmController.text.trim();
              if (hasParentPassword) {
                if (entered != _parentPassword) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Неверный пароль родителя!')),
                  );
                  return;
                }
              } else {
                if (entered.toUpperCase() != 'УДАЛИТЬ') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Введите слово УДАЛИТЬ для подтверждения'),
                    ),
                  );
                  return;
                }
              }

              Navigator.pop(dialogContext);
              await _performDeleteChild();
            },
            child: const Text('Удалить навсегда'),
          ),
        ],
      ),
    ).whenComplete(confirmController.dispose);
  }

  Future<void> _performDeleteChild() async {
    try {
      await FirebaseDatabase.instance
          .ref('children/${widget.childId}')
          .remove();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Профиль ребёнка удалён')),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка при удалении: $e')),
      );
    }
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
          child: Container(
            color: Colors.black.withValues(alpha: 0.45),
          ),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            automaticallyImplyLeading: false,
            title: const Text(
              'Профиль ребёнка',
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
                      availableRoles: const ['Сын', 'Дочь'],
                      defaultDisplayName: 'Ребёнок',
                      fallbackAvatarIcon: Icons.child_care,
                      accentColor: Colors.purple.shade600,
                      initialBirthDate: DateTime(now.year - 10, 1, 1),
                      firstBirthDate: DateTime(2000),
                      lastBirthDate: now,
                      isSaving: _isSaving,
                      onNameChanged: (v) => setState(() => _name = v),
                      onRoleChanged: (v) => setState(() => _role = v),
                      onBirthDateChanged: (v) => setState(() => _birthDate = v),
                      onLoginChanged: (v) => setState(() => _login = v),
                      onPasswordChanged: (v) => setState(() => _password = v),
                      onPinChanged: (v) => setState(() => _pin = v),
                      onAvatarChanged: (v) => setState(() => _avatarHash = v),
                      onSave: _saveChildProfile,
                      onClose: () => Navigator.pop(context),
                      onDelete: _confirmDeleteChild,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}