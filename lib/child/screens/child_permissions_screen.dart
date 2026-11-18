import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'child_panel_screen.dart';

import '../../core/app_theme.dart';
import '../../core/services/chat_notification_service.dart';
import '../../core/services/web_filter_service.dart';

class ChildPermissionsScreen extends StatefulWidget {
  final String childName;

  const ChildPermissionsScreen({
    super.key,
    required this.childName,
  });

  @override
  State<ChildPermissionsScreen> createState() => _ChildPermissionsScreenState();
}

class _ChildPermissionsScreenState extends State<ChildPermissionsScreen>
    with WidgetsBindingObserver {
  bool _locationAlwaysGranted = false;
  bool _notificationsGranted = false;
  bool _usageStatsGranted = false;
  bool _overlayGranted = false;
  bool _batteryGranted = false;
  bool _deviceAdminGranted = false;
  bool _accessibilityGranted = false;
  bool _vpnGranted = false;

  static const _usageChannel =
      MethodChannel('com.example.family_pulse/usage_stats');
  static const _adminChannel =
      MethodChannel('com.example.family_pulse/device_admin');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAllPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAllPermissions();
    }
  }

  Future<void> _checkAllPermissions() async {
    final locAlways = await Permission.locationAlways.isGranted;
    final notifications = await Permission.notification.isGranted;
    final overlay = await Permission.systemAlertWindow.isGranted;
    final battery = await Permission.ignoreBatteryOptimizations.isGranted;
    final vpn = await WebFilterService.checkVpnPermission();

    bool usage = false;
    bool admin = false;
    bool access = false;

    try {
      usage =
          await _usageChannel.invokeMethod<bool>('checkUsagePermission') ?? false;
    } catch (_) {}

    try {
      admin =
          await _adminChannel.invokeMethod<bool>('checkDeviceAdmin') ?? false;
    } catch (_) {}

    try {
      access =
          await _adminChannel.invokeMethod<bool>('checkAccessibility') ?? false;
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _locationAlwaysGranted = locAlways;
      _notificationsGranted = notifications;
      _usageStatsGranted = usage;
      _overlayGranted = overlay;
      _batteryGranted = battery;
      _deviceAdminGranted = admin;
      _accessibilityGranted = access;
      _vpnGranted = vpn;
    });
  }

  Future<void> _requestPermissionSafely(
    MethodChannel channel,
    String method,
  ) async {
    try {
      await channel.invokeMethod(method);
    } catch (e) {
      debugPrint('[Permissions] Ошибка вызова $method:$e');
      await openAppSettings();
    }
  }

  Future<void> _requestLocation() async {
    final status = await Permission.location.request();
    if (status.isGranted) {
      await Permission.locationAlways.request();
    } else if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
    _checkAllPermissions();
  }

  Future<void> _requestNotifications() async {
    final granted = await ChatNotificationService.requestPermission();
    if (!granted && await Permission.notification.isPermanentlyDenied) {
      await openAppSettings();
    }
    _checkAllPermissions();
  }

  Future<void> _requestBattery() async {
    try {
      await Permission.ignoreBatteryOptimizations.request();
    } catch (_) {
      await openAppSettings();
    }
    _checkAllPermissions();
  }

  Future<void> _requestOverlay() async {
    await _requestPermissionSafely(_adminChannel, 'requestOverlayPermission');
    _checkAllPermissions();
  }

  Future<void> _requestVpn() async {
    await WebFilterService.requestVpnPermission();
    _checkAllPermissions();
  }

  bool get _allRequiredGranted =>
      _locationAlwaysGranted &&
      _notificationsGranted &&
      _usageStatsGranted &&
      _overlayGranted &&
      _batteryGranted &&
      _deviceAdminGranted &&
      _accessibilityGranted &&
      _vpnGranted;

  Future<void> _proceedToPanel() async {
    if (!_allRequiredGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Активируйте все 8 пунктов защиты перед продолжением'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      await _adminChannel.invokeMethod('setSetupCompleted', {'completed': true});
    } catch (e) {
      debugPrint('[Permissions] Ошибка установки setup_completed: $e');
    }

    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => ChildPanelScreen(childName: widget.childName),
      ),
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
              'Настройка защиты',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Для защиты от удаления и контроля приложений активируйте все права:',
                    style: TextStyle(fontSize: 14, color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      children: [
                        _buildPermCard(
                          granted: _locationAlwaysGranted,
                          icon: Icons.location_on,
                          color: Colors.orange,
                          title: 'Геолокация (Всегда)',
                          subtitle: 'Фоновое отслеживание координат',
                          onTap: _requestLocation,
                        ),
                        _buildPermCard(
                          granted: _notificationsGranted,
                          icon: Icons.notifications_active_rounded,
                          color: Colors.amber.shade700,
                          title: 'Уведомления семейного чата',
                          subtitle: 'Сообщения и новые задания от родителей',
                          onTap: _requestNotifications,
                        ),
                        _buildPermCard(
                          granted: _batteryGranted,
                          icon: Icons.battery_saver,
                          color: Colors.teal,
                          title: 'Работа без ограничений',
                          subtitle: 'Исключить из оптимизации батареи',
                          onTap: _requestBattery,
                        ),
                        _buildPermCard(
                          granted: _usageStatsGranted,
                          icon: Icons.bar_chart,
                          color: Colors.indigo,
                          title: 'Статистика использования',
                          subtitle: 'Контроль экранного времени',
                          onTap: () => _requestPermissionSafely(
                            _usageChannel,
                            'requestUsagePermission',
                          ),
                        ),
                        _buildPermCard(
                          granted: _overlayGranted,
                          icon: Icons.layers,
                          color: Colors.purple,
                          title: 'Поверх других окон',
                          subtitle: 'Экран блокировки при лимитах',
                          onTap: _requestOverlay,
                        ),
                        _buildPermCard(
                          granted: _deviceAdminGranted,
                          icon: Icons.admin_panel_settings,
                          color: Colors.redAccent,
                          title: 'Администратор устройства',
                          subtitle: 'Запрет на удаление приложения',
                          onTap: () => _requestPermissionSafely(
                            _adminChannel,
                            'requestDeviceAdmin',
                          ),
                        ),
                        _buildPermCard(
                          granted: _accessibilityGranted,
                          icon: Icons.accessibility_new,
                          color: Colors.blue,
                          title: 'Служба доступности',
                          subtitle: 'Защита настроек от отключения',
                          onTap: () => _requestPermissionSafely(
                            _adminChannel,
                            'requestAccessibility',
                          ),
                        ),
                        _buildPermCard(
                          granted: _vpnGranted,
                          icon: Icons.vpn_lock_rounded,
                          color: Colors.cyan.shade700,
                          title: 'Защита интернета (VPN-фильтр)',
                          subtitle: 'Блокировка сайтов 18+ и безопасный поиск',
                          onTap: _requestVpn,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      backgroundColor: _allRequiredGranted
                          ? Colors.green.shade600
                          : Colors.blue.shade700.withValues(alpha: 0.9),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    onPressed: _proceedToPanel,
                    child: const Text(
                      'ЗАВЕРШИТЬ НАСТРОЙКУ ЗАЩИТЫ',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPermCard({
    required bool granted,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white.withValues(alpha: 0.92),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: Icon(
          granted ? Icons.check_circle : icon,
          color: granted ? Colors.green : color,
          size: 30,
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor:
                granted ? Colors.green.shade50 : Colors.blue.shade700,
            foregroundColor: granted ? Colors.green.shade700 : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          onPressed: onTap,
          child: Text(granted ? 'Готово' : 'Включить'),
        ),
      ),
    );
  }
}