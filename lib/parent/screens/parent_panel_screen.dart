import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/initial_session_wrapper.dart';
import '../../features/chat/family_chat_screen.dart';
import 'generate_parent_qr_screen.dart';
import 'scan_second_parent_screen.dart';
import 'add_child_screen.dart';
import 'child_detail_screen.dart';
import 'child_qr_display_screen.dart';
import 'parent_profile_screen.dart';

import '../../core/app_theme.dart';
import '../../core/services/app_log_service.dart';
import '../../core/services/chat_notification_service.dart';
import '../../core/services/family_chat_service.dart';
import '../../core/services/github_update_service.dart';
import '../../core/services/parent_security_service.dart';
import '../../features/widgets/app_version_widget.dart';
import '../../features/widgets/user_avatar_widget.dart';

// Глобальные дизайн-константы в стиле стекломорфизма
const Color parentGlassPanel = Color(0x33FFFFFF);
const Color parentTextPrimary = Colors.white;

class _ProtectionCriterion {
  final String title;
  final String subtitle;
  final int earnedPoints;
  final int maxPoints;
  final bool isCompleted;

  const _ProtectionCriterion({
    required this.title,
    required this.subtitle,
    required this.earnedPoints,
    required this.maxPoints,
    required this.isCompleted,
  });
}

class _FamilyProtectionReport {
  final int percent;
  final String summary;
  final List<_ProtectionCriterion> criteria;

  const _FamilyProtectionReport({
    required this.percent,
    required this.summary,
    required this.criteria,
  });
}

class ParentPanelScreen extends StatefulWidget {
  const ParentPanelScreen({super.key});

  @override
  State<ParentPanelScreen> createState() => _ParentPanelScreenState();
}

class _ParentPanelScreenState extends State<ParentPanelScreen>
    with WidgetsBindingObserver {
  String _currentUid = '';
  String _localName = 'Вы';
  String _localRole = 'Родитель';
  String _localBirthDate = '';
  String _localAvatarHash = '';
  bool _notificationsDisabledWarning = false;
  bool _didRunSilentUpdateCheck = false;

  late Timer _clockTimer;
  Timer? _presenceTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hideBottomNavigationBar();
    _loadLocalProfile();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _now = DateTime.now();
        });
      }
    });
    _presenceTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _updateMyPresence(isOnline: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer.cancel();
    _presenceTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _hideBottomNavigationBar();
      _updateMyPresence(isOnline: true);
      _refreshNotificationPermissionState(requestIfNeeded: false);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _updateMyPresence(isOnline: false);
    }
  }

  Future<void> _refreshNotificationPermissionState({
    bool requestIfNeeded = false,
  }) async {
    final bool granted = requestIfNeeded
        ? await ChatNotificationService.requestPermission()
        : await ChatNotificationService.isPermissionGranted();
    if (mounted && _notificationsDisabledWarning == granted) {
      setState(() {
        _notificationsDisabledWarning = !granted;
      });
    }
  }

  void _hideBottomNavigationBar() {
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: [SystemUiOverlay.top],
    );
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );
  }

  Future<void> _updateMyPresence({required bool isOnline}) async {
    if (_currentUid.isEmpty) return;
    try {
      await FirebaseDatabase.instance.ref('users/$_currentUid').update({
        'isOnline': isOnline,
        'lastSeen': ServerValue.timestamp,
      });
    } catch (_) {}
  }

  Future<void> _loadLocalProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('user_uid') ?? '';
    final name = prefs.getString('user_name') ?? 'Вы';
    final role = prefs.getString('user_role') ?? 'Родитель';
    final birthDate = prefs.getString('user_birth_date') ?? '';
    final avatarHash = prefs.getString('user_avatar_hash') ?? '';

    if (uid.isNotEmpty) {
      await prefs.setBool('parent_profile_ready_$uid', true);
    }

    if (!mounted) return;
    setState(() {
      _currentUid = uid;
      _localName = name;
      _localRole = role;
      _localBirthDate = birthDate;
      _localAvatarHash = avatarHash;
    });

    _updateMyPresence(isOnline: true);
    await _refreshNotificationPermissionState(requestIfNeeded: true);

    if (!_didRunSilentUpdateCheck && mounted) {
      _didRunSilentUpdateCheck = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          GithubUpdateService.checkForUpdates(context, silent: true);
        }
      });
    }
  }

  Future<void> _openMyProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ParentProfileScreen(),
      ),
    );
    _loadLocalProfile();
  }

  bool _isParentOnline(Map<dynamic, dynamic> userData) {
    if (userData['isOnline'] == false) return false;
    final int lastSeen =
        int.tryParse(userData['lastSeen']?.toString() ?? '0') ?? 0;
    if (lastSeen <= 0) return false;
    final int diffMs = DateTime.now().millisecondsSinceEpoch - lastSeen;
    return diffMs <= 3 * 60 * 1000;
  }

  bool _isChildOnline(Map<dynamic, dynamic> childData) {
    final int nowMs = DateTime.now().millisecondsSinceEpoch;
    int lastActivity =
        int.tryParse(childData['lastSeen']?.toString() ?? '0') ?? 0;

    if (childData['location'] is Map) {
      final loc = Map<dynamic, dynamic>.from(childData['location'] as Map);
      final locTs = int.tryParse(loc['timestamp']?.toString() ?? '0') ?? 0;
      if (locTs > lastActivity) {
        lastActivity = locTs;
      }
    }

    if (lastActivity <= 0) return false;
    return (nowMs - lastActivity) <= 5 * 60 * 1000;
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatRussianDate(DateTime dt) {
    const weekdays = [
      'Понедельник',
      'Вторник',
      'Среда',
      'Четверг',
      'Пятница',
      'Суббота',
      'Воскресенье',
    ];
    const months = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];
    final weekday = weekdays[dt.weekday - 1];
    final month = months[dt.month - 1];
    return '$weekday, ${dt.day} $month ${dt.year}';
  }

  _FamilyProtectionReport _evaluateFamilyProtection({
    required List<MapEntry<String, Map<dynamic, dynamic>>> familyChildren,
    required bool hasSecondParent,
  }) {
    final int nowMillis = DateTime.now().millisecondsSinceEpoch;
    const int thirtyMinutesMs = 30 * 60 * 1000;

    final linkedChildren = familyChildren
        .where((e) => e.value['isLinked'] == true)
        .map((e) => e.value)
        .toList();

    int linkPoints = 0;
    String linkSub = 'Добавьте ребёнка и привяжите его устройство';
    if (linkedChildren.isNotEmpty) {
      linkPoints = 30;
      linkSub = 'Привязано устройств: ${linkedChildren.length}';
    } else if (familyChildren.isNotEmpty) {
      linkPoints = 15;
      linkSub = 'Профиль создан, ожидается сканирование QR-кода';
    }

    bool hasFreshGps = false;
    for (final child in linkedChildren) {
      if (child['location'] is Map) {
        final loc = Map<dynamic, dynamic>.from(child['location'] as Map);
        final lat = loc['latitude'];
        final ts = int.tryParse(loc['timestamp']?.toString() ?? '0') ?? 0;
        if (lat != null && (nowMillis - ts) <= thirtyMinutesMs) {
          hasFreshGps = true;
          break;
        }
      }
    }
    final int gpsPoints = hasFreshGps ? 25 : 0;

    bool hasAppControl = false;
    for (final child in linkedChildren) {
      if (child['installedApps'] is Map &&
          (child['installedApps'] as Map).isNotEmpty) {
        hasAppControl = true;
        break;
      }
    }
    final int appPoints = hasAppControl ? 20 : 0;

    bool hasGeofences = false;
    for (final child in linkedChildren) {
      if (child['geofences'] is Map &&
          (child['geofences'] as Map).isNotEmpty) {
        hasGeofences = true;
        break;
      }
    }
    final int zonePoints = hasGeofences ? 15 : 0;

    bool allBatteriesOk = linkedChildren.isNotEmpty;
    for (final child in linkedChildren) {
      if (child['location'] is Map) {
        final loc = Map<dynamic, dynamic>.from(child['location'] as Map);
        final bat =
            int.tryParse(loc['batteryLevel']?.toString() ?? '100') ?? 100;
        if (bat <= 20) {
          allBatteriesOk = false;
          break;
        }
      }
    }
    final int extraPoints =
        (allBatteriesOk ? 5 : 0) + (hasSecondParent ? 5 : 0);

    final totalPercent =
        (linkPoints + gpsPoints + appPoints + zonePoints + extraPoints)
            .clamp(0, 100);

    String summary;
    if (familyChildren.isEmpty) {
      summary = 'Добавьте ребёнка для запуска защиты';
    } else if (linkedChildren.isEmpty) {
      summary = 'Ожидается привязка устройства ребёнка';
    } else if (!hasFreshGps) {
      summary = 'Нет свежего сигнала GPS от устройства';
    } else if (!hasGeofences) {
      summary = 'Рекомендуем добавить геозоны (Дом, Школа)';
    } else if (totalPercent >= 90) {
      summary = 'Все системы защиты активны и в норме';
    } else {
      summary = 'Нажмите для просмотра рекомендаций';
    }

    return _FamilyProtectionReport(
      percent: totalPercent,
      summary: summary,
      criteria: [
        _ProtectionCriterion(
          title: 'Привязка устройств детей',
          subtitle: linkSub,
          earnedPoints: linkPoints,
          maxPoints: 30,
          isCompleted: linkPoints == 30,
        ),
        _ProtectionCriterion(
          title: 'Активная геолокация GPS',
          subtitle: hasFreshGps
              ? 'Координаты обновляются в реальном времени'
              : 'Нет свежих координат за последние 30 минут',
          earnedPoints: gpsPoints,
          maxPoints: 25,
          isCompleted: hasFreshGps,
        ),
        _ProtectionCriterion(
          title: 'Контроль приложений и времени',
          subtitle: hasAppControl
              ? 'Список приложений и статистика синхронизированы'
              : 'Ожидается синхронизация приложений ребёнка',
          earnedPoints: appPoints,
          maxPoints: 20,
          isCompleted: hasAppControl,
        ),
        _ProtectionCriterion(
          title: 'Безопасные геозоны',
          subtitle: hasGeofences
              ? 'Важные точки (Дом/Школа) настроены'
              : 'Добавьте геозоны в карточке ребёнка',
          earnedPoints: zonePoints,
          maxPoints: 15,
          isCompleted: hasGeofences,
        ),
        _ProtectionCriterion(
          title: 'Заряд батареи и второй родитель',
          subtitle:
              'Батарея > 20%: ${allBatteriesOk ? 'да' : 'низкий заряд'} • Второй родитель: ${hasSecondParent ? 'подключён' : 'нет'}',
          earnedPoints: extraPoints,
          maxPoints: 10,
          isCompleted: extraPoints == 10,
        ),
      ],
    );
  }

  void _showProtectionDetailsSheet(_FamilyProtectionReport report) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Защита семьи',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${report.percent}%',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: report.percent >= 80
                          ? Colors.green.shade700
                          : Colors.orange.shade800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Показатель рассчитывается автоматически по состоянию привязанных устройств:',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const Divider(height: 20),
              ...report.criteria.map(
                (c) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        c.isCompleted
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: c.isCompleted ? Colors.green : Colors.orange,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              c.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              c.subtitle,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${c.earnedPoints}/${c.maxPoints}%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color:
                              c.isCompleted ? Colors.green.shade700 : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPrivacyPolicySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Row(
                children: [
                  Icon(Icons.privacy_tip_rounded, color: Colors.teal),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Политика конфиденциальности',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: const [
                    Text(
                      '1. Какие данные обрабатывает FamilyPulse',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Приложение обрабатывает только данные, необходимые для семейной безопасности и родительского контроля: координаты устройства ребёнка (включая фоновый режим), список установленных приложений и время их использования, уровень заряда батареи, а также имена, роли и аватары членов семьи.',
                      style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
                    ),
                    SizedBox(height: 14),
                    Text(
                      '2. Доступ и защита информации',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Все данные привязаны исключительно к вашей семейной группе и передаются по защищённому протоколу. Информация не передаётся третьим лицам и не используется в рекламных целях.',
                      style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
                    ),
                    SizedBox(height: 14),
                    Text(
                      '3. Удаление данных и управление',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'История маршрутов автоматически очищается через 14 дней. Родитель может в любой момент отвязать устройство ребёнка или удалить данные профиля в настройках.',
                      style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAboutAppSheet() async {
    String versionText = '—';
    try {
      final info = await PackageInfo.fromPlatform();
      versionText = '${info.version} (сборка ${info.buildNumber})';
    } catch (_) {}

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.shield_moon_rounded,
                      color: Colors.indigo.shade700,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'FamilyPulse',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Версия: $versionText',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Семейный лаунчер, геолокация, контроль экранного времени и система мотивации для детей и родителей.',
                style: TextStyle(fontSize: 13.5, color: Colors.black87, height: 1.4),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.system_update_rounded, size: 18),
                  label: const Text('Проверить обновления на GitHub'),
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    GithubUpdateService.checkForUpdates(context, silent: false);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTariffsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Row(
                children: [
                  Icon(Icons.workspace_premium_rounded, color: Colors.amber),
                  SizedBox(width: 8),
                  Text(
                    'Тарифы FamilyPulse',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Базовый (Активен)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          '0 ₽ / мес',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '• Геолокация в реальном времени и геозоны\n'
                      '• Детский лаунчер и лимиты приложений\n'
                      '• Задания, баллы, цели и семейный чат',
                      style: TextStyle(fontSize: 12.5, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.indigo.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Семейный Plus (Скоро)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        Text(
                          'В разработке',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: Colors.indigo.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '• Расширенная история маршрутов до 30 дней\n'
                      '• Недельные отчёты по экранному времени\n'
                      '• Эксклюзивные образы для игрового компаньона',
                      style: TextStyle(fontSize: 12.5, height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleScanButtonTap() async {
    PermissionStatus cameraStatus = await Permission.camera.request();

    if (!mounted) return;

    if (cameraStatus.isGranted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ScanSecondParentScreen()),
      );
    } else if (cameraStatus.isPermanentlyDenied) {
      _showSettingsDialog();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Для сканирования QR-кода необходим доступ к камере.'),
        ),
      );
    }
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Требуется доступ к камере'),
        content: const Text(
          'Доступ к камере заблокирован в настройках устройства. Пожалуйста, разрешите доступ в настройках приложения для сканирования QR-кода.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              openAppSettings();
            },
            child: const Text('Открыть настройки'),
          ),
        ],
      ),
    );
  }

  void _showAddSecondMemberSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Добавить второго члена семьи',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(60),
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: parentTextPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                icon: const Icon(Icons.qr_code),
                label: const Text('ДЛЯ ПОДКЛЮЧЕНИЯ'),
                onPressed: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const GenerateParentQrScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(60),
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: parentTextPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('ДЛЯ ВСТУПЛЕНИЯ'),
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _handleScanButtonTap();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMemberInfoDialog({
    required String name,
    required String role,
    required String birthDate,
    required String avatarHash,
    required bool isMe,
    required bool isOnline,
  }) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            UserAvatarWidget(
              avatarBase64: avatarHash,
              radius: 20,
              fallbackIcon: Icons.person,
              fallbackBackgroundColor:
                  isMe ? Colors.blue.shade50 : Colors.green.shade50,
              fallbackIconColor: isMe ? Colors.blue : Colors.green,
              borderWidth: 2.5,
              borderColor: isOnline ? Colors.green : Colors.redAccent,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('$role $name')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Статус: ${isMe ? "Ваш профиль (В сети)" : (isOnline ? "В сети" : "Не в сети")}',
            ),
            const SizedBox(height: 8),
            Text(
              'Дата рождения: ${birthDate.isNotEmpty ? birthDate : "Не указана"}',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  Future<void> _performLogout() async {
    await ChatNotificationService.stopListening();
    await _updateMyPresence(isOnline: false);
    await ParentSecurityService.clearPin(clearBackup: true);
    ParentSecurityService.isSessionUnlocked = false;

    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('saved_device_uid');
    await prefs.remove('user_type');
    await prefs.remove('user_uid');
    await prefs.remove('user_name');
    await prefs.remove('user_role');
    await prefs.remove('user_birth_date');
    await prefs.remove('user_avatar_hash');

    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (context) => const InitialSessionWrapper()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            AppTheme.parentBackgroundAsset,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              debugPrint('ОШИБКА ЗАГРУЗКИ ФОНА: $error');
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.blueGrey.shade900, Colors.blue.shade900],
                  ),
                ),
              );
            },
          ),
        ),
        Positioned.fill(
          child: Container(color: Colors.black.withValues(alpha: 0.4)),
        ),
        StreamBuilder<DatabaseEvent>(
          stream: _currentUid.isEmpty
              ? const Stream.empty()
              : FirebaseDatabase.instance.ref('users/$_currentUid').onValue,
          builder: (context, userSnapshot) {
            Map<dynamic, dynamic> myData = {};
            if (userSnapshot.hasData &&
                userSnapshot.data!.snapshot.value != null) {
              myData = Map<dynamic, dynamic>.from(
                userSnapshot.data!.snapshot.value as Map,
              );
            }

            final myName = myData['name']?.toString() ?? _localName;
            final myRole = myData['familyRole']?.toString() ?? _localRole;
            final myBirthDate =
                myData['birthDate']?.toString() ?? _localBirthDate;
            final myAvatarHash =
                myData['avatarHash']?.toString() ?? _localAvatarHash;
            final linkedParentUid = myData['linkedParent']?.toString();
            final bool hasSecondParent =
                linkedParentUid != null && linkedParentUid.isNotEmpty;

            return StreamBuilder<DatabaseEvent>(
              stream: FirebaseDatabase.instance.ref('children').onValue,
              builder: (context, childrenSnapshot) {
                List<MapEntry<String, Map<dynamic, dynamic>>> familyChildren = [];

                if (childrenSnapshot.hasData &&
                    childrenSnapshot.data!.snapshot.value != null) {
                  final childrenMap = Map<dynamic, dynamic>.from(
                    childrenSnapshot.data!.snapshot.value as Map,
                  );

                  childrenMap.forEach((key, value) {
                    final childData = Map<dynamic, dynamic>.from(value);
                    final childParentUid = childData['parentUid'];

                    final bool isFamilyChild =
                        (childParentUid == _currentUid) ||
                            (hasSecondParent &&
                                childParentUid == linkedParentUid);

                    if (isFamilyChild) {
                      familyChildren.add(MapEntry(key.toString(), childData));
                    }
                  });
                }

                final protectionReport = _evaluateFamilyProtection(
                  familyChildren: familyChildren,
                  hasSecondParent: hasSecondParent,
                );
                final Color shieldColor = protectionReport.percent >= 80
                    ? Colors.green.shade600
                    : protectionReport.percent >= 50
                        ? Colors.orange.shade700
                        : Colors.redAccent;

                final String familyChatId =
                    FamilyChatService.resolveFamilyChatId(
                  primaryParentUid: _currentUid,
                  linkedParentUid: linkedParentUid,
                );

                if (familyChatId.isNotEmpty && _currentUid.isNotEmpty) {
                  ChatNotificationService.startListening(
                    chatId: familyChatId,
                    currentMemberId: _currentUid,
                  );
                }

                final List<String> allMemberIds = [
                  _currentUid,
                  if (hasSecondParent) linkedParentUid,
                  ...familyChildren.map((e) => e.key),
                ];

                return Scaffold(
                  backgroundColor: Colors.transparent,
                  appBar: AppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    title: const Text(
                      'Панель Родителя',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    iconTheme: const IconThemeData(color: Colors.white),
                    actions: [
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.settings, color: Colors.white),
                        tooltip: 'Настройки',
                        onSelected: (value) async {
                          if (value == 'logs') {
                            AppLogService.showLogsBottomSheet(context);
                          } else if (value == 'privacy') {
                            _showPrivacyPolicySheet();
                          } else if (value == 'about') {
                            _showAboutAppSheet();
                          } else if (value == 'tariffs') {
                            _showTariffsSheet();
                          } else if (value == 'logout') {
                            _performLogout();
                          }
                        },
                        itemBuilder: (BuildContext context) =>
                            <PopupMenuEntry<String>>[
                          const PopupMenuItem<String>(
                            value: 'logs',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.bug_report_rounded,
                                  color: Colors.indigo,
                                ),
                                SizedBox(width: 12),
                                Text('Логи'),
                              ],
                            ),
                          ),
                          const PopupMenuItem<String>(
                            value: 'privacy',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.privacy_tip_rounded,
                                  color: Colors.teal,
                                ),
                                SizedBox(width: 12),
                                Text('Политика конфиденциальности'),
                              ],
                            ),
                          ),
                          const PopupMenuItem<String>(
                            value: 'about',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.info_outline_rounded,
                                  color: Colors.blueGrey,
                                ),
                                SizedBox(width: 12),
                                Text('О приложении'),
                              ],
                            ),
                          ),
                          const PopupMenuItem<String>(
                            value: 'tariffs',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.workspace_premium_rounded,
                                  color: Colors.amber,
                                ),
                                SizedBox(width: 12),
                                Text('Тарифы'),
                              ],
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem<String>(
                            value: 'logout',
                            child: Row(
                              children: [
                                Icon(Icons.logout, color: Colors.redAccent),
                                SizedBox(width: 12),
                                Text('Выход'),
                              ],
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem<String>(
                            enabled: false,
                            child: Center(child: AppVersionWidget()),
                          ),
                        ],
                      ),
                    ],
                  ),
                  body: SafeArea(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 20.0),
                      children: [
                        // БЛОК 1: ПАНЕЛЬ ВРЕМЕНИ И ДАТЫ
                        Card(
                          elevation: 4,
                          color: Colors.white.withValues(alpha: 0.9),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 14.0,
                              horizontal: 20.0,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _formatTime(_now),
                                      style: const TextStyle(
                                        fontSize: 36,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _formatRussianDate(_now),
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.access_time_filled,
                                    size: 28,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // ПРЕДУПРЕЖДЕНИЕ ОБ ОТКЛЮЧЁННЫХ УВЕДОМЛЕНИЯХ
                        if (_notificationsDisabledWarning) ...[
                          Card(
                            elevation: 4,
                            color: Colors.amber.shade50,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: Colors.amber.shade700),
                            ),
                            child: ListTile(
                              dense: true,
                              leading: Icon(
                                Icons.notifications_off_rounded,
                                color: Colors.amber.shade900,
                              ),
                              title: const Text(
                                'Уведомления отключены',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: const Text(
                                'Включите уведомления, чтобы получать запросы ребёнка со звуком',
                                style: TextStyle(fontSize: 12),
                              ),
                              trailing: TextButton(
                                onPressed: () => openAppSettings(),
                                child: const Text('Включить'),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],

                        // БЛОК 2: ЗАЩИТА СЕМЬИ
                        InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () =>
                              _showProtectionDetailsSheet(protectionReport),
                          child: Card(
                            elevation: 4,
                            color: Colors.white.withValues(alpha: 0.9),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Text(
                                        'Защита семьи',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      Text(
                                        '${protectionReport.percent}%',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: shieldColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: shieldColor
                                              .withValues(alpha: 0.12),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.shield_rounded,
                                          size: 28,
                                          color: shieldColor,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: LinearProgressIndicator(
                                                value: protectionReport
                                                        .percent /
                                                    100.0,
                                                minHeight: 8,
                                                backgroundColor:
                                                    Colors.grey.shade300,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                        Color>(shieldColor),
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    protectionReport.summary,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.black54,
                                                    ),
                                                  ),
                                                ),
                                                const Icon(
                                                  Icons.chevron_right_rounded,
                                                  size: 16,
                                                  color: Colors.black45,
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // БЛОК 3: МОЯ СЕМЬЯ
                        Card(
                          elevation: 6,
                          color: Colors.white.withValues(alpha: 0.92),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Моя семья',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                                const Divider(),
                                if (_currentUid.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 20),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                else ...[
                                  // 1. Текущий родитель
                                  ListTile(
                                    dense: true,
                                    contentPadding:
                                        const EdgeInsets.symmetric(horizontal: 4),
                                    leading: UserAvatarWidget(
                                      avatarBase64: myAvatarHash,
                                      radius: 19,
                                      fallbackIcon: Icons.person,
                                      fallbackBackgroundColor:
                                          Colors.blue.shade50,
                                      fallbackIconColor: Colors.blue,
                                      borderWidth: 2.5,
                                      borderColor: Colors.green,
                                    ),
                                    title: Text(
                                      '$myRole $myName (Вы)',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: Text(
                                      myBirthDate.isNotEmpty
                                          ? 'Дата рождения: $myBirthDate'
                                          : 'Дата рождения не указана',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    trailing: const Icon(
                                      Icons.edit_outlined,
                                      size: 20,
                                      color: Colors.blueGrey,
                                    ),
                                    onTap: _openMyProfile,
                                  ),

                                  // 2. Второй родитель
                                  if (hasSecondParent)
                                    StreamBuilder<DatabaseEvent>(
                                      stream: FirebaseDatabase.instance
                                          .ref('users/$linkedParentUid')
                                          .onValue,
                                      builder: (context, partnerSnapshot) {
                                        if (!partnerSnapshot.hasData ||
                                            partnerSnapshot
                                                    .data!.snapshot.value ==
                                                null) {
                                          return const ListTile(
                                            dense: true,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                              horizontal: 4,
                                            ),
                                            leading: Icon(
                                              Icons.person_outline,
                                              color: Colors.grey,
                                            ),
                                            title: Text(
                                              'Загрузка второго члена семьи...',
                                            ),
                                          );
                                        }

                                        final partnerData =
                                            Map<dynamic, dynamic>.from(
                                          partnerSnapshot.data!.snapshot.value
                                              as Map,
                                        );

                                        final partnerName =
                                            partnerData['name']?.toString() ??
                                                'Родитель';
                                        final partnerRole =
                                            partnerData['familyRole']
                                                    ?.toString() ??
                                                'Родитель';
                                        final partnerBirth =
                                            partnerData['birthDate']
                                                    ?.toString() ??
                                                '';
                                        final partnerAvatar =
                                            partnerData['avatarHash']
                                                    ?.toString() ??
                                                '';
                                        final bool isPartnerOnline =
                                            _isParentOnline(partnerData);

                                        return ListTile(
                                          dense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 4,
                                          ),
                                          leading: UserAvatarWidget(
                                            avatarBase64: partnerAvatar,
                                            radius: 19,
                                            fallbackIcon: Icons.person,
                                            fallbackBackgroundColor:
                                                Colors.green.shade50,
                                            fallbackIconColor: Colors.green,
                                            borderWidth: 2.5,
                                            borderColor: isPartnerOnline
                                                ? Colors.green
                                                : Colors.redAccent,
                                          ),
                                          title: Text(
                                            '$partnerRole $partnerName',
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          subtitle: Text(
                                            partnerBirth.isNotEmpty
                                                ? 'Дата рождения: $partnerBirth'
                                                : 'Дата рождения не указана',
                                            style:
                                                const TextStyle(fontSize: 12),
                                          ),
                                          trailing: const Icon(
                                            Icons.chevron_right,
                                            color: Colors.grey,
                                          ),
                                          onTap: () => _showMemberInfoDialog(
                                            name: partnerName,
                                            role: partnerRole,
                                            birthDate: partnerBirth,
                                            avatarHash: partnerAvatar,
                                            isMe: false,
                                            isOnline: isPartnerOnline,
                                          ),
                                        );
                                      },
                                    ),

                                  // 3. Дети
                                  ...familyChildren.map((entry) {
                                    final childId = entry.key;
                                    final childData = entry.value;
                                    final childName =
                                        childData['name']?.toString() ??
                                            'Ребёнок';
                                    final familyRole =
                                        childData['familyRole']?.toString() ??
                                            'Ребёнок';
                                    final childBirth =
                                        childData['birthDate']?.toString() ??
                                            '';
                                    final childAvatar =
                                        childData['avatarHash']?.toString() ??
                                            '';
                                    final bool isLinked =
                                        childData['isLinked'] == true;
                                    final bool isOnline =
                                        isLinked && _isChildOnline(childData);

                                    final Color borderColor = !isLinked
                                        ? Colors.orange
                                        : (isOnline
                                            ? Colors.green
                                            : Colors.redAccent);

                                    return ListTile(
                                      dense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 4,
                                      ),
                                      leading: UserAvatarWidget(
                                        avatarBase64: childAvatar,
                                        radius: 19,
                                        fallbackIcon: isLinked
                                            ? Icons.child_care
                                            : Icons.hourglass_top,
                                        fallbackBackgroundColor: isLinked
                                            ? Colors.purple.shade50
                                            : Colors.orange.shade50,
                                        fallbackIconColor: isLinked
                                            ? Colors.purple
                                            : Colors.orange.shade800,
                                        borderWidth: 2.5,
                                        borderColor: borderColor,
                                      ),
                                      title: Text(
                                        '$familyRole $childName',
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Text(
                                        isLinked
                                            ? (childBirth.isNotEmpty
                                                ? 'Дата рождения: $childBirth'
                                                : 'Дата рождения не указана')
                                            : 'Ожидает привязки...',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isLinked
                                              ? Colors.black54
                                              : Colors.orange.shade800,
                                          fontWeight: isLinked
                                              ? FontWeight.normal
                                              : FontWeight.w500,
                                        ),
                                      ),
                                      trailing: const Icon(
                                        Icons.chevron_right,
                                        color: Colors.grey,
                                      ),
                                      onTap: () {
                                        if (isLinked) {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  ChildDetailScreen(
                                                childId: childId,
                                                childName: childName,
                                              ),
                                            ),
                                          );
                                        } else {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  ChildQrDisplayScreen(
                                                childId: childId,
                                                childName: childName,
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                    );
                                  }),
                                ],

                                const SizedBox(height: 12),
                                const Divider(height: 1),
                                const SizedBox(height: 12),

                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size.fromHeight(48),
                                    backgroundColor: Colors.blue.shade700,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  icon: const Icon(Icons.child_care),
                                  label: const Text(
                                    'ДОБАВИТЬ РЕБЁНКА',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            const AddChildScreen(),
                                      ),
                                    );
                                  },
                                ),
                                if (!hasSecondParent) ...[
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size.fromHeight(48),
                                      foregroundColor: Colors.blue.shade800,
                                      side: BorderSide(
                                        color: Colors.blue.shade200,
                                        width: 1.4,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    icon: const Icon(Icons.person_add),
                                    label: const Text(
                                      'ВТОРОЙ РОДИТЕЛЬ',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    onPressed: _showAddSecondMemberSheet,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // БЛОК 4: СЕМЕЙНЫЙ ЧАТ (ПОД ПАНЕЛЬЮ «МОЯ СЕМЬЯ»)
                        StreamBuilder<DatabaseEvent>(
                          stream: familyChatId.isEmpty
                              ? const Stream.empty()
                              : FirebaseDatabase.instance
                                  .ref('familyChats/$familyChatId')
                                  .onValue,
                          builder: (context, chatSnapshot) {
                            int unreadCount = 0;
                            String lastMessage = '';
                            String lastSenderName = '';

                            if (chatSnapshot.hasData &&
                                chatSnapshot.data!.snapshot.value != null) {
                              final chatData = Map<dynamic, dynamic>.from(
                                chatSnapshot.data!.snapshot.value as Map,
                              );
                              lastMessage =
                                  chatData['lastMessage']?.toString() ?? '';
                              lastSenderName =
                                  chatData['lastSenderName']?.toString() ?? '';
                              if (chatData['unreadBy'] is Map) {
                                final unreadMap = Map<dynamic, dynamic>.from(
                                  chatData['unreadBy'] as Map,
                                );
                                unreadCount = int.tryParse(
                                      unreadMap[_currentUid]?.toString() ?? '0',
                                    ) ??
                                    0;
                              }
                            }

                            final bool hasUnread = unreadCount > 0;

                            void openFamilyChat() {
                              if (familyChatId.isEmpty) return;
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => FamilyChatScreen(
                                    chatId: familyChatId,
                                    currentUserId: _currentUid,
                                    currentUserName: '$myRole $myName',
                                    currentUserRole: 'parent',
                                    allFamilyMemberIds: allMemberIds,
                                  ),
                                ),
                              );
                            }

                            return InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: openFamilyChat,
                              child: Card(
                                elevation: 5,
                                color: Colors.white.withValues(alpha: 0.92),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: hasUnread
                                      ? BorderSide(
                                          color: Colors.blue.shade400,
                                          width: 1.5,
                                        )
                                      : BorderSide.none,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(14.0),
                                  child: Row(
                                    children: [
                                      Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(11),
                                            decoration: BoxDecoration(
                                              color: hasUnread
                                                  ? Colors.blue.shade50
                                                  : Colors.grey.shade100,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Icon(
                                              Icons.forum_rounded,
                                              size: 26,
                                              color: hasUnread
                                                  ? Colors.blue.shade700
                                                  : Colors.blueGrey,
                                            ),
                                          ),
                                          if (hasUnread)
                                            Positioned(
                                              top: -2,
                                              right: -2,
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 6,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.redAccent,
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                child: Text(
                                                  '$unreadCount',
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Семейный чат',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.black87,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              hasUnread
                                                  ? (unreadCount == 1
                                                      ? 'Новое уведомление'
                                                      : 'Новые уведомления ($unreadCount)')
                                                  : 'Уведомлений нет',
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: hasUnread
                                                    ? FontWeight.w700
                                                    : FontWeight.w500,
                                                color: hasUnread
                                                    ? Colors.blue.shade700
                                                    : Colors.black54,
                                              ),
                                            ),
                                            if (lastMessage.isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                lastSenderName.isNotEmpty
                                                    ? '$lastSenderName: $lastMessage'
                                                    : lastMessage,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 11.5,
                                                  color: Colors.black45,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: hasUnread
                                              ? Colors.blue.shade700
                                              : Colors.blueGrey.shade50,
                                          foregroundColor: hasUnread
                                              ? Colors.white
                                              : Colors.blueGrey.shade800,
                                          elevation: 0,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 10,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                        ),
                                        onPressed: openFamilyChat,
                                        child: const Text(
                                          'Перейти',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}