import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../child/screens/child_panel_screen.dart';
import '../../core/services/parent_security_service.dart';
import '../../parent/screens/parent_lock_screen.dart';
import '../../parent/screens/parent_panel_screen.dart';
import 'welcome_screen.dart';

class InitialSessionWrapper extends StatefulWidget {
  const InitialSessionWrapper({super.key});

  @override
  State<InitialSessionWrapper> createState() => _InitialSessionWrapperState();
}

class _InitialSessionWrapperState extends State<InitialSessionWrapper> {
  bool _isLoading = true;
  String? _userType;
  String? _userUid;
  String? _childId;
  String _childName = 'Ребёнок';

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final prefs = await SharedPreferences.getInstance();
    var userType = prefs.getString('user_type');
    var userUid = prefs.getString('user_uid');

    // Если родитель вышел через "Войти по логину и паролю" (FirebaseAuth.signOut),
    // очищаем сохраненную сессию, чтобы открыть экран входа.
    if (userType == 'parent' && FirebaseAuth.instance.currentUser == null) {
      await prefs.remove('user_type');
      await prefs.remove('user_uid');
      userType = null;
      userUid = null;
    }

    // Поддерживаем актуальный ключ 'saved_child_id' и резервный 'child_id'
    final childId = prefs.getString('saved_child_id') ?? prefs.getString('child_id');
    final childName = prefs.getString('saved_child_name') ?? 'Ребёнок';

    if (!mounted) return;
    setState(() {
      _userType = userType;
      _userUid = userUid;
      _childId = childId;
      _childName = childName;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Если устройство настроено как Родитель — проверяем разблокировку текущей сессии
    if (_userType == 'parent' && _userUid != null && _userUid!.isNotEmpty) {
      if (ParentSecurityService.isSessionUnlocked) {
        return const ParentPanelScreen();
      }
      return const ParentLockScreen(
        childDashboard: ParentPanelScreen(),
      );
    }

    // Если устройство настроено как Ребёнок
    if (_userType == 'child' && _childId != null && _childId!.isNotEmpty) {
      return ChildPanelScreen(childName: _childName);
    }

    // Если сессии нет — показываем главное меню с кнопкой "МОЯ СЕМЬЯ"
    return const WelcomeScreen();
  }
}