import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_theme.dart';
import '../../core/services/parent_security_service.dart';
import '../../parent/screens/parent_panel_screen.dart';
import '../../child/screens/child_join_screen.dart';
import '../../features/widgets/family_calendar_widget.dart';

// Глобальные дизайн-константы в стиле стекломорфизма
const Color parentGlassPanel = Color(0x33FFFFFF);
const Color parentTextPrimary = Colors.white;

void _hideAndroidNavigationBar() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
}

/// Обёртка с фирменным фоном для стартовых экранов
class AppBackgroundWrapper extends StatelessWidget {
  final Widget child;
  final PreferredSizeWidget? appBar;

  const AppBackgroundWrapper({super.key, required this.child, this.appBar});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            AppTheme.parentBackgroundAsset,
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
        ),
        Positioned.fill(
          child: Container(
            color: Colors.black.withValues(alpha: 0.45),
          ),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: appBar,
          body: SafeArea(child: child),
        ),
      ],
    );
  }
}

/// Экран выбора режима: отступы по 100px от верхнего и нижнего краёв, в центре — «РЕБЁНОК» и «РОДИТЕЛЬ»
class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({super.key});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hideAndroidNavigationBar();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _hideAndroidNavigationBar();
    }
  }

  ButtonStyle _roleButtonStyle() {
    return ElevatedButton.styleFrom(
      minimumSize: const Size(240, 64),
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      backgroundColor: parentGlassPanel,
      foregroundColor: parentTextPrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(32),
        side: BorderSide(
          color: Colors.white.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppBackgroundWrapper(
      child: SizedBox.expand(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 100),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                style: _roleButtonStyle(),
                icon: const Icon(
                  Icons.child_care,
                  size: 28,
                  color: parentTextPrimary,
                ),
                label: const Text(
                  'РЕБЁНОК',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: parentTextPrimary,
                  ),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ChildJoinScreen(),
                    ),
                  );
                },
              ),
              ElevatedButton.icon(
                style: _roleButtonStyle(),
                icon: const Icon(
                  Icons.admin_panel_settings,
                  size: 28,
                  color: parentTextPrimary,
                ),
                label: const Text(
                  'РОДИТЕЛЬ',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: parentTextPrimary,
                  ),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ParentRegistrationScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Экран авторизации по логину и паролю
class PasswordLoginScreen extends StatefulWidget {
  const PasswordLoginScreen({super.key});

  @override
  State<PasswordLoginScreen> createState() => _PasswordLoginScreenState();
}

class _PasswordLoginScreenState extends State<PasswordLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _loginController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _hideAndroidNavigationBar();
  }

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loginWithCredentials() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final enteredLogin = _loginController.text.trim();
      final enteredPassword = _passwordController.text.trim();

      final snapshot = await FirebaseDatabase.instance.ref('users').get();
      if (!snapshot.exists || snapshot.value == null) {
        throw Exception('Пользователи не найдены');
      }

      final usersMap = Map<dynamic, dynamic>.from(snapshot.value as Map);
      String? foundUid;
      Map<dynamic, dynamic>? foundUserData;

      usersMap.forEach((key, value) {
        final userData = Map<dynamic, dynamic>.from(value);
        if (userData['login']?.toString() == enteredLogin &&
            userData['password']?.toString() == enteredPassword) {
          foundUid = key.toString();
          foundUserData = userData;
        }
      });

      if (foundUid == null || foundUserData == null) {
        throw Exception('Неверный логин или пароль');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_type', 'parent');
      await prefs.setString('user_uid', foundUid!);
      await prefs.setString('saved_device_uid', foundUid!);
      await prefs.setString(
        'user_name',
        foundUserData!['name']?.toString() ?? 'Родитель',
      );
      await prefs.setString(
        'user_role',
        foundUserData!['familyRole']?.toString() ?? 'Родитель',
      );
      await prefs.setString(
        'user_birth_date',
        foundUserData!['birthDate']?.toString() ?? '',
      );
      await prefs.setString(
        'user_avatar_hash',
        foundUserData!['avatarHash']?.toString() ?? '',
      );
      await prefs.setBool('parent_profile_ready_$foundUid', true);

      final userPin = foundUserData!['pin']?.toString().trim() ?? '';
      if (userPin.length == 4) {
        await ParentSecurityService.savePin(userPin);
      } else {
        ParentSecurityService.isSessionUnlocked = true;
      }

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const ParentPanelScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBackgroundWrapper(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Авторизация',
          style: TextStyle(color: parentTextPrimary),
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 8,
            color: Colors.white.withValues(alpha: 0.92),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Вход в аккаунт',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _loginController,
                      decoration: InputDecoration(
                        labelText: 'Логин',
                        prefixIcon: const Icon(Icons.person),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Введите логин' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Пароль',
                        prefixIcon: const Icon(Icons.lock),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Введите пароль' : null,
                    ),
                    const SizedBox(height: 28),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      onPressed: _isLoading ? null : _loginWithCredentials,
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'ВОЙТИ',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Анкета Родителя: СОЗДАТЬ, У МЕНЯ ЕСТЬ ПРОФИЛЬ, ОТМЕНА
class ParentRegistrationScreen extends StatefulWidget {
  const ParentRegistrationScreen({super.key});

  @override
  State<ParentRegistrationScreen> createState() =>
      _ParentRegistrationScreenState();
}

class _ParentRegistrationScreenState extends State<ParentRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameController = TextEditingController();
  String _selectedRole = 'Папа';
  DateTime? _selectedBirthDate;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _hideAndroidNavigationBar();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await FamilyCalendarWidget.showPickerDialog(
      context: context,
      initialDate: _selectedBirthDate ?? DateTime(now.year - 30, 1, 1),
      firstDate: DateTime(1940),
      lastDate: DateTime(now.year - 14),
      title: 'Дата рождения',
    );

    if (picked != null && mounted) {
      setState(() {
        _selectedBirthDate = picked;
      });
    }
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day.$month.${date.year}';
  }

  Future<void> _createParentProfile() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedBirthDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пожалуйста, укажите дату рождения')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final newRef = FirebaseDatabase.instance.ref('users').push();
      final String generatedUid =
          newRef.key ?? 'parent_${DateTime.now().millisecondsSinceEpoch}';

      final String name = _nameController.text.trim();
      final String birthDateStr = _formatDate(_selectedBirthDate!);

      await newRef.set({
        'uid': generatedUid,
        'name': name,
        'familyRole': _selectedRole,
        'birthDate': birthDateStr,
        'createdAt': ServerValue.timestamp,
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_type', 'parent');
      await prefs.setString('user_uid', generatedUid);
      await prefs.setString('saved_device_uid', generatedUid);
      await prefs.setString('user_name', name);
      await prefs.setString('user_role', _selectedRole);
      await prefs.setString('user_birth_date', birthDateStr);
      await prefs.setBool('parent_profile_ready_$generatedUid', true);
      ParentSecurityService.isSessionUnlocked = true;

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const ParentPanelScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка создания профиля: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBackgroundWrapper(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Анкета родителя',
          style: TextStyle(color: parentTextPrimary),
        ),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12.0),
          child: Card(
            elevation: 8,
            color: Colors.white.withValues(alpha: 0.92),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Создание профиля',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 20),

                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Ваше имя',
                        prefixIcon: const Icon(Icons.person),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Введите имя';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    DropdownButtonFormField<String>(
                      initialValue: _selectedRole,
                      decoration: InputDecoration(
                        labelText: 'Роль в семье',
                        prefixIcon: const Icon(Icons.supervisor_account),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Мама', child: Text('Мама')),
                        DropdownMenuItem(value: 'Папа', child: Text('Папа')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedRole = value);
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    InkWell(
                      onTap: _pickBirthDate,
                      borderRadius: BorderRadius.circular(30),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: 'Дата рождения',
                          prefixIcon: const Icon(Icons.cake),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: Text(
                          _selectedBirthDate == null
                              ? 'Календарь'
                              : _formatDate(_selectedBirthDate!),
                          style: TextStyle(
                            fontSize: 16,
                            color: _selectedBirthDate == null
                                ? Colors.grey.shade600
                                : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Кнопка СОЗДАТЬ
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      onPressed: _isSaving ? null : _createParentProfile,
                      child: _isSaving
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'СОЗДАТЬ',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                    const SizedBox(height: 10),

                    // Кнопка У МЕНЯ ЕСТЬ ПРОФИЛЬ -> Авторизация по логину и паролю
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        foregroundColor: Colors.blue.shade800,
                        side: BorderSide(color: Colors.blue.shade700),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      icon: const Icon(Icons.login, size: 20),
                      label: const Text(
                        'У МЕНЯ ЕСТЬ ПРОФИЛЬ',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: _isSaving
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const PasswordLoginScreen(),
                                ),
                              );
                            },
                    ),
                    const SizedBox(height: 6),

                    // Кнопка ОТМЕНА
                    TextButton(
                      onPressed: _isSaving ? null : () => Navigator.pop(context),
                      child: const Text(
                        'ОТМЕНА',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}