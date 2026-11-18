import 'package:firebase_database/firebase_database.dart';

class FamilyChatService {
  static DatabaseReference get _db => FirebaseDatabase.instance.ref();

  /// Вычисляет единый ID комнаты семейного чата для всех членов одной семьи
  static String resolveFamilyChatId({
    required String primaryParentUid,
    String? linkedParentUid,
  }) {
    final p1 = primaryParentUid.trim();
    final p2 = (linkedParentUid ?? '').trim();
    if (p1.isEmpty) return p2;
    if (p2.isEmpty) return p1;
    return p1.compareTo(p2) <= 0 ? p1 : p2;
  }

  /// Определяет ID комнаты для ребёнка по его parentUid (с проверкой linkedParent)
  static Future<String> resolveChatIdForChild(String parentUid) async {
    if (parentUid.isEmpty) return '';
    try {
      final snap = await _db.child('users/$parentUid/linkedParent').get();
      final linkedUid = snap.exists && snap.value != null
          ? snap.value.toString()
          : null;
      return resolveFamilyChatId(
        primaryParentUid: parentUid,
        linkedParentUid: linkedUid,
      );
    } catch (_) {
      return parentUid;
    }
  }

  /// Собирает список всех ID участников семьи (родители + дети) для уведомлений
  static Future<List<String>> resolveAllFamilyMemberIds({
    required String primaryParentUid,
  }) async {
    if (primaryParentUid.isEmpty) return [];
    final Set<String> memberIds = {primaryParentUid};

    try {
      final linkedSnap =
          await _db.child('users/$primaryParentUid/linkedParent').get();
      final String? linkedUid =
          linkedSnap.exists && linkedSnap.value != null
              ? linkedSnap.value.toString()
              : null;
      if (linkedUid != null && linkedUid.isNotEmpty) {
        memberIds.add(linkedUid);
      }

      final childrenSnap = await _db.child('children').get();
      if (childrenSnap.exists && childrenSnap.value is Map) {
        final childrenMap =
            Map<dynamic, dynamic>.from(childrenSnap.value as Map);
        childrenMap.forEach((key, val) {
          if (val is Map) {
            final cParent = val['parentUid']?.toString() ?? '';
            if (cParent == primaryParentUid ||
                (linkedUid != null && cParent == linkedUid)) {
              memberIds.add(key.toString());
            }
          }
        });
      }
    } catch (_) {}

    return memberIds.toList();
  }

  /// Отправка обычного текстового сообщения в семейный чат
  static Future<void> sendTextMessage({
    required String chatId,
    required String senderId,
    required String senderName,
    required String senderRole, // 'parent' или 'child'
    required String text,
    required List<String> allFamilyMemberIds,
  }) async {
    final trimmed = text.trim();
    if (chatId.isEmpty || trimmed.isEmpty) return;

    final chatRef = _db.child('familyChats/$chatId');
    await chatRef.child('messages').push().set({
      'type': 'text',
      'senderId': senderId,
      'senderName': senderName,
      'senderRole': senderRole,
      'text': trimmed,
      'timestamp': ServerValue.timestamp,
    });

    await chatRef.update({
      'lastMessage': trimmed,
      'lastSenderName': senderName,
      'lastSenderId': senderId, // <--- Фиксируем ID отправителя для пуш-уведомлений
      'lastType': 'text',
      'lastMessageAt': ServerValue.timestamp,
    });

    // Увеличиваем счётчик непрочитанных для всех остальных членов семьи
    for (final memberId in allFamilyMemberIds) {
      if (memberId.isNotEmpty && memberId != senderId) {
        await chatRef
            .child('unreadBy/$memberId')
            .set(ServerValue.increment(1));
      }
    }
  }

  /// Отправка системного события в семейный чат (задания, геозоны, цели и т.д.)
  static Future<void> sendSystemEvent({
    required String chatId,
    required String text,
    List<String> notifyMemberIds = const [],
    String? excludeMemberId,
    Map<String, dynamic>? action,
  }) async {
    final trimmed = text.trim();
    if (chatId.isEmpty || trimmed.isEmpty) return;

    final chatRef = _db.child('familyChats/$chatId');
    final payload = <String, dynamic>{
      'type': 'system',
      'senderId': 'system',
      'senderName': 'Система',
      'senderRole': 'system',
      'text': trimmed,
      'timestamp': ServerValue.timestamp,
    };
    if (action != null && action.isNotEmpty) {
      payload['action'] = action;
    }

    await chatRef.child('messages').push().set(payload);

    await chatRef.update({
      'lastMessage': trimmed,
      'lastSenderName': 'Система',
      'lastSenderId': 'system', // <--- Фиксируем системного отправителя
      'lastType': 'system',
      'lastMessageAt': ServerValue.timestamp,
    });

    for (final memberId in notifyMemberIds) {
      if (memberId.isNotEmpty && memberId != excludeMemberId) {
        await chatRef
            .child('unreadBy/$memberId')
            .set(ServerValue.increment(1));
      }
    }
  }

  /// Принятие задания ребёнком прямо из карточки системного сообщения в чате
  static Future<bool> acceptTaskFromChat({
    required String chatId,
    required String messageId,
    required String childId,
    required String childName,
    required String taskId,
  }) async {
    if (chatId.isEmpty ||
        messageId.isEmpty ||
        childId.isEmpty ||
        taskId.isEmpty) {
      return false;
    }

    final taskRef = _db.child('children/$childId/tasks/$taskId');
    final taskSnap = await taskRef.get();
    if (!taskSnap.exists || taskSnap.value is! Map) {
      await _db
          .child('familyChats/$chatId/messages/$messageId/action')
          .update({'isCompleted': true});
      return false;
    }

    final taskData = Map<dynamic, dynamic>.from(taskSnap.value as Map);
    final taskTitle = taskData['title']?.toString() ?? 'Задание';
    final currentStatus = taskData['status']?.toString() ?? 'available';

    if (currentStatus == 'available') {
      await taskRef.update({
        'status': 'in_progress',
        'updatedAt': ServerValue.timestamp,
      });
    }

    await _db
        .child('familyChats/$chatId/messages/$messageId/action')
        .update({'isCompleted': true});

    final parentUidSnap =
        await _db.child('children/$childId/parentUid').get();
    final parentUid = parentUidSnap.value?.toString() ?? '';
    final memberIds = parentUid.isNotEmpty
        ? await resolveAllFamilyMemberIds(primaryParentUid: parentUid)
        : <String>[];

    await sendSystemEvent(
      chatId: chatId,
      text: '🚀 $childName принял(а) задание «$taskTitle» в работу',
      notifyMemberIds: memberIds,
      excludeMemberId: childId,
      action: {
        'kind': 'open_tasks',
        'childId': childId,
      },
    );

    return true;
  }

  /// Сброс счётчика непрочитанных сообщений при входе в чат
  static Future<void> markAsRead({
    required String chatId,
    required String memberId,
  }) async {
    if (chatId.isEmpty || memberId.isEmpty) return;
    await _db.child('familyChats/$chatId/unreadBy/$memberId').set(0);
  }
}