import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';

class WebFilterService {
  static const MethodChannel _adminChannel =
      MethodChannel('com.example.family_pulse/device_admin');

  static String _lastAppliedSignature = '';

  /// Проверка, выдано ли системное разрешение на локальный VPN
  static Future<bool> checkVpnPermission() async {
    try {
      return await _adminChannel.invokeMethod<bool>('checkVpnPermission') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// Запрос системного диалога разрешения VPN
  static Future<bool> requestVpnPermission() async {
    try {
      return await _adminChannel.invokeMethod<bool>('requestVpnPermission') ??
          false;
    } catch (e) {
      debugPrint('[WebFilterService] Ошибка запроса VPN: $e');
      return false;
    }
  }

  /// Проверка, запущен ли сейчас нативный FamilyVpnService
  static Future<bool> isVpnActive() async {
    try {
      return await _adminChannel.invokeMethod<bool>('isVpnActive') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Парсинг списка доменов из узла Firebase (Map или List)
  static List<String> extractDomains(dynamic rawNode) {
    final Set<String> domains = {};
    if (rawNode is Map) {
      rawNode.forEach((_, val) {
        final d = normalizeDomain(val?.toString() ?? '');
        if (d.isNotEmpty) domains.add(d);
      });
    } else if (rawNode is List) {
      for (final item in rawNode) {
        final d = normalizeDomain(item?.toString() ?? '');
        if (d.isNotEmpty) domains.add(d);
      }
    }
    final list = domains.toList()..sort();
    return list;
  }

  static String normalizeDomain(String raw) {
    var d = raw.trim().toLowerCase();
    if (d.startsWith('https://')) d = d.substring(8);
    if (d.startsWith('http://')) d = d.substring(7);
    if (d.startsWith('www.')) d = d.substring(4);
    final slashIdx = d.indexOf('/');
    if (slashIdx != -1) d = d.substring(0, slashIdx);
    final queryIdx = d.indexOf('?');
    if (queryIdx != -1) d = d.substring(0, queryIdx);
    while (d.endsWith('.')) {
      d = d.substring(0, d.length - 1);
    }
    return d;
  }

  /// Безопасный ключ для сохранения домена в Firebase RTDB (заменяет точки и запрещённые символы)
  static String domainToFirebaseKey(String domain) {
    return normalizeDomain(domain).replaceAll(RegExp(r'[.#$\[\]/]'), '_');
  }

  /// Синхронизация правил из снимка профиля ребёнка (`children/$childId`) в нативный VPN-сервис
  static Future<void> syncFromChildData(
    Map<dynamic, dynamic> childData, {
    bool force = false,
  }) async {
    final filterMap = childData['webFilter'] is Map
        ? Map<dynamic, dynamic>.from(childData['webFilter'] as Map)
        : <dynamic, dynamic>{};

    // По умолчанию защита активна (блокирует 18+ и включает SafeSearch), если родитель явно не выключил
    final bool enabled = filterMap['enabled'] != false;
    final String mode =
        filterMap['mode']?.toString() == 'whitelist' ? 'whitelist' : 'blacklist';
    final bool blockAdult = filterMap['blockAdult'] != false;
    final List<String> blockedDomains =
        extractDomains(filterMap['blockedDomains']);
    final List<String> allowedDomains =
        extractDomains(filterMap['allowedDomains']);

    final signature =
        '$enabled|$mode|$blockAdult|${blockedDomains.join(",")}|${allowedDomains.join(",")}';

    if (!force && signature == _lastAppliedSignature) {
      if (enabled) {
        final active = await isVpnActive();
        if (active) return;
      } else {
        return;
      }
    }

    try {
      await _adminChannel.invokeMethod('updateWebFilterRules', {
        'enabled': enabled,
        'mode': mode,
        'blockAdult': blockAdult,
        'blockedDomains': blockedDomains,
        'allowedDomains': allowedDomains,
      });
      _lastAppliedSignature = signature;
    } catch (e) {
      debugPrint('[WebFilterService] Ошибка синхронизации правил VPN: $e');
    }
  }

  /// Остановка веб-фильтра (при отвязке устройства ребёнка)
  static Future<void> stopFilter() async {
    _lastAppliedSignature = '';
    try {
      await _adminChannel.invokeMethod('stopWebFilter');
    } catch (_) {}
  }

  /// Сохранение базовых переключателей фильтра со стороны родителя
  static Future<void> updateFilterSettings({
    required String childId,
    required bool enabled,
    required String mode,
    required bool blockAdult,
  }) async {
    if (childId.isEmpty) return;
    await FirebaseDatabase.instance.ref('children/$childId/webFilter').update({
      'enabled': enabled,
      'mode': mode,
      'blockAdult': blockAdult,
      'updatedAt': ServerValue.timestamp,
    });
  }

  /// Добавление домена в чёрный или белый список
  static Future<void> addDomain({
    required String childId,
    required String listType, // 'blockedDomains' или 'allowedDomains'
    required String rawDomain,
  }) async {
    final clean = normalizeDomain(rawDomain);
    if (childId.isEmpty || clean.isEmpty || !clean.contains('.')) return;
    final key = domainToFirebaseKey(clean);
    await FirebaseDatabase.instance
        .ref('children/$childId/webFilter/$listType/$key')
        .set(clean);
  }

  /// Удаление домена из списка
  static Future<void> removeDomain({
    required String childId,
    required String listType,
    required String domain,
  }) async {
    if (childId.isEmpty) return;
    final key = domainToFirebaseKey(domain);
    await FirebaseDatabase.instance
        .ref('children/$childId/webFilter/$listType/$key')
        .remove();
  }
}