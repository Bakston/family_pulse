import 'package:flutter/foundation.dart';
import 'package:firebase_database/firebase_database.dart';
import 'family_chat_service.dart';

class DailyTasksService {
  static String buildDateKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String _formatShortRuDate(String dateKey) {
    final parts = dateKey.split('-');
    if (parts.length != 3) return dateKey;
    return '${parts[2]}.${parts[1]}';
  }

  /// Проверяет ежедневные задания ребёнка:
  /// если день сменился, а задание не подтверждено родителем (`status != 'done'`),
  /// списывает штраф из баланса баллов, пишет в историю и обновляет задание на новый день.
  static Future<void> processDailyTasks(String childId) async {
    if (childId.isEmpty) return;

    try {
      final db = FirebaseDatabase.instance;
      final childRef = db.ref('children/$childId');
      final childSnap = await childRef.get();
      if (!childSnap.exists || childSnap.value is! Map) return;

      final childData = Map<dynamic, dynamic>.from(childSnap.value as Map);
      if (childData['tasks'] is! Map) return;

      final String todayKey = buildDateKey(DateTime.now());
      final String childName = childData['name']?.toString() ?? 'Ребёнок';
      final String parentUid = childData['parentUid']?.toString() ?? '';

      final rawTasks = Map<dynamic, dynamic>.from(childData['tasks'] as Map);
      final List<String> chatEvents = [];
      int totalPenaltyToDeduct = 0;

      for (final entry in rawTasks.entries) {
        final taskId = entry.key.toString();
        if (entry.value is! Map) continue;

        final task = Map<dynamic, dynamic>.from(entry.value as Map);
        final bool isDaily = task['isDaily'] == true;
        if (!isDaily) continue;

        final String activeDate = task['activeDate']?.toString() ?? '';
        if (activeDate.isEmpty) {
          await childRef.child('tasks/$taskId/activeDate').set(todayKey);
          continue;
        }

        // Если активная дата меньше сегодняшней — сутки закончились
        if (activeDate.compareTo(todayKey) < 0) {
          final taskRef = childRef.child('tasks/$taskId');
          bool wonTransaction = false;
          String title = task['title']?.toString() ?? 'Задание';
          String prevStatus = task['status']?.toString() ?? 'available';
          int penalty =
              int.tryParse(task['penaltyPoints']?.toString() ?? '0') ?? 0;

          final txResult = await taskRef.runTransaction((Object? currentData) {
            if (currentData is! Map) return Transaction.abort();
            final map = Map<dynamic, dynamic>.from(currentData);
            final currentActiveDate = map['activeDate']?.toString() ?? '';

            // Другое устройство уже закрыло этот день
            if (currentActiveDate.compareTo(todayKey) >= 0) {
              return Transaction.abort();
            }

            title = map['title']?.toString() ?? title;
            prevStatus = map['status']?.toString() ?? 'available';
            penalty =
                int.tryParse(map['penaltyPoints']?.toString() ?? '0') ?? 0;

            map['activeDate'] = todayKey;
            map['status'] = 'available';
            map['updatedAt'] = ServerValue.timestamp;
            return Transaction.success(map);
          });

          wonTransaction = txResult.committed;

          if (wonTransaction && prevStatus != 'done' && penalty > 0) {
            totalPenaltyToDeduct += penalty;

            final nowMillis = DateTime.now().millisecondsSinceEpoch;
            await childRef.child('taskHistory').push().set({
              'title': '$title (Ежедневное)',
              'points': -penalty,
              'status': 'penalty',
              'finishedAt': nowMillis,
            });

            final shortDate = _formatShortRuDate(activeDate);
            chatEvents.add(
              '⚠️ Штраф за $shortDate: $childName не выполнил(а) ежедневное задание «$title» (-$penalty Б)',
            );
          }
        }
      }

      if (totalPenaltyToDeduct > 0) {
        // Списываем штраф из баланса (допускается уход в минус)
        await childRef.child('goal/current').runTransaction((Object? val) {
          final currentBalance = int.tryParse(val?.toString() ?? '0') ?? 0;
          return Transaction.success(currentBalance - totalPenaltyToDeduct);
        });
      }

      if (chatEvents.isNotEmpty && parentUid.isNotEmpty) {
        final chatId = await FamilyChatService.resolveChatIdForChild(parentUid);
        if (chatId.isNotEmpty) {
          final memberIds = await FamilyChatService.resolveAllFamilyMemberIds(
            primaryParentUid: parentUid,
          );
          for (final text in chatEvents) {
            await FamilyChatService.sendSystemEvent(
              chatId: chatId,
              text: text,
              notifyMemberIds: memberIds,
              action: {
                'kind': 'open_tasks',
                'childId': childId,
              },
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[DailyTasksService] Ошибка проверки ежедневных заданий: $e');
    }
  }
}