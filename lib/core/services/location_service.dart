import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:battery_plus/battery_plus.dart';

import 'app_control_service.dart';
import 'daily_tasks_service.dart';
import 'family_chat_service.dart';
import 'web_filter_service.dart';

class _CachedGeofence {
  final String id;
  final String title;
  final double latitude;
  final double longitude;
  final double radius;

  const _CachedGeofence({
    required this.id,
    required this.title,
    required this.latitude,
    required this.longitude,
    required this.radius,
  });
}

class _HistoryCandidate {
  final double latitude;
  final double longitude;
  final double accuracy;
  final double speed;
  final int batteryLevel;
  final String? geofenceTitle;
  final int timestampMs;

  const _HistoryCandidate({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.speed,
    required this.batteryLevel,
    this.geofenceTitle,
    required this.timestampMs,
  });
}

class LocationService {
  static StreamSubscription<Position>? _positionSubscription;
  static StreamSubscription<DatabaseEvent>? _geofencesSubscription;
  static StreamSubscription<DatabaseEvent>? _childRulesSubscription;
  static Timer? _realtimeProtectionTimer;
  static Timer? _heartbeatTimer;
  static Timer? _selfDiagnosticsTimer;

  static bool _isTracking = false;
  static bool _isSendingImmediate = false;
  static int _lastHandledForceLocationAt = 0;
  static Map<dynamic, dynamic> _latestChildData = {};
  static final Battery _battery = Battery();

  /// Последняя подтверждённая (записанная в БД) точка маршрута (точка A)
  static _HistoryCandidate? _committedHistoryPoint;

  /// Точка-кандидат на проверку GPS-выброса (точка B, ждёт подтверждения точкой C)
  static _HistoryCandidate? _pendingHistoryPoint;

  static List<_CachedGeofence> _geofencesCache = [];
  static bool _geofencesLoaded = false;

  static final Map<String, bool> _insideGeofenceState = {};
  static String? _lockedGeofenceId;
  static const double _exitHysteresisMeters = 15.0;

  static bool get isTracking => _isTracking;

  static Future<bool> checkAndRequestPermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return false;
    }

    return true;
  }

  static Future<void> ensureRealtimeProtectionSubscribed(String childId) async {
    if (childId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    _lastHandledForceLocationAt =
        prefs.getInt('last_handled_force_location_at') ?? 0;

    final db = FirebaseDatabase.instance;

    if (_childRulesSubscription == null) {
      try {
        final initialSnap = await db.ref('children/$childId').get();
        if (initialSnap.exists && initialSnap.value is Map) {
          await _applyChildRulesSnapshot(
            childId,
            Map<dynamic, dynamic>.from(initialSnap.value as Map),
          );
        }
      } catch (e) {
        debugPrint('[LocationService] Ошибка первичной загрузки правил: $e');
      }

      _childRulesSubscription = db.ref('children/$childId').onValue.listen(
        (DatabaseEvent event) async {
          if (event.snapshot.exists && event.snapshot.value is Map) {
            await _applyChildRulesSnapshot(
              childId,
              Map<dynamic, dynamic>.from(event.snapshot.value as Map),
            );
          }
        },
        onError: (e) {
          debugPrint('[LocationService] Ошибка потока правил ребёнка: $e');
        },
      );
    }

    _realtimeProtectionTimer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) async {
        await AppControlService.syncInstalledApps();
        if (_latestChildData.isNotEmpty) {
          final blocked =
              AppControlService.evaluateBlockedPackages(_latestChildData);
          await AppControlService.updateNativeBlockedPackages(blocked);
        }
      },
    );

    _heartbeatTimer ??= Timer.periodic(
      const Duration(seconds: 45),
      (_) async {
        try {
          await db.ref('children/$childId/lastSeen').set(ServerValue.timestamp);
        } catch (_) {}
      },
    );

    if (_selfDiagnosticsTimer == null) {
      Future.delayed(const Duration(seconds: 20), () {
        runChildSelfDiagnostics(childId);
      });
      _selfDiagnosticsTimer = Timer.periodic(
        const Duration(minutes: 10),
        (_) => runChildSelfDiagnostics(childId),
      );
    }
  }

  static Future<void> runChildSelfDiagnostics(String childId) async {
    if (childId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final channel = AppControlService.adminChannel;
      const usageChannel =
          MethodChannel('com.example.family_pulse/usage_stats');

      final bool isAccessibilityOk =
          await channel.invokeMethod<bool>('checkAccessibility') ?? false;
      final bool isDeviceAdminOk =
          await channel.invokeMethod<bool>('checkDeviceAdmin') ?? false;
      final bool isUsageOk =
          await usageChannel.invokeMethod<bool>('checkUsagePermission') ??
              false;
      final bool isOverlayOk =
          await channel.invokeMethod<bool>('checkOverlayPermission') ?? false;
      final bool isGpsEnabled = await Geolocator.isLocationServiceEnabled();
      final LocationPermission locPerm = await Geolocator.checkPermission();
      final bool isLocationAlwaysOk = locPerm == LocationPermission.always;
      final bool isNotifOk = await Permission.notification.isGranted;

      final checks = <String, ({bool ok, String failMsg, String okMsg})>{
        'accessibility': (
          ok: isAccessibilityOk,
          failMsg:
              'отключена «Служба доступности» — блокировка приложений не работает',
          okMsg: '«Служба доступности» снова включена',
        ),
        'device_admin': (
          ok: isDeviceAdminOk,
          failMsg: 'отключены права «Администратора устройства»',
          okMsg: 'права «Администратора устройства» восстановлены',
        ),
        'usage_stats': (
          ok: isUsageOk,
          failMsg:
              'отключён доступ к «Статистике использования» — лимиты времени не считаются',
          okMsg: 'доступ к «Статистике использования» восстановлен',
        ),
        'overlay': (
          ok: isOverlayOk,
          failMsg: 'отключено разрешение «Поверх других окон»',
          okMsg: 'разрешение «Поверх других окон» восстановлено',
        ),
        'gps_service': (
          ok: isGpsEnabled,
          failMsg: 'выключена геолокация (GPS) на телефоне',
          okMsg: 'геолокация (GPS) снова включена',
        ),
        'location_always': (
          ok: isLocationAlwaysOk,
          failMsg:
              'геолокация не в режиме «Разрешить в любом режиме» — возможны обрывы в фоне',
          okMsg: 'фоновый доступ к геолокации восстановлен',
        ),
        'notifications': (
          ok: isNotifOk,
          failMsg: 'выключены уведомления для FamilyPulse',
          okMsg: 'уведомления для FamilyPulse снова включены',
        ),
      };

      final List<String> alertsToSend = [];
      for (final entry in checks.entries) {
        final key = 'diag_alert_active_${childId}_${entry.key}';
        final wasAlertActive = prefs.getBool(key) ?? false;

        if (!entry.value.ok && !wasAlertActive) {
          await prefs.setBool(key, true);
          alertsToSend.add('⚠️ На устройстве ребёнка ${entry.value.failMsg}');
        } else if (entry.value.ok && wasAlertActive) {
          await prefs.setBool(key, false);
          alertsToSend.add('✅ На устройстве ребёнка ${entry.value.okMsg}');
        }
      }

      if (alertsToSend.isEmpty) return;

      final childSnap =
          await FirebaseDatabase.instance.ref('children/$childId').get();
      if (!childSnap.exists || childSnap.value is! Map) return;
      final childData = Map<dynamic, dynamic>.from(childSnap.value as Map);
      final childName = childData['name']?.toString() ?? 'Ребёнок';
      final parentUid = childData['parentUid']?.toString() ?? '';
      if (parentUid.isEmpty) return;

      final chatId = await FamilyChatService.resolveChatIdForChild(parentUid);
      if (chatId.isEmpty) return;

      final memberIds = await FamilyChatService.resolveAllFamilyMemberIds(
        primaryParentUid: parentUid,
      );

      for (final rawText in alertsToSend) {
        final text = rawText.replaceFirst('ребёнка', childName);
        await FamilyChatService.sendSystemEvent(
          chatId: chatId,
          text: text,
          notifyMemberIds: memberIds,
          excludeMemberId: childId,
        );
      }
    } catch (e) {
      debugPrint('[LocationService] Ошибка самодиагностики: $e');
    }
  }

  static Future<void> _applyChildRulesSnapshot(
    String childId,
    Map<dynamic, dynamic> childData,
  ) async {
    _latestChildData = childData;

    final blockedList = AppControlService.evaluateBlockedPackages(childData);
    await AppControlService.updateNativeBlockedPackages(blockedList);

    await WebFilterService.syncFromChildData(childData);

    if (childData['commands'] is Map) {
      final commands = Map<dynamic, dynamic>.from(childData['commands'] as Map);
      final int forceAt =
          int.tryParse(commands['forceLocationAt']?.toString() ?? '0') ?? 0;
      if (forceAt > _lastHandledForceLocationAt) {
        _lastHandledForceLocationAt = forceAt;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('last_handled_force_location_at', forceAt);
        unawaited(sendImmediateLocationUpdate(childId: childId));
      }
    }
  }

  static Future<void> _ensureGeofencesSubscribed(String childId) async {
    if (_geofencesSubscription != null && _geofencesLoaded) return;

    await _geofencesSubscription?.cancel();
    _geofencesLoaded = false;

    final db = FirebaseDatabase.instance;

    try {
      final initialSnap = await db.ref('children/$childId/geofences').get();
      _applyGeofencesSnapshot(initialSnap, childId);
    } catch (e) {
      debugPrint('[LocationService] Ошибка первичной загрузки геозон: $e');
    }

    _geofencesSubscription =
        db.ref('children/$childId/geofences').onValue.listen(
      (DatabaseEvent event) {
        _applyGeofencesSnapshot(event.snapshot, childId);
      },
      onError: (e) {
        debugPrint('[LocationService] Ошибка потока геозон: $e');
      },
    );
  }

  static void _applyGeofencesSnapshot(DataSnapshot snapshot, String childId) {
    final List<_CachedGeofence> loaded = [];
    final activeZoneIds = <String>{};

    if (snapshot.exists && snapshot.value is Map) {
      final rawZones = Map<dynamic, dynamic>.from(snapshot.value as Map);
      rawZones.forEach((key, val) {
        if (val is! Map) return;
        final zoneId = key.toString();
        final zLat = double.tryParse(val['latitude']?.toString() ?? '');
        final zLng = double.tryParse(val['longitude']?.toString() ?? '');
        final radius =
            double.tryParse(val['radius']?.toString() ?? '150') ?? 150.0;
        final title = val['title']?.toString() ?? 'Точка';

        if (zLat != null && zLng != null) {
          activeZoneIds.add(zoneId);
          loaded.add(
            _CachedGeofence(
              id: zoneId,
              title: title,
              latitude: zLat,
              longitude: zLng,
              radius: radius,
            ),
          );
        }
      });
    }

    _geofencesCache = loaded;
    _geofencesLoaded = true;

    _insideGeofenceState.removeWhere((id, _) => !activeZoneIds.contains(id));
    if (_lockedGeofenceId != null &&
        !activeZoneIds.contains(_lockedGeofenceId)) {
      _lockedGeofenceId = null;
    }
  }

  static Future<bool> sendImmediateLocationUpdate({String? childId}) async {
    if (_isSendingImmediate) return false;
    _isSendingImmediate = true;

    try {
      String? targetChildId = childId;
      if (targetChildId == null || targetChildId.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        targetChildId = prefs.getString('saved_child_id');
      }

      if (targetChildId == null || targetChildId.isEmpty) {
        return false;
      }

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return false;
      }

      await _ensureGeofencesSubscribed(targetChildId);

      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 10),
          ),
        );
      } catch (e) {
        position = await Geolocator.getLastKnownPosition();
      }

      if (position != null) {
        await _sendDataToFirebase(
          targetChildId,
          position,
          forceHistory: true,
          forceWrite: true,
        );
        return true;
      }
      return false;
    } finally {
      _isSendingImmediate = false;
    }
  }

  static Future<bool> startChildLocationTracking({String? childId}) async {
    String? targetChildId = childId;
    if (targetChildId == null || targetChildId.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      targetChildId = prefs.getString('saved_child_id');
    }

    if (targetChildId == null || targetChildId.isEmpty) {
      return false;
    }

    await ensureRealtimeProtectionSubscribed(targetChildId);
    unawaited(AppControlService.syncInstalledApps());
    unawaited(DailyTasksService.processDailyTasks(targetChildId));

    if (_isTracking) return true;

    final hasPermission = await checkAndRequestPermissions();
    if (!hasPermission) {
      return false;
    }

    await _ensureGeofencesSubscribed(targetChildId);

    try {
      final initialPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      await _sendDataToFirebase(
        targetChildId,
        initialPosition,
        forceHistory: true,
        forceWrite: true,
      );
    } catch (e) {
      debugPrint('[LocationService] Ошибка получения стартовой позиции: $e');
    }

    late LocationSettings locationSettings;

    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
        intervalDuration: const Duration(seconds: 30),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'FamilyPulse активен',
          notificationText:
              'Защита устройства и контроль правил в реальном времени',
          enableWakeLock: true,
        ),
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 20,
      );
    }

    await _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) {
        _sendDataToFirebase(targetChildId!, position);
      },
      onError: (error) {
        debugPrint('[LocationService] Ошибка потока геолокации: $error');
      },
    );

    _isTracking = true;
    return true;
  }

  static String _buildDateKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static _CachedGeofence? _resolveCurrentGeofence(
    double lat,
    double lng,
    double accuracy,
  ) {
    if (_geofencesCache.isEmpty || accuracy > 80) return null;

    if (_lockedGeofenceId != null) {
      for (final zone in _geofencesCache) {
        if (zone.id == _lockedGeofenceId) {
          final dist = Geolocator.distanceBetween(
            lat,
            lng,
            zone.latitude,
            zone.longitude,
          );
          if (dist <= zone.radius + _exitHysteresisMeters) {
            return zone;
          }
          break;
        }
      }
    }

    for (final zone in _geofencesCache) {
      final dist = Geolocator.distanceBetween(
        lat,
        lng,
        zone.latitude,
        zone.longitude,
      );
      if (dist <= zone.radius) {
        return zone;
      }
    }

    return null;
  }

  /// Запись точки в Firebase
  static Future<void> _writeHistoryCandidate(
    String childId,
    _HistoryCandidate point,
  ) async {
    final dt = DateTime.fromMillisecondsSinceEpoch(point.timestampMs);
    final dateKey = _buildDateKey(dt);
    await FirebaseDatabase.instance
        .ref('children/$childId/locationHistory/$dateKey')
        .push()
        .set({
      'latitude': point.latitude,
      'longitude': point.longitude,
      'accuracy': point.accuracy,
      'speed': point.speed,
      'batteryLevel': point.batteryLevel,
      if (point.geofenceTitle != null) 'geofenceTitle': point.geofenceTitle,
      'timestamp': point.timestampMs,
    });
    _committedHistoryPoint = point;
  }

  /// Проверяет, является ли точка B GPS-выбросом («лучом») между точками A и C
  static bool _isGpsSpike({
    required _HistoryCandidate a,
    required _HistoryCandidate b,
    required _HistoryCandidate c,
  }) {
    final double distAB = Geolocator.distanceBetween(
      a.latitude,
      a.longitude,
      b.latitude,
      b.longitude,
    );
    final double distAC = Geolocator.distanceBetween(
      a.latitude,
      a.longitude,
      c.latitude,
      c.longitude,
    );
    final double distBC = Geolocator.distanceBetween(
      b.latitude,
      b.longitude,
      c.latitude,
      c.longitude,
    );

    final double dtACSec = (c.timestampMs - a.timestampMs) / 1000.0;
    final double dtABSec = (b.timestampMs - a.timestampMs) / 1000.0;

    // 1. Классический «луч»: выпрыгнул из A на >100 м и за <= 3 минуты вернулся обратно в радиус 60 м от A
    if (distAB > 100.0 && distAC <= 60.0 && dtACSec <= 180.0) {
      return true;
    }

    // 2. Нереальная телепортация (> 35 м/с ≈ 126 км/ч) на коротком отрезке с возвратом
    if (dtABSec > 0 && (distAB / dtABSec) > 35.0 && distBC > 100.0) {
      return true;
    }

    return false;
  }

  /// Запись текущих координат и фильтрация дубликатов/выбросов маршрута
  static Future<void> _sendDataToFirebase(
    String childId,
    Position position, {
    bool forceHistory = false,
    bool forceWrite = false,
  }) async {
    try {
      // Отбрасываем заведомо грубые вышки сотовой связи (accuracy > 75 м), чтобы не плодить «лучи»
      if (!forceWrite && position.accuracy > 75.0) {
        return;
      }

      final _CachedGeofence? activeZone = _resolveCurrentGeofence(
        position.latitude,
        position.longitude,
        position.accuracy,
      );

      if (!forceWrite &&
          activeZone != null &&
          _lockedGeofenceId == activeZone.id) {
        return;
      }

      if (position.accuracy <= 75.0) {
        await _checkGeofencesAndNotify(childId, position);
      }

      final double outLat =
          activeZone != null ? activeZone.latitude : position.latitude;
      final double outLng =
          activeZone != null ? activeZone.longitude : position.longitude;
      final double outSpeed = activeZone != null ? 0.0 : position.speed;
      final bool isEnteringZone =
          activeZone != null && _lockedGeofenceId != activeZone.id;

      _lockedGeofenceId = activeZone?.id;

      int batteryLevel = 100;
      bool isCharging = false;

      try {
        batteryLevel = await _battery.batteryLevel;
        final batteryState = await _battery.batteryState;
        isCharging = batteryState == BatteryState.charging ||
            batteryState == BatteryState.full;
      } catch (_) {}

      final db = FirebaseDatabase.instance;
      await db.ref('children/$childId/location').update({
        'latitude': outLat,
        'longitude': outLng,
        'accuracy': position.accuracy,
        'speed': outSpeed,
        'batteryLevel': batteryLevel,
        'isCharging': isCharging,
        'activeGeofenceId': activeZone?.id,
        'activeGeofenceTitle': activeZone?.title,
        'timestamp': ServerValue.timestamp,
      });

      final int nowMs = DateTime.now().millisecondsSinceEpoch;
      final candidate = _HistoryCandidate(
        latitude: outLat,
        longitude: outLng,
        accuracy: position.accuracy,
        speed: outSpeed,
        batteryLevel: batteryLevel,
        geofenceTitle: activeZone?.title,
        timestampMs: nowMs,
      );

      // Анти-дубликат стоянок: если ребёнок стоит на месте (< 30 м от последней точки) — не дублируем!
      final _HistoryCandidate? referencePoint =
          _pendingHistoryPoint ?? _committedHistoryPoint;
      if (!forceHistory && !isEnteringZone && referencePoint != null) {
        final double movedMeters = Geolocator.distanceBetween(
          referencePoint.latitude,
          referencePoint.longitude,
          candidate.latitude,
          candidate.longitude,
        );
        if (movedMeters < 30.0) {
          return;
        }
      }

      // Если это самая первая точка или принудительный/геозонный переход — фиксируем сразу
      if (_committedHistoryPoint == null || forceHistory || isEnteringZone) {
        if (_pendingHistoryPoint != null && _committedHistoryPoint != null) {
          if (!_isGpsSpike(
            a: _committedHistoryPoint!,
            b: _pendingHistoryPoint!,
            c: candidate,
          )) {
            await _writeHistoryCandidate(childId, _pendingHistoryPoint!);
          }
          _pendingHistoryPoint = null;
        }
        await _writeHistoryCandidate(childId, candidate);
        return;
      }

      // Буфер на 1 шаг для отлова GPS-лучей (A -> B -> C)
      if (_pendingHistoryPoint == null) {
        _pendingHistoryPoint = candidate;
      } else {
        final bool spike = _isGpsSpike(
          a: _committedHistoryPoint!,
          b: _pendingHistoryPoint!,
          c: candidate,
        );

        if (spike) {
          debugPrint('[LocationService] Отфильтрован GPS-выброс (луч) в маршруте');
          // Точку B выкидываем; если C ушла от A >= 30 м, она становится новым кандидатом B
          final double distFromA = Geolocator.distanceBetween(
            _committedHistoryPoint!.latitude,
            _committedHistoryPoint!.longitude,
            candidate.latitude,
            candidate.longitude,
          );
          _pendingHistoryPoint = distFromA >= 30.0 ? candidate : null;
        } else {
          // Точка B подтверждена — записываем её в историю, а C ставим в ожидание
          await _writeHistoryCandidate(childId, _pendingHistoryPoint!);
          _pendingHistoryPoint = candidate;
        }
      }
    } catch (e) {
      debugPrint('[LocationService] Ошибка записи в БД: $e');
    }
  }

  static Future<void> _checkGeofencesAndNotify(
    String childId,
    Position position,
  ) async {
    try {
      if (_geofencesCache.isEmpty) {
        _insideGeofenceState.clear();
        return;
      }

      final List<String> eventsToSend = [];

      for (final zone in _geofencesCache) {
        final distance = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          zone.latitude,
          zone.longitude,
        );

        final bool? prevInside = _insideGeofenceState[zone.id];
        if (prevInside == null) {
          _insideGeofenceState[zone.id] = distance <= zone.radius;
        } else if (!prevInside && distance <= zone.radius) {
          _insideGeofenceState[zone.id] = true;
          eventsToSend.add('в геозону «${zone.title}»');
        } else if (prevInside &&
            distance > (zone.radius + _exitHysteresisMeters)) {
          _insideGeofenceState[zone.id] = false;
          eventsToSend.add('из геозоны «${zone.title}»');
        }
      }

      if (eventsToSend.isEmpty) return;

      final childSnap =
          await FirebaseDatabase.instance.ref('children/$childId').get();
      if (!childSnap.exists || childSnap.value is! Map) return;

      final childData = Map<dynamic, dynamic>.from(childSnap.value as Map);
      final childName = childData['name']?.toString() ?? 'Ребёнок';
      final parentUid = childData['parentUid']?.toString() ?? '';
      if (parentUid.isEmpty) return;

      final chatId = await FamilyChatService.resolveChatIdForChild(parentUid);
      if (chatId.isEmpty) return;

      final memberIds = await FamilyChatService.resolveAllFamilyMemberIds(
        primaryParentUid: parentUid,
      );

      for (final suffix in eventsToSend) {
        final isEnter = suffix.startsWith('в ');
        final eventText = isEnter
            ? '📍 $childName вошёл(ла) $suffix'
            : '🚶 $childName покинул(а) $suffix';

        await FamilyChatService.sendSystemEvent(
          chatId: chatId,
          text: eventText,
          notifyMemberIds: memberIds,
          excludeMemberId: childId,
        );
      }
    } catch (e) {
      debugPrint('[LocationService] Ошибка проверки геозон: $e');
    }
  }

  static Future<void> stopTracking() async {
    _realtimeProtectionTimer?.cancel();
    _realtimeProtectionTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _selfDiagnosticsTimer?.cancel();
    _selfDiagnosticsTimer = null;

    await _childRulesSubscription?.cancel();
    _childRulesSubscription = null;
    _latestChildData = {};

    await _positionSubscription?.cancel();
    await _geofencesSubscription?.cancel();
    _positionSubscription = null;
    _geofencesSubscription = null;
    _isTracking = false;
    _geofencesLoaded = false;
    _geofencesCache = [];
    _insideGeofenceState.clear();
    _lockedGeofenceId = null;
    _committedHistoryPoint = null;
    _pendingHistoryPoint = null;
  }
}