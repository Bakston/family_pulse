import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/chat/family_chat_screen.dart';
import '../../main.dart' show navigatorKey;
import 'family_chat_service.dart';

class ChatNotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static StreamSubscription<DatabaseEvent>? _chatSubscription;
  static bool _isInitialized = false;
  static String? _activeChatId;
  static String? _activeMemberId;

  /// Флаг: открыт ли сейчас экран FamilyChatScreen (чтобы не дублировать звук)
  static bool isChatScreenOpen = false;

  // Новый ID канала сбрасывает закэшированные Android «тихие» настройки
  static const String _channelId = 'family_chat_channel_v2';
  static const String _channelName = 'Семейный чат и события';

  /// Инициализация плагина, канала уведомлений и обработчика нажатий
  static Future<void> init() async {
    if (_isInitialized) return;

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final chatId = response.payload ?? '';
        openFamilyChatFromNotification(chatId: chatId);
      },
    );

    final androidPlugin =
        _notifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'Уведомления о сообщениях и действиях в семейном чате',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        showBadge: true,
      ),
    );

    _isInitialized = true;
  }

  /// Проверяет, не было ли приложение запущено нажатием на уведомление в шторке
  static Future<void> handleInitialLaunchIfNeeded() async {
    await init();
    final launchDetails =
        await _notifications.getNotificationAppLaunchDetails();
    if (launchDetails != null &&
        launchDetails.didNotificationLaunchApp &&
        launchDetails.notificationResponse != null) {
      final chatId = launchDetails.notificationResponse!.payload ?? '';
      Future.delayed(const Duration(milliseconds: 500), () {
        openFamilyChatFromNotification(chatId: chatId);
      });
    }
  }

  /// Переход на экран FamilyChatScreen при нажатии на уведомление
  static Future<void> openFamilyChatFromNotification({String? chatId}) async {
    if (isChatScreenOpen) return;

    final navState = navigatorKey.currentState;
    if (navState == null) return;

    final prefs = await SharedPreferences.getInstance();
    final userType = prefs.getString('user_type') ?? '';

    if (userType == 'parent') {
      final uid = prefs.getString('user_uid') ?? '';
      if (uid.isEmpty) return;

      final localRole = prefs.getString('user_role') ?? 'Родитель';
      final localName = prefs.getString('user_name') ?? 'Вы';

      String resolvedChatId = (chatId != null && chatId.isNotEmpty)
          ? chatId
          : await FamilyChatService.resolveChatIdForChild(uid);

      if (resolvedChatId.isEmpty) return;

      final memberIds = await FamilyChatService.resolveAllFamilyMemberIds(
        primaryParentUid: uid,
      );

      navState.push(
        MaterialPageRoute(
          builder: (_) => FamilyChatScreen(
            chatId: resolvedChatId,
            currentUserId: uid,
            currentUserName: '$localRole $localName',
            currentUserRole: 'parent',
            allFamilyMemberIds: memberIds,
          ),
        ),
      );
    } else if (userType == 'child') {
      final childId = prefs.getString('saved_child_id') ?? '';
      if (childId.isEmpty) return;

      final childName = prefs.getString('saved_child_name') ?? 'Ребёнок';
      final childGender = prefs.getString('saved_child_gender') ?? 'boy';

      String parentUid = '';
      try {
        final snap = await FirebaseDatabase.instance
            .ref('children/$childId/parentUid')
            .get();
        parentUid = snap.value?.toString() ?? '';
      } catch (_) {}

      String resolvedChatId = (chatId != null && chatId.isNotEmpty)
          ? chatId
          : await FamilyChatService.resolveChatIdForChild(parentUid);

      if (resolvedChatId.isEmpty) return;

      final memberIds = parentUid.isNotEmpty
          ? await FamilyChatService.resolveAllFamilyMemberIds(
              primaryParentUid: parentUid,
            )
          : <String>[childId];

      navState.push(
        MaterialPageRoute(
          builder: (_) => FamilyChatScreen(
            chatId: resolvedChatId,
            currentUserId: childId,
            currentUserName: childName,
            currentUserRole: 'child',
            childGender: childGender,
            allFamilyMemberIds: memberIds,
          ),
        ),
      );
    }
  }

  /// Запрос системного разрешения на уведомления (Android 13+)
  static Future<bool> requestPermission() async {
    final status = await Permission.notification.status;
    if (status.isGranted) return true;
    final result = await Permission.notification.request();
    return result.isGranted;
  }

  /// Проверка, разрешены ли уведомления в системе
  static Future<bool> isPermissionGranted() async {
    return await Permission.notification.isGranted;
  }

  /// Запуск прослушивания семейного чата для текущего участника
  static Future<void> startListening({
    required String chatId,
    required String currentMemberId,
  }) async {
    if (chatId.isEmpty || currentMemberId.isEmpty) return;
    if (_activeChatId == chatId &&
        _activeMemberId == currentMemberId &&
        _chatSubscription != null) {
      return;
    }

    await init();
    await _chatSubscription?.cancel();
    _activeChatId = chatId;
    _activeMemberId = currentMemberId;

    final prefs = await SharedPreferences.getInstance();
    final prefKey = 'last_notified_chat_ts_${chatId}_$currentMemberId';

    _chatSubscription = FirebaseDatabase.instance
        .ref('familyChats/$chatId')
        .onValue
        .listen((DatabaseEvent event) async {
      if (event.snapshot.value is! Map) return;
      final chatData = Map<dynamic, dynamic>.from(event.snapshot.value as Map);

      final int lastMessageAt =
          int.tryParse(chatData['lastMessageAt']?.toString() ?? '0') ?? 0;
      final String lastMessage = chatData['lastMessage']?.toString() ?? '';
      final String lastSenderName =
          chatData['lastSenderName']?.toString() ?? 'Семейный чат';
      final String lastSenderId =
          chatData['lastSenderId']?.toString() ?? '';

      if (lastMessageAt <= 0 || lastMessage.isEmpty) return;

      final int savedLastTs = prefs.getInt(prefKey) ?? 0;
      final int nowMs = DateTime.now().millisecondsSinceEpoch;

      // При самом первом запуске не спамим старыми сообщениями старше 2 минут,
      // но свежие (пришедшие только что) — обязательно показываем
      if (savedLastTs == 0) {
        await prefs.setInt(prefKey, lastMessageAt);
        if ((nowMs - lastMessageAt) > 120 * 1000) {
          return;
        }
      } else {
        if (lastMessageAt <= savedLastTs) return;
        await prefs.setInt(prefKey, lastMessageAt);
      }

      // Не показываем уведомление, если сообщение отправили вы сами или чат сейчас открыт
      if (lastSenderId == currentMemberId || isChatScreenOpen) return;

      await _showSystemNotification(
        chatId: chatId,
        title: lastSenderName == 'Система'
            ? 'FamilyPulse • Событие'
            : 'Семейный чат • $lastSenderName',
        body: lastMessage,
      );
    }, onError: (e) {
      debugPrint('[ChatNotificationService] Ошибка потока чата: $e');
    });
  }

  static Future<void> _showSystemNotification({
    required String chatId,
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Уведомления о сообщениях и действиях в семейном чате',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      icon: '@mipmap/ic_launcher',
    );

    const details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(1000000),
      title,
      body,
      details,
      payload: chatId,
    );
  }

  /// Остановка слушателя (при выходе из аккаунта / отвязке)
  static Future<void> stopListening() async {
    await _chatSubscription?.cancel();
    _chatSubscription = null;
    _activeChatId = null;
    _activeMemberId = null;
  }
}