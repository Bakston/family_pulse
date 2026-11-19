import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:device_apps_ng/device_apps_ng.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_theme.dart';
import '../../core/services/location_service.dart';
import '../../core/services/app_control_service.dart';
import '../../core/services/chat_notification_service.dart';
import '../../core/services/daily_tasks_service.dart';
import '../../core/services/family_chat_service.dart';
import '../../core/services/github_update_service.dart';
import '../../core/services/web_filter_service.dart';
import '../../features/chat/family_chat_screen.dart';
import '../../features/widgets/user_avatar_widget.dart';
import '../../features/auth/initial_session_wrapper.dart';
import 'child_permissions_screen.dart';
import 'child_tasks_screen.dart';

class ChildPanelScreen extends StatefulWidget {
  final String childName;

  const ChildPanelScreen({
    super.key,
    required this.childName,
  });

  @override
  State<ChildPanelScreen> createState() => _ChildPanelScreenState();
}

class _ChildPanelScreenState extends State<ChildPanelScreen>
    with WidgetsBindingObserver {
  String _childId = '';
  String _cachedGender = 'boy';
  bool _isDefaultLauncher = false;
  bool _isLocationActive = false;
  bool _manual5MinBypassActive = false;
  int _lastHandledForceLocationAt = 0;
  List<Application> _installedApps = [];
  bool _isLoadingApps = true;

  late Timer _clockTimer;
  Timer? _syncTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _now = DateTime.now());
      }
    });
    _initLauncher();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer.cancel();
    _syncTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_manual5MinBypassActive) {
        AppControlService.adminChannel.invokeMethod(
          'setParentBypass',
          {'minutes': 0},
        );
      }
      _refreshDefaultLauncherState();
      _ensureServicesRunning();
      _loadDeviceApps();
      _updateChildPresence();
      _checkPendingUnlockRequest();
      if (_childId.isNotEmpty) {
        DailyTasksService.processDailyTasks(_childId);
      }
    }
  }

  Future<void> _refreshDefaultLauncherState() async {
    bool isLauncher = false;
    try {
      isLauncher = await AppControlService.adminChannel
              .invokeMethod<bool>('checkDefaultLauncher') ??
          false;
    } catch (_) {}

    if (mounted && _isDefaultLauncher != isLauncher) {
      setState(() => _isDefaultLauncher = isLauncher);
    } else {
      _isDefaultLauncher = isLauncher;
    }

    if (_childId.isNotEmpty) {
      try {
        await FirebaseDatabase.instance
            .ref('children/$_childId/childMode')
            .set(isLauncher ? 'launcher' : 'background');
      } catch (_) {}
    }
  }

  Future<void> _updateChildPresence() async {
    if (_childId.isEmpty) return;
    try {
      await FirebaseDatabase.instance
          .ref('children/$_childId/lastSeen')
          .set(ServerValue.timestamp);
    } catch (_) {}
  }

  void _triggerSilentUpdateCheck() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      GithubUpdateService.checkForUpdates(context, silent: true);
    });
  }

  Future<void> _initLauncher() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString('saved_child_id') ?? '';
    final savedGender = prefs.getString('saved_child_gender') ?? 'boy';
    _lastHandledForceLocationAt =
        prefs.getInt('last_handled_force_location_at') ?? 0;

    if (mounted) {
      setState(() {
        _childId = savedId;
        _cachedGender = savedGender;
      });
    }

    await _refreshDefaultLauncherState();
    await _loadDeviceApps();
    _triggerSilentUpdateCheck();

    if (savedId.isEmpty) return;

    await _updateChildPresence();
    await DailyTasksService.processDailyTasks(savedId);
    await _checkPendingUnlockRequest();

    try {
      final parentSnap = await FirebaseDatabase.instance
          .ref('children/$savedId/parentUid')
          .get();
      final parentUid = parentSnap.value?.toString() ?? '';
      if (parentUid.isNotEmpty) {
        final chatId = await FamilyChatService.resolveChatIdForChild(parentUid);
        if (chatId.isNotEmpty) {
          await ChatNotificationService.startListening(
            chatId: chatId,
            currentMemberId: savedId,
          );
        }
      }
    } catch (_) {}

    await _ensureServicesRunning();

    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
      await _updateChildPresence();
      await DailyTasksService.processDailyTasks(savedId);
      await AppControlService.syncInstalledApps();
      await _loadDeviceApps();
      _triggerSilentUpdateCheck();
    });
  }

  /// Проверяет, нажимал ли ребёнок «Спросить разрешение на использование» в нативном экране блокировки
  Future<void> _checkPendingUnlockRequest() async {
    if (_childId.isEmpty) return;
    try {
      final rawReq = await AppControlService.adminChannel
          .invokeMethod('consumePendingUnlockRequest');
      if (rawReq == null) return;

      final req = Map<String, dynamic>.from(rawReq);
      final packageName = req['packageName']?.toString() ?? '';
      final appName = req['appName']?.toString() ?? packageName;
      if (packageName.isEmpty) return;

      final childSnap =
          await FirebaseDatabase.instance.ref('children/$_childId').get();
      if (!childSnap.exists || childSnap.value is! Map) return;
      final childData = Map<dynamic, dynamic>.from(childSnap.value as Map);

      final childName = childData['name']?.toString() ?? widget.childName;
      final parentUid = childData['parentUid']?.toString() ?? '';
      if (parentUid.isEmpty) return;

      String? linkedParentUid;
      try {
        final linkedSnap = await FirebaseDatabase.instance
            .ref('users/$parentUid/linkedParent')
            .get();
        if (linkedSnap.exists && linkedSnap.value != null) {
          linkedParentUid = linkedSnap.value.toString();
        }
      } catch (_) {}

      final chatId = FamilyChatService.resolveFamilyChatId(
        primaryParentUid: parentUid,
        linkedParentUid: linkedParentUid,
      );
      if (chatId.isEmpty) return;

      final memberIds = <String>[_childId, parentUid];
      if (linkedParentUid != null && linkedParentUid.isNotEmpty) {
        memberIds.add(linkedParentUid);
      }

      final requestText = '$childName просит разрешить приложение «$appName»';
      final msgRef = FirebaseDatabase.instance
          .ref('familyChats/$chatId/messages')
          .push();
      await msgRef.set({
        'type': 'system',
        'senderId': _childId,
        'senderName': childName,
        'senderRole': 'child',
        'text': requestText,
        'timestamp': ServerValue.timestamp,
        'action': {
          'kind': 'app_unlock_request',
          'childId': _childId,
          'packageName': packageName,
          'appName': appName,
          'buttonLabel': 'Настройки доступа',
        },
      });

      final updates = <String, dynamic>{
        'lastMessage': requestText,
        'lastMessageAt': ServerValue.timestamp,
        'lastTimestamp': ServerValue.timestamp,
        'lastSenderId': _childId,
        'lastSenderName': childName,
      };
      for (final mId in memberIds.toSet()) {
        if (mId != _childId) {
          updates['unreadBy/$mId'] = ServerValue.increment(1);
        }
      }
      await FirebaseDatabase.instance.ref('familyChats/$chatId').update(updates);
    } catch (e) {
      debugPrint('Ошибка обработки запроса на разблокировку: $e');
    }
  }

  void _checkForceLocationCommand(Map<dynamic, dynamic> childData) {
    if (_childId.isEmpty) return;
    if (childData['commands'] is! Map) return;

    final commands = Map<dynamic, dynamic>.from(childData['commands'] as Map);
    final int forceAt =
        int.tryParse(commands['forceLocationAt']?.toString() ?? '0') ?? 0;

    if (forceAt > _lastHandledForceLocationAt) {
      _lastHandledForceLocationAt = forceAt;
      SharedPreferences.getInstance().then((prefs) {
        prefs.setInt('last_handled_force_location_at', forceAt);
      });
      LocationService.sendImmediateLocationUpdate(childId: _childId);
    }
  }

  Future<void> _ensureServicesRunning() async {
    if (_childId.isEmpty) return;

    bool tracking = LocationService.isTracking;
    if (!tracking) {
      tracking = await LocationService.startChildLocationTracking(
        childId: _childId,
      );
    }

    await AppControlService.syncInstalledApps();

    try {
      final snap =
          await FirebaseDatabase.instance.ref('children/$_childId').get();
      if (snap.exists && snap.value is Map) {
        await WebFilterService.syncFromChildData(
          Map<dynamic, dynamic>.from(snap.value as Map),
          force: true,
        );
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _isLocationActive = tracking;
    });
  }

  Future<void> _loadDeviceApps() async {
    try {
      final apps = await DeviceApps.getInstalledApplications(
        includeAppIcons: true,
        includeSystemApps: true,
        onlyAppsWithLaunchIntent: true,
      );

      apps.removeWhere(
        (app) => AppControlService.restrictedSystemPackages
            .contains(app.packageName),
      );
      apps.sort(
        (a, b) => a.appName.toLowerCase().compareTo(b.appName.toLowerCase()),
      );

      if (!mounted) return;
      setState(() {
        _installedApps = apps;
        _isLoadingApps = false;
      });
    } catch (e) {
      debugPrint('Ошибка загрузки приложений: $e');
      if (mounted) setState(() => _isLoadingApps = false);
    }
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatRussianDate(DateTime dt) {
    const weekdays = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];
    const months = [
      'Января',
      'Февраля',
      'Марта',
      'Апреля',
      'Мая',
      'Июня',
      'Июля',
      'Августа',
      'Сентября',
      'Октября',
      'Ноября',
      'Декабря',
    ];
    return '${weekdays[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]}';
  }

  Future<void> _openSystemDialer(List<Application> allowedApps) async {
    try {
      final opened = await AppControlService.adminChannel.invokeMethod<bool>(
        'openPhoneDialer',
      );
      if (opened == true) return;
    } catch (_) {}

    _launchDockAction('dialer', allowedApps);
  }

  void _launchDockAction(String keyword, List<Application> allowedApps) {
    final List<String> keywords;
    if (keyword == 'dialer') {
      keywords = ['dialer', 'contacts', 'телефон', 'контакты'];
    } else if (keyword == 'messag') {
      keywords = ['messag', 'mms', 'sms', 'сообщения'];
    } else {
      keywords = [keyword];
    }

    for (final app in allowedApps) {
      final pkg = app.packageName.toLowerCase();
      final name = app.appName.toLowerCase();
      if (keywords.any((k) => pkg.contains(k) || name.contains(k))) {
        DeviceApps.openApp(app.packageName);
        return;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Приложение недоступно или заблокировано')),
    );
  }

  void _openTasksScreen(String currentName, String currentGender) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChildTasksScreen(
          childId: _childId,
          childName: currentName,
          gender: currentGender,
        ),
      ),
    );
  }

  Future<void> _openFamilyChat({
    required String currentName,
    required String currentGender,
    required String parentUid,
    required String chatId,
  }) async {
    final resolvedChatId = chatId.isNotEmpty
        ? chatId
        : await FamilyChatService.resolveChatIdForChild(parentUid);

    if (!mounted || resolvedChatId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Семейный чат пока недоступен')),
        );
      }
      return;
    }

    final List<String> memberIds = [_childId];
    if (parentUid.isNotEmpty) {
      memberIds.add(parentUid);
      try {
        final linkedSnap = await FirebaseDatabase.instance
            .ref('users/$parentUid/linkedParent')
            .get();
        if (linkedSnap.exists && linkedSnap.value != null) {
          final linkedUid = linkedSnap.value.toString();
          if (linkedUid.isNotEmpty) {
            memberIds.add(linkedUid);
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FamilyChatScreen(
          chatId: resolvedChatId,
          currentUserId: _childId,
          currentUserName: currentName,
          currentUserRole: 'child',
          childGender: currentGender,
          allFamilyMemberIds: memberIds,
        ),
      ),
    );
  }

  void _showAppsDrawer(AppPalette palette, List<Application> allowedApps) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        height: MediaQuery.of(context).size.height * 0.78,
        decoration: BoxDecoration(
          color: palette.background.withValues(alpha: 0.96),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(
            color: palette.primaryAccent.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: palette.textSecondary.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Разрешённые приложения',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: palette.textPrimary,
                ),
              ),
            ),
            Expanded(
              child: _isLoadingApps
                  ? Center(
                      child: CircularProgressIndicator(
                        color: palette.primaryAccent,
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.78,
                      ),
                      itemCount: allowedApps.length,
                      itemBuilder: (context, index) {
                        final app = allowedApps[index];
                        return InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            DeviceApps.openApp(app.packageName);
                          },
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 54,
                                height: 54,
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: palette.glassPanel,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: palette.primaryAccent
                                        .withValues(alpha: 0.25),
                                  ),
                                ),
                                child: app is ApplicationWithIcon
                                    ? Image.memory(
                                        app.icon,
                                        fit: BoxFit.contain,
                                      )
                                    : Icon(
                                        Icons.apps,
                                        color: palette.primaryAccent,
                                        size: 30,
                                      ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                app.appName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: palette.textPrimary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showParentAccessDialog(String parentUid) {
    final passController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings, color: Colors.blue, size: 26),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Доступ для родителя',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width,
          child: TextField(
            controller: passController,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Пароль родителя',
              prefixIcon: const Icon(Icons.lock_outline),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              final entered = passController.text.trim();
              if (entered.isEmpty) return;

              bool valid = false;
              if (parentUid.isNotEmpty) {
                final parentSnap = await FirebaseDatabase.instance
                    .ref('users/$parentUid')
                    .get();
                if (parentSnap.exists && parentSnap.value != null) {
                  final pData =
                      Map<dynamic, dynamic>.from(parentSnap.value as Map);
                  if (pData['password']?.toString() == entered) {
                    valid = true;
                  }
                }
              }

              if (!mounted) return;
              if (!valid) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Неверный пароль родителя'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
              await _refreshDefaultLauncherState();
              if (!mounted) return;
              _showParentOptionsSheet();
            },
            child: const Text('Войти'),
          ),
        ],
      ),
    ).whenComplete(passController.dispose);
  }

  void _showParentOptionsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'Настройки устройства ребёнка',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              ListTile(
                dense: true,
                leading: const Icon(Icons.home_filled, color: Colors.deepPurple),
                title: const Text(
                  'Рабочий экран по умолчанию',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  _isDefaultLauncher
                      ? 'Сейчас режим: Лаунчер FamilyPulse'
                      : 'Сейчас режим: Стандартный рабочий стол телефона',
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await AppControlService.adminChannel
                      .invokeMethod('requestDefaultLauncher');
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.verified_user, color: Colors.blue),
                title: const Text(
                  'Проверить системные разрешения',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Открыть экран проверки всех прав защиты',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChildPermissionsScreen(
                        childName: widget.childName,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.lock_open, color: Colors.orange),
                title: const Text(
                  'Разблокировать настройки на 5 минут',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Единственный режим временного доступа к настройкам телефона',
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  _manual5MinBypassActive = true;
                  Future.delayed(const Duration(minutes: 5), () {
                    _manual5MinBypassActive = false;
                  });
                  await AppControlService.adminChannel.invokeMethod(
                    'setParentBypass',
                    {'minutes': 5},
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Доступ к настройкам устройства открыт на 5 минут',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.system_update, color: Colors.green),
                title: const Text(
                  'Проверить обновления приложения',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Проверить и установить новую версию с GitHub',
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  GithubUpdateService.checkForUpdates(context, silent: false);
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.link_off, color: Colors.red),
                title: const Text(
                  'Отвязать устройство ребёнка',
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await ChatNotificationService.stopListening();
                  await LocationService.stopTracking();
                  await WebFilterService.stopFilter();
                  if (_childId.isNotEmpty) {
                    await FirebaseDatabase.instance
                        .ref('children/$_childId')
                        .update({
                      'isLinked': false,
                      'lastSeen': 0,
                    });
                  }
                  await AppControlService.adminChannel.invokeMethod(
                    'setSetupCompleted',
                    {'completed': false},
                  );
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('user_type');
                  await prefs.remove('saved_child_id');
                  await prefs.remove('saved_child_name');
                  await prefs.remove('saved_child_gender');

                  if (!mounted) return;
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const InitialSessionWrapper(),
                    ),
                    (route) => false,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isDefaultLauncher,
      child: StreamBuilder<DatabaseEvent>(
        stream: _childId.isEmpty
            ? const Stream.empty()
            : FirebaseDatabase.instance.ref('children/$_childId').onValue,
        builder: (context, snapshot) {
          Map<dynamic, dynamic> childData = {};
          if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
            childData = Map<dynamic, dynamic>.from(
              snapshot.data!.snapshot.value as Map,
            );
            _checkForceLocationCommand(childData);
          }

          final familyRole = childData['familyRole']?.toString();
          final currentGender = familyRole != null
              ? AppTheme.resolveGenderFromRole(familyRole)
              : _cachedGender;

          final palette = AppTheme.getPalette('child', gender: currentGender);

          final currentName =
              childData['name']?.toString() ?? widget.childName;
          final avatarHash = childData['avatarHash']?.toString() ?? '';
          final parentUid = childData['parentUid']?.toString() ?? '';

          final goalMap = childData['goal'] is Map
              ? Map<dynamic, dynamic>.from(childData['goal'] as Map)
              : {};
          final goalTitle = goalMap['title']?.toString() ?? 'Цель не задана';
          final goalStatus = goalMap['status']?.toString() ??
              (goalMap['title'] != null ? 'active' : 'none');
          final int currentPoints =
              int.tryParse(goalMap['current']?.toString() ?? '0') ?? 0;
          final int targetPoints =
              int.tryParse(goalMap['target']?.toString() ?? '0') ?? 0;
          final double goalProgress =
              (goalStatus == 'active' && targetPoints > 0)
                  ? (currentPoints / targetPoints).clamp(0.0, 1.0)
                  : 0.0;

          int newTasksCount = 0;
          int uncompletedTasksCount = 0;
          if (childData['tasks'] is Map) {
            final rawTasks =
                Map<dynamic, dynamic>.from(childData['tasks'] as Map);
            rawTasks.forEach((key, val) {
              if (val is Map) {
                final st = val['status']?.toString() ?? 'active';
                if (st == 'new') {
                  newTasksCount++;
                } else if (st != 'done') {
                  uncompletedTasksCount++;
                }
              }
            });
          }

          final bool hasTasks = (newTasksCount + uncompletedTasksCount) > 0;
          final String tasksStatusText;
          final Color tasksStatusColor;
          if (newTasksCount > 0) {
            tasksStatusText = newTasksCount == 1
                ? 'Есть новое задание'
                : 'Новых заданий: $newTasksCount';
            tasksStatusColor = const Color(0xFFFFD54F);
          } else if (uncompletedTasksCount > 0) {
            tasksStatusText = uncompletedTasksCount == 1
                ? 'Есть невыполненное задание'
                : 'Есть невыполненные задания ($uncompletedTasksCount)';
            tasksStatusColor = const Color(0xFFFFD54F);
          } else {
            tasksStatusText = 'Нет заданий, попроси их у родителей';
            tasksStatusColor = palette.textSecondary;
          }

          final blockedList =
              AppControlService.evaluateBlockedPackages(childData);
          final Set<String> blockedPackages = blockedList.toSet();

          AppControlService.updateNativeBlockedPackages(blockedList);
          if (_childId.isNotEmpty && childData.isNotEmpty) {
            WebFilterService.syncFromChildData(childData);
          }

          final allowedApps = _installedApps
              .where((app) => !blockedPackages.contains(app.packageName))
              .toList();

          return StreamBuilder<DatabaseEvent>(
            stream: parentUid.isEmpty
                ? const Stream.empty()
                : FirebaseDatabase.instance
                    .ref('users/$parentUid/linkedParent')
                    .onValue,
            builder: (context, linkedParentSnap) {
              final linkedParentUid =
                  linkedParentSnap.data?.snapshot.value?.toString();
              final familyChatId = FamilyChatService.resolveFamilyChatId(
                primaryParentUid: parentUid,
                linkedParentUid: linkedParentUid,
              );

              return StreamBuilder<DatabaseEvent>(
                stream: (familyChatId.isEmpty || _childId.isEmpty)
                    ? const Stream.empty()
                    : FirebaseDatabase.instance
                        .ref('familyChats/$familyChatId/unreadBy/$_childId')
                        .onValue,
                builder: (context, unreadSnap) {
                  final int unreadChatCount = int.tryParse(
                        unreadSnap.data?.snapshot.value?.toString() ?? '0',
                      ) ??
                      0;

                  return Stack(
                    children: [
                      Positioned.fill(
                        child: Image.asset(
                          palette.backgroundAsset,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(color: palette.background);
                          },
                        ),
                      ),
                      Positioned.fill(
                        child: Container(
                          color: palette.background.withValues(alpha: 0.45),
                        ),
                      ),
                      Scaffold(
                        backgroundColor: Colors.transparent,
                        body: SafeArea(
                          child: Column(
                            children: [
                              Expanded(
                                child: ListView(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 12, 16, 12),
                                  children: [
                                    _buildGlassCard(
                                      palette: palette,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 16,
                                      ),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _formatTime(_now),
                                                style: TextStyle(
                                                  fontSize: 42,
                                                  fontWeight: FontWeight.bold,
                                                  color: palette.textPrimary,
                                                  letterSpacing: 1.5,
                                                ),
                                              ),
                                              Text(
                                                _formatRussianDate(_now),
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: palette.textSecondary,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ],
                                          ),
                                          GestureDetector(
                                            onLongPress: () =>
                                                _showParentAccessDialog(
                                              parentUid,
                                            ),
                                            child: Column(
                                              children: [
                                                UserAvatarWidget(
                                                  avatarBase64: avatarHash,
                                                  radius: 26,
                                                  fallbackIcon:
                                                      Icons.child_care,
                                                  fallbackBackgroundColor:
                                                      palette.secondaryAccent
                                                          .withValues(
                                                    alpha: 0.3,
                                                  ),
                                                  fallbackIconColor:
                                                      palette.primaryAccent,
                                                  borderWidth: 2,
                                                  borderColor: _isLocationActive
                                                      ? AppTheme.successColor
                                                      : AppTheme.warningColor,
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  currentName,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: palette.textPrimary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 12),

                                    GestureDetector(
                                      onTap: () => _openTasksScreen(
                                        currentName,
                                        currentGender,
                                      ),
                                      child: _buildGlassCard(
                                        palette: palette,
                                        padding: const EdgeInsets.all(16),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 56,
                                              height: 56,
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  CircularProgressIndicator(
                                                    value:
                                                        goalStatus == 'pending'
                                                            ? null
                                                            : goalProgress,
                                                    strokeWidth:
                                                        goalStatus == 'pending'
                                                            ? 3
                                                            : 6,
                                                    backgroundColor: palette
                                                        .textSecondary
                                                        .withValues(
                                                      alpha: 0.25,
                                                    ),
                                                    valueColor:
                                                        AlwaysStoppedAnimation<
                                                            Color>(
                                                      goalStatus == 'pending'
                                                          ? AppTheme
                                                              .warningColor
                                                          : palette
                                                              .primaryAccent,
                                                    ),
                                                  ),
                                                  Center(
                                                    child: goalStatus ==
                                                            'pending'
                                                        ? Icon(
                                                            Icons
                                                                .hourglass_top_rounded,
                                                            color: AppTheme
                                                                .warningColor,
                                                            size: 22,
                                                          )
                                                        : Text(
                                                            '${(goalProgress * 100).round()}%',
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              color: palette
                                                                  .textPrimary,
                                                            ),
                                                          ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    goalStatus == 'pending'
                                                        ? 'Цель (на согласовании):'
                                                        : goalStatus ==
                                                                'rejected'
                                                            ? 'Цель отклонена:'
                                                            : 'Моя цель:',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color: goalStatus ==
                                                              'pending'
                                                          ? AppTheme
                                                              .warningColor
                                                          : goalStatus ==
                                                                  'rejected'
                                                              ? AppTheme
                                                                  .errorColor
                                                              : palette
                                                                  .textSecondary,
                                                      fontWeight: (goalStatus ==
                                                                  'pending' ||
                                                              goalStatus ==
                                                                  'rejected')
                                                          ? FontWeight.w600
                                                          : FontWeight.normal,
                                                    ),
                                                  ),
                                                  Text(
                                                    (goalStatus == 'none' ||
                                                            goalStatus ==
                                                                'completed')
                                                        ? 'Нажми, чтобы выбрать'
                                                        : goalTitle,
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color:
                                                          palette.textPrimary,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    targetPoints > 0 &&
                                                            goalStatus !=
                                                                'completed'
                                                        ? '$currentPoints / $targetPoints Б'
                                                        : 'Баллов: $currentPoints Б',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: currentPoints < 0
                                                          ? AppTheme.errorColor
                                                          : palette
                                                              .primaryAccent,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  Row(
                                                    children: [
                                                      Icon(
                                                        hasTasks
                                                            ? Icons
                                                                .notifications_active_rounded
                                                            : Icons
                                                                .info_outline_rounded,
                                                        size: 14,
                                                        color: tasksStatusColor,
                                                      ),
                                                      const SizedBox(width: 5),
                                                      Expanded(
                                                        child: Text(
                                                          tasksStatusText,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            fontSize: 12,
                                                            fontWeight: hasTasks
                                                                ? FontWeight.w600
                                                                : FontWeight
                                                                    .normal,
                                                            color:
                                                                tasksStatusColor,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Container(
                                              width: 48,
                                              height: 48,
                                              decoration: BoxDecoration(
                                                color: hasTasks
                                                    ? const Color(0xFFFFD54F)
                                                        .withValues(alpha: 0.22)
                                                    : palette.secondaryAccent
                                                        .withValues(alpha: 0.15),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: hasTasks
                                                      ? const Color(0xFFFFD54F)
                                                      : palette.textSecondary
                                                          .withValues(
                                                          alpha: 0.35,
                                                        ),
                                                  width: hasTasks ? 1.5 : 1.0,
                                                ),
                                                boxShadow: hasTasks
                                                    ? [
                                                        BoxShadow(
                                                          color: const Color(
                                                            0xFFFFD54F,
                                                          ).withValues(
                                                            alpha: 0.35,
                                                          ),
                                                          blurRadius: 10,
                                                        ),
                                                      ]
                                                    : null,
                                              ),
                                              child: Icon(
                                                hasTasks
                                                    ? Icons
                                                        .assignment_turned_in_rounded
                                                    : Icons.assignment_outlined,
                                                color: hasTasks
                                                    ? const Color(0xFFFFD54F)
                                                    : palette.textSecondary,
                                                size: 26,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              Container(
                                width: double.infinity,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color:
                                      palette.glassPanel.withValues(alpha: 0.85),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _buildDockButton(
                                        palette: palette,
                                        icon: Icons.apps_rounded,
                                        label: 'Приложения',
                                        onTap: () => _showAppsDrawer(
                                          palette,
                                          allowedApps,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: _buildDockButton(
                                        palette: palette,
                                        icon: Icons.camera_alt_rounded,
                                        label: 'Камера',
                                        onTap: () => _launchDockAction(
                                          'camera',
                                          allowedApps,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: () =>
                                            _openSystemDialer(allowedApps),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 54,
                                              height: 54,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: palette.secondaryAccent
                                                    .withValues(alpha: 0.35),
                                                border: Border.all(
                                                  color: palette.primaryAccent,
                                                  width: 2.5,
                                                ),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: palette.primaryAccent
                                                        .withValues(
                                                      alpha: 0.45,
                                                    ),
                                                    blurRadius: 12,
                                                  ),
                                                ],
                                              ),
                                              child: Icon(
                                                Icons.call_rounded,
                                                color: palette.primaryAccent,
                                                size: 28,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Телефон',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: palette.primaryAccent,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: _buildDockButton(
                                        palette: palette,
                                        icon: Icons.chat_bubble_rounded,
                                        label: 'Чат',
                                        badgeCount: unreadChatCount,
                                        onTap: () => _openFamilyChat(
                                          currentName: currentName,
                                          currentGender: currentGender,
                                          parentUid: parentUid,
                                          chatId: familyChatId,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: _buildDockButton(
                                        palette: palette,
                                        icon:
                                            Icons.assignment_turned_in_rounded,
                                        label: 'Задания',
                                        onTap: () => _openTasksScreen(
                                          currentName,
                                          currentGender,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildGlassCard({
    required AppPalette palette,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(16),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: palette.glassPanel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: palette.primaryAccent.withValues(alpha: 0.25),
          width: 1.2,
        ),
      ),
      child: child,
    );
  }

  Widget _buildDockButton({
    required AppPalette palette,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.secondaryAccent.withValues(alpha: 0.25),
                ),
                child: Icon(icon, color: palette.primaryAccent, size: 22),
              ),
              if (badgeCount > 0)
                Positioned(
                  top: -2,
                  right: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.errorColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: palette.background,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: palette.textPrimary),
          ),
        ],
      ),
    );
  }
}