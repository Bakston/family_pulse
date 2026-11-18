import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/app_theme.dart';
import 'core/services/chat_notification_service.dart';
import 'core/services/family_chat_service.dart';
import 'core/services/github_update_service.dart';
import 'core/services/location_service.dart';
import 'features/auth/initial_session_wrapper.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Firebase.initializeApp();
  await ChatNotificationService.handleInitialLaunchIfNeeded();

  final prefs = await SharedPreferences.getInstance();
  final userType = prefs.getString('user_type') ?? '';

  if (userType == 'child') {
    final childId = prefs.getString('saved_child_id') ?? '';
    if (childId.isNotEmpty) {
      unawaited(LocationService.startChildLocationTracking(childId: childId));
      unawaited(_bootstrapChildChatNotifications(childId));
    }
  } else if (userType == 'parent') {
    final uid = prefs.getString('user_uid') ?? '';
    if (uid.isNotEmpty) {
      unawaited(_bootstrapParentChatNotifications(uid));
    }
  }

  runApp(const FamilyPulseApp());
}

Future<void> _bootstrapChildChatNotifications(String childId) async {
  try {
    final snap = await FirebaseDatabase.instance
        .ref('children/$childId/parentUid')
        .get();
    final parentUid = snap.value?.toString() ?? '';
    if (parentUid.isEmpty) return;

    final chatId = await FamilyChatService.resolveChatIdForChild(parentUid);
    if (chatId.isNotEmpty) {
      await ChatNotificationService.startListening(
        chatId: chatId,
        currentMemberId: childId,
      );
    }
  } catch (_) {}
}

Future<void> _bootstrapParentChatNotifications(String uid) async {
  try {
    final chatId = await FamilyChatService.resolveChatIdForChild(uid);
    if (chatId.isNotEmpty) {
      await ChatNotificationService.startListening(
        chatId: chatId,
        currentMemberId: uid,
      );
    }
  } catch (_) {}
}

class FamilyPulseApp extends StatefulWidget {
  const FamilyPulseApp({super.key});

  @override
  State<FamilyPulseApp> createState() => _FamilyPulseAppState();
}

class _FamilyPulseAppState extends State<FamilyPulseApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = navigatorKey.currentContext;
      if (context != null) {
        GithubUpdateService.checkForUpdates(context, silent: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FamilyPulse',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const InitialSessionWrapper(),
    );
  }
}