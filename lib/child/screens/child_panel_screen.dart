import 'dart:async';
import 'package:flutter/services.dart';
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
import '../../core/services/launcher_storage_service.dart';
import '../../core/services/web_filter_service.dart';
import '../../features/chat/family_chat_screen.dart';
import '../../features/widgets/launcher_dock_section.dart';
import '../../features/widgets/launcher_grid_section.dart';
import '../../features/widgets/launcher_top_widget.dart';
import '../../features/auth/initial_session_wrapper.dart';
import 'child_permissions_screen.dart';
import 'child_tasks_screen.dart';
import 'launcher_layout.dart';

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
  bool _manual5MinBypassActive = false;
  int _lastHandledForceLocationAt = 0;

  String _lastAppliedBlockedSignature = '';
  String _lastAppliedWebFilterSignature = '';
  String _lastPrunedAllowedSignature = '';

  LauncherLayoutState _layoutState = const LauncherLayoutState();
  List<Application> _installedApps = [];
  Uint8List? _dialerIconBytes;
  bool _isLoadingApps = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applyLightSystemOverlay();
    _initLauncher();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _applyLightSystemOverlay() {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _applyLightSystemOverlay();
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
            .set('launcher');
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

  Future<void> _loadDialerIcon() async {
    try {
      final bytes = await AppControlService.adminChannel
          .invokeMethod<Uint8List>('getDialerIcon');
      if (mounted && bytes != null && bytes.isNotEmpty) {
        setState(() => _dialerIconBytes = bytes);
      }
    } catch (_) {}
  }

  Future<void> _initLauncher() async {
    final loadedLayout = await LauncherStorageService.loadLayout();
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString('saved_child_id') ?? '';
    final savedGender = prefs.getString('saved_child_gender') ?? 'boy';
    _lastHandledForceLocationAt =
        prefs.getInt('last_handled_force_location_at') ?? 0;

    if (mounted) {
      setState(() {
        _layoutState = loadedLayout;
        _childId = savedId;
        _cachedGender = savedGender;
      });
    }

    await _refreshDefaultLauncherState();
    await Future.wait([
      _loadDeviceApps(),
      _loadDialerIcon(),
    ]);
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
  }

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

    if (!LocationService.isTracking) {
      await LocationService.startChildLocationTracking(childId: _childId);
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
  }

  bool _sameAppLists(List<Application> a, List<Application> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].packageName != b[i].packageName ||
          a[i].appName != b[i].appName) {
        return false;
      }
    }
    return true;
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
      if (_isLoadingApps || !_sameAppLists(_installedApps, apps)) {
        setState(() {
          _installedApps = apps;
          _isLoadingApps = false;
        });
      }
    } catch (e) {
      debugPrint('Ошибка загрузки приложений: $e');
      if (mounted && _isLoadingApps) {
        setState(() => _isLoadingApps = false);
      }
    }
  }

  Future<void> _syncGridWithAllowedApps(Set<String> allowedPackageSet) async {
    final pruned = _layoutState.pruneUnavailableApps(allowedPackageSet);
    if (pruned != _layoutState) {
      await LauncherStorageService.saveLayout(pruned);
      if (mounted) {
        setState(() => _layoutState = pruned);
      }
    }
  }

  Future<void> _addShortcutToGrid(String packageName) async {
    final updated = await LauncherStorageService.addAppToGrid(packageName);
    if (!mounted) return;
    setState(() => _layoutState = updated);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ярлык добавлен на рабочий стол')),
    );
  }

  Future<void> _removeShortcutFromGrid(String packageName) async {
    final updated = await LauncherStorageService.removeAppFromGrid(packageName);
    if (!mounted) return;
    setState(() => _layoutState = updated);
  }

  Future<void> _moveShortcutToSlot(int fromIndex, int toIndex) async {
    final updated =
        await LauncherStorageService.moveAppToSlot(fromIndex, toIndex);
    if (!mounted) return;
    setState(() => _layoutState = updated);
  }

  Future<void> _moveDockSlot(int fromIndex, int toIndex) async {
    final updated = _layoutState.moveDockSlot(fromIndex, toIndex);
    if (updated != _layoutState) {
      await LauncherStorageService.saveLayout(updated);
      if (mounted) {
        setState(() => _layoutState = updated);
      }
    }
  }

  Future<void> _moveGridAppToDock(int gridIndex, {int? dockIndex}) async {
    final updated =
        _layoutState.moveGridAppToDock(gridIndex, dockIndex: dockIndex);
    if (updated != _layoutState) {
      await LauncherStorageService.saveLayout(updated);
      if (mounted) {
        setState(() => _layoutState = updated);
      }
    }
  }

  Future<void> _moveDockAppToGrid(int dockIndex, int gridIndex) async {
    final updated = _layoutState.moveDockAppToGrid(dockIndex, gridIndex);
    if (updated != _layoutState) {
      await LauncherStorageService.saveLayout(updated);
      if (mounted) {
        setState(() => _layoutState = updated);
      }
    }
  }

  Future<void> _updateDock(List<LauncherDockSlot> updatedSlots) async {
    final updated = await LauncherStorageService.updateDockSlots(updatedSlots);
    if (!mounted) return;
    setState(() => _layoutState = updated);
  }

  Future<void> _openSystemDialer(List<Application> allowedApps) async {
    try {
      final opened = await AppControlService.adminChannel.invokeMethod<bool>(
        'openPhoneDialer',
      );
      if (opened == true) return;
    } catch (_) {}

    for (final app in allowedApps) {
      final pkg = app.packageName.toLowerCase();
      final name = app.appName.toLowerCase();
      if ((pkg.contains('dialer') ||
              pkg.contains('telecom') ||
              pkg.contains('phone') ||
              name.contains('телефон') ||
              name.contains('вызовы')) &&
          !name.contains('контакты')) {
        DeviceApps.openApp(app.packageName);
        return;
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Приложение «Вызовы» недоступно')),
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

  void _showAppsDrawer(List<Application> allowedApps) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xF5181B20) : const Color(0xF8FFFFFF);
    final primaryText = isDark ? Colors.white : const Color(0xFF181A1F);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        height: MediaQuery.of(context).size.height * 0.78,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: primaryText.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Приложения',
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: primaryText,
                    ),
                  ),
                  Text(
                    'Удерживайте для ярлыка',
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 12,
                      color: primaryText.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoadingApps
                  ? const Center(child: CircularProgressIndicator())
                  : GridView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 8,
                        childAspectRatio: 0.82,
                      ),
                      itemCount: allowedApps.length,
                      itemBuilder: (context, index) {
                        final app = allowedApps[index];
                        final alreadyOnGrid =
                            _layoutState.containsOnGrid(app.packageName);
                        final Uint8List? iconBytes = app is ApplicationWithIcon
                            ? app.icon
                            : null;

                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            DeviceApps.openApp(app.packageName);
                          },
                          onLongPress: () {
                            Navigator.pop(sheetContext);
                            if (alreadyOnGrid) {
                              _removeShortcutFromGrid(app.packageName);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Ярлык «${app.appName}» убран с рабочего стола',
                                  ),
                                ),
                              );
                            } else {
                              _addShortcutToGrid(app.packageName);
                            }
                          },
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 48,
                                height: 48,
                                child: iconBytes != null
                                    ? Image.memory(
                                        iconBytes,
                                        fit: BoxFit.contain,
                                        gaplessPlayback: true,
                                      )
                                    : Icon(
                                        Icons.apps_rounded,
                                        color: primaryText,
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
                                  fontFamily: AppTheme.fontFamily,
                                  color: primaryText,
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
        title: const Text(
          'Доступ для родителя',
          style: TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
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
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
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
                      ? 'Сейчас активен лаунчер'
                      : 'Выберите лаунчер по умолчанию в настройках',
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: PopScope(
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
            final currentName =
                childData['name']?.toString() ?? widget.childName;
            final childAvatarUrl = (childData['avatarUrl'] ??
                    childData['photoUrl'] ??
                    childData['avatarBase64'] ??
                    childData['avatar'])
                ?.toString();
            final parentUid = childData['parentUid']?.toString() ?? '';

            int newTasksCount = 0;
            int activeTasksCount = 0;
            if (childData['tasks'] is Map) {
              final rawTasks =
                  Map<dynamic, dynamic>.from(childData['tasks'] as Map);
              rawTasks.forEach((_, val) {
                if (val is Map) {
                  final st = val['status']?.toString() ?? 'available';
                  if (st == 'new') {
                    newTasksCount++;
                  } else if (st != 'done') {
                    activeTasksCount++;
                  }
                }
              });
            }

            final blockedList =
                AppControlService.evaluateBlockedPackages(childData);
            final Set<String> blockedPackages = blockedList.toSet();
            final sortedBlocked = List<String>.from(blockedList)..sort();
            final blockedSignature = sortedBlocked.join(',');

            if (blockedSignature != _lastAppliedBlockedSignature) {
              _lastAppliedBlockedSignature = blockedSignature;
              AppControlService.updateNativeBlockedPackages(blockedList);
            }

            if (_childId.isNotEmpty && childData.isNotEmpty) {
              final webFilterSig = childData['webFilter']?.toString() ?? '';
              if (webFilterSig != _lastAppliedWebFilterSignature) {
                _lastAppliedWebFilterSignature = webFilterSig;
                WebFilterService.syncFromChildData(childData);
              }
            }

            final allowedApps = _installedApps
                .where((app) => !blockedPackages.contains(app.packageName))
                .toList();

            final allowedPackageSet =
                allowedApps.map((app) => app.packageName).toSet();
            if (allowedPackageSet.isNotEmpty) {
              final sortedAllowed = allowedPackageSet.toList()..sort();
              final allowedSignature = sortedAllowed.join(',');
              if (allowedSignature != _lastPrunedAllowedSignature) {
                _lastPrunedAllowedSignature = allowedSignature;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    unawaited(_syncGridWithAllowedApps(allowedPackageSet));
                  }
                });
              }
            }

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

                    return GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onVerticalDragEnd: (details) {
                        final velocity = details.primaryVelocity ?? 0;
                        if (velocity < -260) {
                          _showAppsDrawer(allowedApps);
                        }
                      },
                      child: Scaffold(
                        backgroundColor: Colors.transparent,
                        body: SafeArea(
                          child: Column(
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 10, 12, 6),
                                child: GestureDetector(
                                  onLongPress: () =>
                                      _showParentAccessDialog(parentUid),
                                  child: LauncherTopWidget(
                                    childName: currentName,
                                    childGender: currentGender,
                                    childAvatarUrl: childAvatarUrl,
                                    unreadChatCount: unreadChatCount,
                                    activeTasksCount: activeTasksCount,
                                    newTasksCount: newTasksCount,
                                    onOpenTasks: () => _openTasksScreen(
                                      currentName,
                                      currentGender,
                                    ),
                                    onOpenChat: () => _openFamilyChat(
                                      currentName: currentName,
                                      currentGender: currentGender,
                                      parentUid: parentUid,
                                      chatId: familyChatId,
                                    ),
                                    onAvatarLongPress: () =>
                                        _showParentAccessDialog(parentUid),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: LauncherGridSection(
                                  gridSlots: _layoutState.normalizedGridSlots,
                                  allowedApps: allowedApps,
                                  onLaunchApp: (pkg) => DeviceApps.openApp(pkg),
                                  onRemoveApp: _removeShortcutFromGrid,
                                  onMoveAppToSlot: _moveShortcutToSlot,
                                  onMoveDockAppToGrid: _moveDockAppToGrid,
                                ),
                              ),
                              LauncherDockSection(
                                dockSlots: _layoutState.dockSlots,
                                allowedApps: allowedApps,
                                dialerIconBytes: _dialerIconBytes,
                                onOpenDialer: () =>
                                    _openSystemDialer(allowedApps),
                                onLaunchApp: (pkg) => DeviceApps.openApp(pkg),
                                onDockChanged: _updateDock,
                                onMoveDockSlot: _moveDockSlot,
                                onMoveGridAppToDock: _moveGridAppToDock,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}