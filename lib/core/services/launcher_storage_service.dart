import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../../child/screens/launcher_layout.dart';

class LauncherStorageService {
  static const String _storageKey = 'child_launcher_layout_v2';
  static const String _legacyStorageKey = 'child_launcher_layout_v1';

  /// Загружает сохранённую раскладку. Если новая версия ещё не сохранялась,
  /// переносит ярлыки сетки из v1 и ставит обновлённый 5-слотовый док.
  static Future<LauncherLayoutState> loadLayout() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return LauncherLayoutState.fromJson(
            Map<String, dynamic>.from(decoded),
          );
        }
      } catch (_) {}
    }

    final legacyRaw = prefs.getString(_legacyStorageKey);
    if (legacyRaw != null && legacyRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(legacyRaw);
        if (decoded is Map) {
          final legacyState = LauncherLayoutState.fromJson(
            Map<String, dynamic>.from(decoded),
          );
          final migrated = LauncherLayoutState(
            gridSlots: legacyState.normalizedGridSlots,
            dockSlots: LauncherLayoutState.defaultDock,
          );
          await saveLayout(migrated);
          return migrated;
        }
      } catch (_) {}
    }

    return const LauncherLayoutState();
  }

  static Future<void> saveLayout(LauncherLayoutState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(state.toJson()));
  }

  /// Добавляет ярлык приложения в первую свободную ячейку и сразу сохраняет
  static Future<LauncherLayoutState> addAppToGrid(String packageName) async {
    final current = await loadLayout();
    final updated = current.addAppToGrid(packageName);
    if (updated != current) {
      await saveLayout(updated);
    }
    return updated;
  }

  /// Убирает ярлык приложения из сетки и сразу сохраняет
  static Future<LauncherLayoutState> removeAppFromGrid(String packageName) async {
    final current = await loadLayout();
    final updated = current.removeAppFromGrid(packageName);
    if (updated != current) {
      await saveLayout(updated);
    }
    return updated;
  }

  /// Переставляет ярлык в целевую ячейку сетки и сразу сохраняет
  static Future<LauncherLayoutState> moveAppToSlot(
    int fromIndex,
    int toIndex,
  ) async {
    final current = await loadLayout();
    final updated = current.moveAppToSlot(fromIndex, toIndex);
    if (updated != current) {
      await saveLayout(updated);
    }
    return updated;
  }

  /// Обновляет слоты панели быстрого доступа (дока) и сохраняет
  static Future<LauncherLayoutState> updateDockSlots(
    List<LauncherDockSlot> slots,
  ) async {
    final current = await loadLayout();
    final updated = current.copyWith(dockSlots: slots);
    await saveLayout(updated);
    return updated;
  }

  static Future<void> clearLayout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    await prefs.remove(_legacyStorageKey);
  }
}