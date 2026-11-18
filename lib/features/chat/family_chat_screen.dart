import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

import '../../child/screens/child_tasks_screen.dart';
import '../../core/app_theme.dart';
import '../../core/services/chat_notification_service.dart';
import '../../core/services/family_chat_service.dart';
import '../../parent/screens/child_tasks_management_screen.dart';
import '../../parent/screens/child_apps_screen.dart';

class FamilyChatScreen extends StatefulWidget {
  final String chatId;
  final String currentUserId;
  final String currentUserName;
  final String currentUserRole; // 'parent' или 'child'
  final String childGender; // 'boy' или 'girl' (для палитры ребёнка)
  final List<String> allFamilyMemberIds;

  const FamilyChatScreen({
    super.key,
    required this.chatId,
    required this.currentUserId,
    required this.currentUserName,
    required this.currentUserRole,
    this.childGender = 'boy',
    required this.allFamilyMemberIds,
  });

  @override
  State<FamilyChatScreen> createState() => _FamilyChatScreenState();
}

class _FamilyChatScreenState extends State<FamilyChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;
  final Set<String> _processingActionMessageIds = {};

  @override
  void initState() {
    super.initState();
    ChatNotificationService.isChatScreenOpen = true;
    _resetUnread();
  }

  @override
  void dispose() {
    ChatNotificationService.isChatScreenOpen = false;
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _resetUnread() {
    FamilyChatService.markAsRead(
      chatId: widget.chatId,
      memberId: widget.currentUserId,
    );
  }

  String _formatMessageTime(int millis) {
    if (millis <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatDayDivider(int millis) {
    if (millis <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(msgDay).inDays;

    if (diffDays == 0) return 'Сегодня';
    if (diffDays == 1) return 'Вчера';
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d.$m.${dt.year}';
  }

  Future<void> _sendMessage([String? presetText]) async {
    final text = (presetText ?? _messageController.text).trim();
    if (text.isEmpty || _isSending) return;

    if (presetText == null) {
      _messageController.clear();
    }

    setState(() => _isSending = true);
    try {
      await FamilyChatService.sendTextMessage(
        chatId: widget.chatId,
        senderId: widget.currentUserId,
        senderName: widget.currentUserName,
        senderRole: widget.currentUserRole,
        text: text,
        allFamilyMemberIds: widget.allFamilyMemberIds,
      );
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  Future<void> _handleAcceptTaskAction({
    required String messageId,
    required String childId,
    required String taskId,
  }) async {
    if (_processingActionMessageIds.contains(messageId)) return;
    setState(() => _processingActionMessageIds.add(messageId));

    try {
      final ok = await FamilyChatService.acceptTaskFromChat(
        chatId: widget.chatId,
        messageId: messageId,
        childId: childId,
        childName: widget.currentUserName,
        taskId: taskId,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Задание принято! Оно появилось в активных заданиях.'
                : 'Это задание уже неактуально или выполнено.',
          ),
          backgroundColor: ok ? Colors.deepPurple : Colors.orange,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _processingActionMessageIds.remove(messageId));
      }
    }
  }

  Future<void> _handleSystemCardTap(Map<String, dynamic>? action) async {
    if (action == null) return;
    final kind = action['kind']?.toString() ?? '';
    final targetChildId = action['childId']?.toString() ?? '';

    if (kind == 'app_unlock_request' &&
        widget.currentUserRole == 'parent' &&
        targetChildId.isNotEmpty) {
      String childName = 'Ребёнок';
      try {
        final snap = await FirebaseDatabase.instance
            .ref('children/$targetChildId/name')
            .get();
        if (snap.exists && snap.value != null) {
          childName = snap.value.toString();
        }
      } catch (_) {}

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChildAppsScreen(
            childId: targetChildId,
            childName: childName,
            initialPackageName: action['packageName']?.toString(),
          ),
        ),
      );
      return;
    }

    if (kind == 'accept_task' || kind == 'open_tasks') {
      if (widget.currentUserRole == 'child') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChildTasksScreen(
              childId: widget.currentUserId,
              childName: widget.currentUserName,
              gender: widget.childGender,
            ),
          ),
        );
      } else if (targetChildId.isNotEmpty) {
        String childName = 'Ребёнок';
        try {
          final snap = await FirebaseDatabase.instance
              .ref('children/$targetChildId/name')
              .get();
          if (snap.exists && snap.value != null) {
            childName = snap.value.toString();
          }
        } catch (_) {}

        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChildTasksManagementScreen(
              childId: targetChildId,
              childName: childName,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isParent = widget.currentUserRole == 'parent';
    final AppPalette palette = isParent
        ? AppTheme.getPalette('parent')
        : AppTheme.getPalette('child', gender: widget.childGender);

    const List<String> childQuickPhrases = [
      'Я в школе 📚',
      'Я уже дома 🏠',
      'Выхожу домой 🚶',
      'Перезвоните, пожалуйста 📞',
    ];

    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            palette.backgroundAsset,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(color: palette.background),
          ),
        ),
        Positioned.fill(
          child: Container(
            color: isParent
                ? Colors.black.withValues(alpha: 0.42)
                : palette.background.withValues(alpha: 0.55),
          ),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            title: const Row(
              children: [
                Icon(Icons.forum_rounded, color: Colors.white, size: 22),
                SizedBox(width: 10),
                Text(
                  'Семейный чат',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: widget.chatId.isEmpty
                      ? const Center(
                          child: Text(
                            'Чат не инициализирован',
                            style: TextStyle(color: Colors.white70),
                          ),
                        )
                      : StreamBuilder<DatabaseEvent>(
                          stream: FirebaseDatabase.instance
                              .ref('familyChats/${widget.chatId}/messages')
                              .orderByChild('timestamp')
                              .limitToLast(100)
                              .onValue,
                          builder: (context, snapshot) {
                            _resetUnread();

                            final List messages = [];
                            if (snapshot.hasData &&
                                snapshot.data!.snapshot.value != null) {
                              final rawMap = Map<dynamic, dynamic>.from(
                                snapshot.data!.snapshot.value as Map,
                              );
                              rawMap.forEach((key, val) {
                                if (val is Map) {
                                  messages.add({
                                    'id': key.toString(),
                                    'type': val['type']?.toString() ?? 'text',
                                    'senderId':
                                        val['senderId']?.toString() ?? '',
                                    'senderName':
                                        val['senderName']?.toString() ??
                                            'Участник',
                                    'senderRole':
                                        val['senderRole']?.toString() ??
                                            'parent',
                                    'text': val['text']?.toString() ?? '',
                                    'timestamp': int.tryParse(
                                          val['timestamp']?.toString() ?? '0',
                                        ) ??
                                        0,
                                    'action': val['action'] is Map
                                        ? Map<String, dynamic>.from(
                                            val['action'] as Map,
                                          )
                                        : null,
                                  });
                                }
                              });
                              messages.sort(
                                (a, b) => (a['timestamp'] as int)
                                    .compareTo(b['timestamp'] as int),
                              );
                            }

                            if (messages.isEmpty) {
                              return Center(
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 32,
                                  ),
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    color: isParent
                                        ? Colors.white.withValues(alpha: 0.9)
                                        : palette.glassPanel,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    'Здесь будут отображаться сообщения вашей семьи и важные события (задания, геозоны, цели).\n\nНапишите первое сообщение!',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 13.5,
                                      height: 1.4,
                                      color: isParent
                                          ? Colors.black87
                                          : palette.textPrimary,
                                    ),
                                  ),
                                ),
                              );
                            }

                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (_scrollController.hasClients) {
                                _scrollController.jumpTo(
                                  _scrollController.position.maxScrollExtent,
                                );
                              }
                            });

                            return ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                8,
                                14,
                                12,
                              ),
                              itemCount: messages.length,
                              itemBuilder: (context, index) {
                                final msg = messages[index];
                                final int ts = msg['timestamp'] as int;
                                final String dayLabel = _formatDayDivider(ts);
                                final String? prevDayLabel = index > 0
                                    ? _formatDayDivider(
                                        messages[index - 1]['timestamp'] as int,
                                      )
                                    : null;
                                final bool showDateHeader =
                                    dayLabel.isNotEmpty &&
                                        dayLabel != prevDayLabel;

                                final bool isSystem = msg['type'] == 'system';
                                final bool isMine =
                                    msg['senderId'] == widget.currentUserId;

                                return Column(
                                  children: [
                                    if (showDateHeader)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 10,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black
                                                .withValues(alpha: 0.45),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            dayLabel,
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                              color: Colors.white,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (isSystem)
                                      _buildSystemEventBubble(
                                        messageId: msg['id'] as String,
                                        text: msg['text'] as String,
                                        timeStr: _formatMessageTime(ts),
                                        action: msg['action']
                                            as Map<String, dynamic>?,
                                        isParent: isParent,
                                      )
                                    else
                                      _buildMessageBubble(
                                        senderName: msg['senderName'] as String,
                                        text: msg['text'] as String,
                                        timeStr: _formatMessageTime(ts),
                                        isMine: isMine,
                                        isParentScreen: isParent,
                                        palette: palette,
                                      ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                ),

                if (!isParent)
                  SizedBox(
                    height: 38,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      itemCount: childQuickPhrases.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, idx) {
                        final phrase = childQuickPhrases[idx];
                        return ActionChip(
                          backgroundColor: palette.glassPanel,
                          side: BorderSide(
                            color:
                                palette.primaryAccent.withValues(alpha: 0.45),
                          ),
                          label: Text(
                            phrase,
                            style: TextStyle(
                              fontSize: 12,
                              color: palette.textPrimary,
                            ),
                          ),
                          onPressed: () => _sendMessage(phrase),
                        );
                      },
                    ),
                  ),

                Container(
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isParent
                        ? Colors.white.withValues(alpha: 0.95)
                        : palette.glassPanel.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: isParent
                          ? Colors.white
                          : palette.primaryAccent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          minLines: 1,
                          maxLines: 4,
                          textCapitalization: TextCapitalization.sentences,
                          style: TextStyle(
                            color: isParent
                                ? Colors.black87
                                : palette.textPrimary,
                            fontSize: 15,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Написать в семейный чат...',
                            hintStyle: TextStyle(
                              color: isParent
                                  ? Colors.black45
                                  : palette.textSecondary,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 8,
                            ),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: _isSending ? null : () => _sendMessage(),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isParent
                                ? Colors.blue.shade700
                                : palette.primaryAccent,
                          ),
                          child: Icon(
                            Icons.send_rounded,
                            size: 20,
                            color: isParent ? Colors.white : palette.background,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSystemEventBubble({
    required String messageId,
    required String text,
    required String timeStr,
    required Map<String, dynamic>? action,
    required bool isParent,
  }) {
    const Color systemViolet = Color(0xFF8B5CF6);
    final String kind = action?['kind']?.toString() ?? '';
    final String targetChildId = action?['childId']?.toString() ?? '';
    final String taskId = action?['taskId']?.toString() ?? '';
    final bool isCompleted = action?['isCompleted'] == true;
    final String buttonLabel =
        action?['buttonLabel']?.toString() ?? 'Принять задание';

    final bool canChildAcceptTask = !isParent &&
        kind == 'accept_task' &&
        targetChildId == widget.currentUserId &&
        taskId.isNotEmpty;

    final bool canParentOpenAppAccess = isParent &&
        kind == 'app_unlock_request' &&
        targetChildId.isNotEmpty;

    final bool hasInlineButton = canChildAcceptTask || canParentOpenAppAccess;
    final bool isClickable = action != null && kind.isNotEmpty;
    final bool isProcessing = _processingActionMessageIds.contains(messageId);

    return GestureDetector(
      onTap: isClickable ? () => _handleSystemCardTap(action) : null,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 14),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isParent
              ? const Color(0xFFF3E8FF).withValues(alpha: 0.96)
              : systemViolet.withValues(alpha: 0.24),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isParent
                ? const Color(0xFFD8B4FE)
                : systemViolet.withValues(alpha: 0.6),
            width: 1.2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: isParent
                      ? const Color(0xFF7C3AED)
                      : const Color(0xFFC4B5FD),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isParent
                          ? const Color(0xFF4C1D95)
                          : const Color(0xFFF3E8FF),
                    ),
                  ),
                ),
                if (timeStr.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isParent
                          ? const Color(0xFF6D28D9).withValues(alpha: 0.7)
                          : const Color(0xFFDDD6FE).withValues(alpha: 0.75),
                    ),
                  ),
                ],
                if (isClickable && !hasInlineButton) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: isParent
                        ? const Color(0xFF7C3AED)
                        : const Color(0xFFC4B5FD),
                  ),
                ],
              ],
            ),

            if (canChildAcceptTask) ...[
              const SizedBox(height: 8),
              if (isCompleted)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    '✓ Принято в работу',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFA7F3D0),
                    ),
                  ),
                )
              else
                SizedBox(
                  height: 34,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF7C3AED),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: isProcessing
                        ? null
                        : () => _handleAcceptTaskAction(
                              messageId: messageId,
                              childId: targetChildId,
                              taskId: taskId,
                            ),
                    icon: isProcessing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline, size: 16),
                    label: Text(
                      buttonLabel,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],

            if (canParentOpenAppAccess) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 34,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C3AED),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => _handleSystemCardTap(action),
                  icon: const Icon(Icons.tune_rounded, size: 16),
                  label: Text(
                    action?['buttonLabel']?.toString() ?? 'Настройки доступа',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble({
    required String senderName,
    required String text,
    required String timeStr,
    required bool isMine,
    required bool isParentScreen,
    required AppPalette palette,
  }) {
    final Color bubbleColor;
    final Color textColor;
    final Color nameColor;

    if (isParentScreen) {
      bubbleColor = isMine
          ? Colors.blue.shade700
          : Colors.white.withValues(alpha: 0.95);
      textColor = isMine ? Colors.white : Colors.black87;
      nameColor = Colors.blue.shade800;
    } else {
      bubbleColor = isMine
          ? palette.primaryAccent.withValues(alpha: 0.88)
          : palette.glassPanel.withValues(alpha: 0.9);
      textColor = isMine ? palette.background : palette.textPrimary;
      nameColor = palette.primaryAccent;
    }

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.fromLTRB(14, 9, 14, 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.76,
        ),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMine ? 18 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 18),
          ),
          border: isMine
              ? null
              : Border.all(
                  color: isParentScreen
                      ? Colors.black12
                      : palette.primaryAccent.withValues(alpha: 0.3),
                ),
        ),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMine) ...[
              Text(
                senderName,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: nameColor,
                ),
              ),
              const SizedBox(height: 2),
            ],
            Text(
              text,
              style: TextStyle(
                fontSize: 14.5,
                color: textColor,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              timeStr,
              style: TextStyle(
                fontSize: 10.5,
                color: textColor.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}