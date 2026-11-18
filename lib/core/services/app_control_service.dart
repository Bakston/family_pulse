import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:device_apps_ng/device_apps_ng.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppControlService {
  static const platform = MethodChannel('com.example.family_pulse/usage_stats');
  static const adminChannel = MethodChannel('com.example.family_pulse/device_admin');

  static const List<String> defaultCategoryIds = ['games', 'social', 'study', 'other'];

  static const Map<String, String> defaultCategoryTitles = {
    'games': 'Игры',
    'social': 'Соцсети',
    'study': 'Учёба',
    'other': 'Прочее',
  };

  /// Критические системные пакеты, которые по умолчанию заблокированы для ребёнка
  static const Set<String> restrictedSystemPackages = {
    'com.familypulse.app',
    'com.android.settings',
    'com.android.vending',
    'com.google.android.packageinstaller',
    'com.android.packageinstaller',
    'com.miui.securitycenter',
    'com.coloros.safecenter',
    'com.huawei.systemmanager',
  };

  /// Форматирование минут в вид "00ч 00м"
  static String formatTotalDuration(int totalMinutes) {
    final safe = totalMinutes < 0 ? 0 : totalMinutes;
    final h = (safe ~/ 60).toString().padLeft(2, '0');
    final m = (safe % 60).toString().padLeft(2, '0');
    return '$hч $mм';
  }

  /// Получение упорядоченного списка всех категорий (базовые + добавленные родителем)
  static List getOrderedCategories(Map<dynamic, dynamic> childData) {
    final rawCats = childData['appCategories'] is Map
        ? Map<dynamic, dynamic>.from(childData['appCategories'] as Map)
        : <dynamic, dynamic>{};

    final List result = [];
    final addedIds = <String>{};

    // 1. Сначала идут 4 базовые категории в фиксированном порядке
    for (final id in defaultCategoryIds) {
      final catMap = rawCats[id] is Map
          ? Map<dynamic, dynamic>.from(rawCats[id] as Map)
          : <dynamic, dynamic>{};
      final title = catMap['title']?.toString().trim().isNotEmpty == true
          ? catMap['title'].toString().trim()
          : (defaultCategoryTitles[id] ?? id);
      result.add({
        'id': id,
        'title': title,
        'isDefault': true,
        'data': catMap,
      });
      addedIds.add(id);
    }

    // 2. Затем все пользовательские категории, добавленные родителем
    final customEntries = [];
    rawCats.forEach((key, val) {
      final id = key.toString();
      if (addedIds.contains(id) || id.startsWith('_') || val is! Map) return;
      final catMap = Map<dynamic, dynamic>.from(val);
      final title = catMap['title']?.toString().trim().isNotEmpty == true
          ? catMap['title'].toString().trim()
          : 'Категория';
      customEntries.add({
        'id': id,
        'title': title,
        'isDefault': false,
        'createdAt': int.tryParse(catMap['createdAt']?.toString() ?? '0') ?? 0,
        'data': catMap,
      });
    });

    customEntries.sort(
      (a, b) => (a['createdAt'] as int).compareTo(b['createdAt'] as int),
    );
    result.addAll(customEntries);

    return result;
  }

  /// Автоопределение категории при первой синхронизации нового пакета
  static String guessCategory(String packageName, String appName) {
    final p = packageName.toLowerCase();
    final n = appName.toLowerCase();

    if (p.contains('game') ||
        p.contains('roblox') ||
        p.contains('minecraft') ||
        p.contains('supercell') ||
        p.contains('brawl') ||
        p.contains('pubg') ||
        p.contains('standoff') ||
        p.contains('unity') ||
        n.contains('игр')) {
      return 'games';
    }

    if (p.contains('telegram') ||
        p.contains('whatsapp') ||
        p.contains('viber') ||
        p.contains('vkontakte') ||
        p.contains('vk.') ||
        p.contains('instagram') ||
        p.contains('tiktok') ||
        p.contains('musically') ||
        p.contains('youtube') ||
        p.contains('discord') ||
        p.contains('likee') ||
        p.contains('snapchat')) {
      return 'social';
    }

    if (p.contains('classroom') ||
        p.contains('duolingo') ||
        p.contains('dnevnik') ||
        p.contains('school') ||
        p.contains('ucheb') ||
        p.contains('math') ||
        p.contains('read') ||
        p.contains('book') ||
        p.contains('yandex.disc') ||
        n.contains('дневник') ||
        n.contains('учеб') ||
        n.contains('школ')) {
      return 'study';
    }

    return 'other';
  }

  /// Подсчёт экранного времени по всем активным категориям и общего времени
  static Map<String, int> calculateCategoryMinutes(Map<dynamic, dynamic> childData) {
    final categories = getOrderedCategories(childData);
    final validIds = categories.map((c) => c['id'].toString()).toSet();

    final result = <String, int>{'total': 0};
    for (final id in validIds) {
      result[id] = 0;
    }

    if (childData['installedApps'] is! Map) return result;

    final appsMap = Map<dynamic, dynamic>.from(childData['installedApps'] as Map);
    appsMap.forEach((key, val) {
      if (key.toString().startsWith('_') || val is! Map) return;
      final mins = int.tryParse(val['timeSpentMinutes']?.toString() ?? '0') ?? 0;
      final rawCat = val['category']?.toString() ?? 'other';
      final cat = validIds.contains(rawCat) ? rawCat : 'other';

      result[cat] = (result[cat] ?? 0) + mins;
      result['total'] = (result['total'] ?? 0) + mins;
    });

    return result;
  }

  /// Извлечение списка правил категории (поддерживает и новый массив rules, и старый плоский формат)
  static List extractCategoryRules(Map<dynamic, dynamic> catData) {
    final List rules = [];
    final rawRules = catData['rules'];

    if (rawRules is List) {
      for (final item in rawRules) {
        if (item is Map) {
          rules.add(Map<dynamic, dynamic>.from(item));
        }
      }
    } else if (rawRules is Map) {
      rawRules.forEach((k, v) {
        if (v is Map) {
          rules.add(Map<dynamic, dynamic>.from(v));
        }
      });
    } else if (catData.containsKey('allowedDays') ||
        catData.containsKey('useTimeWindow') ||
        catData.containsKey('dailyLimitMinutes')) {
      // Обратная совместимость со старой структурой одного правила
      rules.add(Map<dynamic, dynamic>.from(catData));
    }

    return rules;
  }

  /// Проверка одного конкретного правила в текущий момент времени
  static bool isSingleRuleMatchedNow({
    required Map<dynamic, dynamic> ruleMap,
    required int spentMinutesToday,
    required DateTime now,
  }) {
    if (ruleMap['isBlocked'] == true) return false;

    // 1. Проверка дней недели (1 = Пн .. 7 = Вс)
    final rawDays = ruleMap['allowedDays'];
    if (rawDays is List && rawDays.isNotEmpty) {
      final allowedDays = rawDays
          .map((e) => int.tryParse(e.toString()) ?? 0)
          .where((d) => d >= 1 && d <= 7)
          .toList();
      if (allowedDays.isNotEmpty && !allowedDays.contains(now.weekday)) {
        return false;
      }
    }

    // 2. Проверка временного окна (например, с 19:00 до 20:00)
    if (ruleMap['useTimeWindow'] == true) {
      final startMins =
          int.tryParse(ruleMap['startMinutes']?.toString() ?? '0') ?? 0;
      final endMins =
          int.tryParse(ruleMap['endMinutes']?.toString() ?? '1439') ?? 1439;
      final currentMins = now.hour * 60 + now.minute;

      if (startMins <= endMins) {
        if (currentMins < startMins || currentMins >= endMins) return false;
      } else {
        if (currentMins < startMins && currentMins >= endMins) return false;
      }
    }

    // 3. Проверка дневного лимита в минутах
    final dailyLimit =
        int.tryParse(ruleMap['dailyLimitMinutes']?.toString() ?? '0') ?? 0;
    if (dailyLimit > 0 && spentMinutesToday >= dailyLimit) {
      return false;
    }

    return true;
  }

  /// Проверка доступности категории с учётом нескольких правил (логика ИЛИ между правилами)
  static bool isCategoryAllowedNow({
    required Map<dynamic, dynamic> catData,
    required int spentMinutesToday,
    required DateTime now,
  }) {
    if (catData['isBlocked'] == true) return false;

    final rules = extractCategoryRules(catData);
    // Если правил для категории не задано — ограничений нет
    if (rules.isEmpty) return true;

    // Доступ разрешён, если выполняется хотя бы одно из заданных правил
    for (final rule in rules) {
      if (isSingleRuleMatchedNow(
        ruleMap: rule,
        spentMinutesToday: spentMinutesToday,
        now: now,
      )) {
        return true;
      }
    }

    return false;
  }

  /// Вычисление итогового списка заблокированных пакетов
  static List<String> evaluateBlockedPackages(
    Map<dynamic, dynamic> childData, {
    DateTime? nowOverride,
  }) {
    final now = nowOverride ?? DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final blocked = <String>{...restrictedSystemPackages};

    if (childData['installedApps'] is! Map) return blocked.toList();

    final appsMap = Map<dynamic, dynamic>.from(childData['installedApps'] as Map);
    final categories = getOrderedCategories(childData);
    final validCatIds = categories.map((c) => c['id'].toString()).toSet();
    final catMinutes = calculateCategoryMinutes(childData);

    final categoryAllowedMap = <String, bool>{};
    for (final cat in categories) {
      final catId = cat['id'].toString();
      final catData = cat['data'] is Map
          ? Map<dynamic, dynamic>.from(cat['data'] as Map)
          : <dynamic, dynamic>{};
      categoryAllowedMap[catId] = isCategoryAllowedNow(
        catData: catData,
        spentMinutesToday: catMinutes[catId] ?? 0,
        now: now,
      );
    }

    appsMap.forEach((key, val) {
      if (key.toString().startsWith('_') || val is! Map) return;
      final pkg = val['packageName']?.toString() ?? '';
      if (pkg.isEmpty) return;

      // 1. Временное разрешение от родителя перекрывает любые запреты
      final tempAllowUntil =
          int.tryParse(val['tempAllowUntil']?.toString() ?? '0') ?? 0;
      if (tempAllowUntil > nowMs) {
        blocked.remove(pkg);
        return;
      }

      final ruleMode = val['ruleMode']?.toString() ?? 'inherit';
      final rawCat = val['category']?.toString() ?? 'other';
      final cat = validCatIds.contains(rawCat) ? rawCat : 'other';
      final appSpent =
          int.tryParse(val['timeSpentMinutes']?.toString() ?? '0') ?? 0;

      bool isAppAllowed;
      if (ruleMode == 'always_allowed') {
        isAppAllowed = true;
      } else if (ruleMode == 'custom') {
        isAppAllowed = isSingleRuleMatchedNow(
          ruleMap: val,
          spentMinutesToday: appSpent,
          now: now,
        );
      } else {
        if (val['isBlocked'] == true) {
          isAppAllowed = false;
        } else {
          isAppAllowed = categoryAllowedMap[cat] ?? true;
        }
      }

      if (!isAppAllowed) {
        blocked.add(pkg);
      }
    });

    return blocked.toList();
  }

  /// Синхронизация списка приложений, статистики использования и применение правил
  static Future<void> syncInstalledApps() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final childId = prefs.getString('saved_child_id');
      if (childId == null || childId.isEmpty) return;

      final childRef = FirebaseDatabase.instance.ref('children/$childId');
      final childSnap = await childRef.get();

      Map<dynamic, dynamic> existingChildData = {};
      Map<dynamic, dynamic> oldAppsMap = {};
      if (childSnap.exists && childSnap.value != null) {
        existingChildData =
            Map<dynamic, dynamic>.from(childSnap.value as Map);
        if (existingChildData['installedApps'] is Map) {
          oldAppsMap = Map<dynamic, dynamic>.from(
            existingChildData['installedApps'] as Map,
          );
        }
      }

      final validCatIds = getOrderedCategories(existingChildData)
          .map((c) => c['id'].toString())
          .toSet();

      final List<Application> apps = await DeviceApps.getInstalledApplications(
        includeAppIcons: false,
        includeSystemApps: true,
        onlyAppsWithLaunchIntent: true,
      );

      Map<String, int> usageMap = {};
      try {
        final Map<dynamic, dynamic>? rawUsage =
            await platform.invokeMethod('getUsageStats');
        if (rawUsage != null) {
          usageMap = rawUsage.map(
            (key, value) => MapEntry(
              key.toString(),
              int.tryParse(value.toString()) ?? 0,
            ),
          );
        }
      } catch (e) {
        debugPrint('[AppControl] Ошибка получения UsageStats из Kotlin: $e');
      }

      final Map<String, dynamic> appsData = {};

      for (final app in apps) {
        if (app.packageName == 'com.familypulse.app') continue;

        final int timeSpentMs = usageMap[app.packageName] ?? 0;
        final int spentMinutes = (timeSpentMs / (1000 * 60)).round();
        final String safeKey = app.packageName.replaceAll('.', '_');

        final Map<dynamic, dynamic> prev = oldAppsMap[safeKey] is Map
            ? Map<dynamic, dynamic>.from(oldAppsMap[safeKey] as Map)
            : {};

        String category = prev['category']?.toString() ??
            guessCategory(app.packageName, app.appName);
        if (!validCatIds.contains(category)) {
          category = 'other';
        }

        final bool defaultSystemBlocked =
            restrictedSystemPackages.contains(app.packageName);
        final String ruleMode = prev['ruleMode']?.toString() ??
            (defaultSystemBlocked ? 'custom' : 'inherit');
        final bool isBlocked = prev.containsKey('isBlocked')
            ? prev['isBlocked'] == true
            : defaultSystemBlocked;

        final Map<String, dynamic> entry = {
          'appName': app.appName,
          'packageName': app.packageName,
          'timeSpentMinutes': spentMinutes,
          'category': category,
          'ruleMode': ruleMode,
          'isBlocked': isBlocked,
        };

        if (prev['allowedDays'] != null) {
          entry['allowedDays'] = prev['allowedDays'];
        }
        if (prev['useTimeWindow'] != null) {
          entry['useTimeWindow'] = prev['useTimeWindow'];
        }
        if (prev['startMinutes'] != null) {
          entry['startMinutes'] = prev['startMinutes'];
        }
        if (prev['endMinutes'] != null) {
          entry['endMinutes'] = prev['endMinutes'];
        }
        if (prev['dailyLimitMinutes'] != null) {
          entry['dailyLimitMinutes'] = prev['dailyLimitMinutes'];
        }
        if (prev['tempAllowUntil'] != null) {
          entry['tempAllowUntil'] = prev['tempAllowUntil'];
        }

        appsData[safeKey] = entry;
      }

      appsData['_lastSyncTime'] = ServerValue.timestamp;

      await childRef.child('installedApps').set(appsData);

      existingChildData['installedApps'] = appsData;
      final blockedList = evaluateBlockedPackages(existingChildData);
      await updateNativeBlockedPackages(blockedList);
    } catch (e) {
      debugPrint('[AppControl] Ошибка синхронизации приложений: $e');
    }
  }

  /// Передача списка заблокированных пакетов в нативный слой Android
  static Future<void> updateNativeBlockedPackages(List<String> packages) async {
    try {
      final fullList = {...restrictedSystemPackages, ...packages}.toList();
      await adminChannel.invokeMethod('setBlockedPackages', {
        'packages': fullList,
      });
    } catch (e) {
      debugPrint('[AppControl] Ошибка передачи blockedPackages в Kotlin: $e');
    }
  }
}