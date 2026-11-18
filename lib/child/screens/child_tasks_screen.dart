import 'package:material_ui/material_ui.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../core/app_theme.dart';
import '../../core/services/daily_tasks_service.dart';
import '../../core/services/family_chat_service.dart';

class ChildTasksScreen extends StatefulWidget {
  final String childId;
  final String childName;
  final String gender;

  const ChildTasksScreen({
    super.key,
    required this.childId,
    required this.childName,
    required this.gender,
  });

  @override
  State<ChildTasksScreen> createState() => _ChildTasksScreenState();
}

class _ChildTasksScreenState extends State<ChildTasksScreen> {
  DatabaseReference get _childRef =>
      FirebaseDatabase.instance.ref('children/${widget.childId}');

  @override
  void initState() {
    super.initState();
    DailyTasksService.processDailyTasks(widget.childId);
  }

  String _formatDateTime(int millis) {
    if (millis <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d.$m.${dt.year} в $h:$min';
  }

  /// Вспомогательный метод отправки системного события от лица ребёнка в семейный чат
  Future<void> _publishChildSystemEvent(
    String text, {
    Map<String, dynamic>? action,
  }) async {
    if (widget.childId.isEmpty) return;
    try {
      final parentSnap = await _childRef.child('parentUid').get();
      final parentUid = parentSnap.value?.toString() ?? '';
      if (parentUid.isEmpty) return;

      final chatId = await FamilyChatService.resolveChatIdForChild(parentUid);
      if (chatId.isEmpty) return;

      final memberIds = await FamilyChatService.resolveAllFamilyMemberIds(
        primaryParentUid: parentUid,
      );

      await FamilyChatService.sendSystemEvent(
        chatId: chatId,
        text: text,
        notifyMemberIds: memberIds,
        excludeMemberId: widget.childId,
        action: action ??
            {
              'kind': 'open_tasks',
              'childId': widget.childId,
            },
      );
    } catch (e) {
      debugPrint('Ошибка отправки системного события в чат: $e');
    }
  }

  void _showProposeGoalDialog({
    String initialTitle = '',
    int initialTarget = 5000,
    int preservedCurrent = 0,
  }) {
    final titleController = TextEditingController(text: initialTitle);
    final targetController = TextEditingController(
      text: initialTarget > 0 ? initialTarget.toString() : '5000',
    );

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.emoji_events, color: Colors.amber, size: 26),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Предложить цель родителям',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'На что копим? (название награды)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: targetController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Стоимость в баллах',
                  suffixText: 'Б',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Цель появится на главном экране после подтверждения родителями.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              final title = titleController.text.trim();
              final target = int.tryParse(targetController.text.trim()) ?? 0;
              if (title.isEmpty || target <= 0 || widget.childId.isEmpty) {
                return;
              }

              await _childRef.child('goal').set({
                'title': title,
                'target': target,
                'current': preservedCurrent,
                'status': 'pending',
                'updatedAt': ServerValue.timestamp,
              });

              await _publishChildSystemEvent(
                '🎯 ${widget.childName} предложил(а) цель: «$title» ($target Б)',
              );

              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Запрос на установку цели отправлен родителям'),
                  backgroundColor: Colors.orange,
                ),
              );
            },
            child: const Text('Отправить запрос'),
          ),
        ],
      ),
    ).whenComplete(() {
      titleController.dispose();
      targetController.dispose();
    });
  }

  Future<void> _sendGoalToReview(String goalTitle) async {
    if (widget.childId.isEmpty) return;
    await _childRef.child('goal').update({
      'status': 'review',
      'reviewRequestedAt': ServerValue.timestamp,
    });

    final titleLabel = goalTitle.isNotEmpty ? '«$goalTitle»' : '';
    await _publishChildSystemEvent(
      '🎁 ${widget.childName} достиг(ла) цели $titleLabel и просит выдать награду!',
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Запрос на получение награды отправлен родителям!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _requestNewTaskFromParent() async {
    final noteController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.campaign_rounded, color: Colors.blue, size: 26),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Запросить задание у родителей',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width,
          child: TextField(
            controller: noteController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Например: Готов помочь по дому или сделать доп. уроки',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Отправить запрос'),
          ),
        ],
      ),
    );

    final noteText = noteController.text.trim();
    noteController.dispose();

    if (confirmed != true || widget.childId.isEmpty) return;

    final finalNote =
        noteText.isEmpty ? 'Хочу взять новое задание за баллы' : noteText;

    await _childRef.child('taskRequests').push().set({
      'childName': widget.childName,
      'note': finalNote,
      'status': 'pending',
      'createdAt': ServerValue.timestamp,
    });

    await _publishChildSystemEvent(
      '🙋 ${widget.childName} просит новое задание: «$finalNote»',
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Запрос на новое задание отправлен родителям!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _updateTaskStatus({
    required String taskKey,
    required String taskTitle,
    required String newStatus,
  }) async {
    await _childRef.child('tasks/$taskKey').update({
      'status': newStatus,
      'updatedAt': ServerValue.timestamp,
    });

    if (newStatus == 'in_progress') {
      await _publishChildSystemEvent(
        '🚀 ${widget.childName} взял(а) задание «$taskTitle» в работу',
      );
    } else if (newStatus == 'review') {
      await _publishChildSystemEvent(
        '✅ ${widget.childName} выполнил(а) задание «$taskTitle» и отправил(а) на проверку',
      );
    }
  }

  void _showChildHistorySheet(
    AppPalette palette,
    Map<dynamic, dynamic> childData,
  ) {
    final List historyItems = [];
    if (childData['taskHistory'] is Map) {
      final rawHistory =
          Map<dynamic, dynamic>.from(childData['taskHistory'] as Map);
      rawHistory.forEach((key, val) {
        if (val is Map) {
          historyItems.add({
            'title': val['title']?.toString() ?? 'Задание',
            'points': int.tryParse(val['points']?.toString() ?? '0') ?? 0,
            'status': val['status']?.toString() ?? 'completed',
            'isGoal': val['isGoal'] == true,
            'finishedAt':
                int.tryParse(val['finishedAt']?.toString() ?? '0') ?? 0,
          });
        }
      });
      historyItems.sort(
        (a, b) => (b['finishedAt'] as int).compareTo(a['finishedAt'] as int),
      );
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        height: MediaQuery.of(context).size.height * 0.72,
        decoration: BoxDecoration(
          color: palette.background.withValues(alpha: 0.96),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border.all(
            color: palette.primaryAccent.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: palette.textSecondary.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text(
                'История заданий и целей',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: palette.textPrimary,
                ),
              ),
            ),
            Expanded(
              child: historyItems.isEmpty
                  ? Center(
                      child: Text(
                        'История пока пуста',
                        style: TextStyle(color: palette.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                      itemCount: historyItems.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: palette.textSecondary.withValues(alpha: 0.2),
                      ),
                      itemBuilder: (context, idx) {
                        final item = historyItems[idx];
                        final String status = item['status'] as String;
                        final bool isCompleted = status == 'completed';
                        final bool isPenalty = status == 'penalty';
                        final bool isGoal = item['isGoal'] == true;
                        final int points = item['points'] as int;
                        final String dateStr =
                            _formatDateTime(item['finishedAt'] as int);

                        final String statusLabel = isCompleted
                            ? 'Выполнено'
                            : (isPenalty ? 'Штраф за пропуск' : 'Не выполнено');
                        final String pointsLabel = points == 0
                            ? ''
                            : (points > 0 ? '+$points Б' : '$points Б');

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            isGoal
                                ? Icons.emoji_events_rounded
                                : (isCompleted
                                    ? Icons.check_circle_rounded
                                    : (isPenalty
                                        ? Icons.warning_amber_rounded
                                        : Icons.cancel_rounded)),
                            color: isCompleted
                                ? AppTheme.successColor
                                : AppTheme.errorColor,
                          ),
                          title: Text(
                            isGoal
                                ? 'Цель: ${item['title']}'
                                : item['title'] as String,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Text(
                            '$statusLabel${dateStr.isNotEmpty ? ' • $dateStr' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isCompleted
                                  ? AppTheme.successColor
                                  : AppTheme.errorColor,
                            ),
                          ),
                          trailing: pointsLabel.isNotEmpty
                              ? Text(
                                  pointsLabel,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: isCompleted
                                        ? palette.primaryAccent
                                        : AppTheme.errorColor,
                                  ),
                                )
                              : null,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppTheme.getPalette('child', gender: widget.gender);

    return StreamBuilder<DatabaseEvent>(
      stream:
          widget.childId.isEmpty ? const Stream.empty() : _childRef.onValue,
      builder: (context, snapshot) {
        Map<dynamic, dynamic> childData = {};
        if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
          childData = Map<dynamic, dynamic>.from(
            snapshot.data!.snapshot.value as Map,
          );
        }

        final goalMap = childData['goal'] is Map
            ? Map<dynamic, dynamic>.from(childData['goal'] as Map)
            : {};
        final goalTitle = goalMap['title']?.toString() ?? '';
        final goalStatus = goalMap['status']?.toString() ??
            (goalTitle.isNotEmpty ? 'active' : 'none');
        final int currentPoints =
            int.tryParse(goalMap['current']?.toString() ?? '0') ?? 0;
        final int targetPoints =
            int.tryParse(goalMap['target']?.toString() ?? '0') ?? 0;
        final double progress = targetPoints > 0
            ? (currentPoints / targetPoints).clamp(0.0, 1.0)
            : 0.0;

        final bool isGoalPointsReached = goalStatus == 'active' &&
            targetPoints > 0 &&
            currentPoints >= targetPoints;

        final List currentTasks = [];
        final List completedTasks = [];
        final List uncompletedTasks = [];

        if (childData['tasks'] is Map) {
          final rawTasks =
              Map<dynamic, dynamic>.from(childData['tasks'] as Map);
          rawTasks.forEach((key, val) {
            if (val is Map) {
              final status = val['status']?.toString() ?? 'available';
              final item = <String, dynamic>{
                'key': key.toString(),
                'title': val['title']?.toString() ?? 'Задание',
                'points':
                    int.tryParse(val['points']?.toString() ?? '100') ?? 100,
                'isDaily': val['isDaily'] == true,
                'penaltyPoints':
                    int.tryParse(val['penaltyPoints']?.toString() ?? '0') ?? 0,
                'status': status,
              };
              if (status == 'done') {
                completedTasks.add(item);
              } else if (status == 'failed' || status == 'missed') {
                uncompletedTasks.add({
                  'title': item['title'],
                  'points': -(item['penaltyPoints'] as int),
                  'status': status,
                  'finishedAt':
                      int.tryParse(val['updatedAt']?.toString() ?? '0') ?? 0,
                });
              } else {
                currentTasks.add(item);
              }
            }
          });

          const order = {
            'in_progress': 0,
            'new': 1,
            'available': 2,
            'review': 3,
          };
          currentTasks.sort(
            (a, b) =>
                (order[a['status']] ?? 9).compareTo(order[b['status']] ?? 9),
          );
        }

        // Подтягиваем невыполненные и просроченные задания из истории
        if (childData['taskHistory'] is Map) {
          final rawHistory =
              Map<dynamic, dynamic>.from(childData['taskHistory'] as Map);
          rawHistory.forEach((key, val) {
            if (val is Map && val['isGoal'] != true) {
              final status = val['status']?.toString() ?? 'completed';
              if (status == 'failed' ||
                  status == 'missed' ||
                  status == 'penalty' ||
                  status == 'uncompleted') {
                uncompletedTasks.add({
                  'title': val['title']?.toString() ?? 'Задание',
                  'points': int.tryParse(val['points']?.toString() ?? '0') ?? 0,
                  'status': status,
                  'finishedAt':
                      int.tryParse(val['finishedAt']?.toString() ?? '0') ?? 0,
                });
              }
            }
          });
          uncompletedTasks.sort(
            (a, b) =>
                (b['finishedAt'] as int).compareTo(a['finishedAt'] as int),
          );
        }

        final bool canProposeNewGoal = goalStatus == 'none' ||
            goalStatus == 'rejected' ||
            goalStatus == 'completed';

        return Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                palette.backgroundAsset,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    Container(color: palette.background),
              ),
            ),
            Positioned.fill(
              child:
                  Container(color: palette.background.withValues(alpha: 0.55)),
            ),
            Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                iconTheme: IconThemeData(color: palette.textPrimary),
                title: Text(
                  'Задания и цели',
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                actions: [
                  IconButton(
                    tooltip: 'История заданий и целей',
                    icon: Icon(
                      Icons.history_rounded,
                      color: palette.primaryAccent,
                    ),
                    onPressed: () =>
                        _showChildHistorySheet(palette, childData),
                  ),
                ],
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  // БЛОК 1: ЕДИНСТВЕННАЯ ЦЕЛЬ И ЕЁ СТАТУС
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: palette.glassPanel,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: goalStatus == 'pending'
                            ? AppTheme.warningColor.withValues(alpha: 0.7)
                            : (goalStatus == 'review' || isGoalPointsReached)
                                ? AppTheme.successColor.withValues(alpha: 0.8)
                                : palette.primaryAccent
                                    .withValues(alpha: 0.35),
                        width: 1.3,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Моя цель',
                              style: TextStyle(
                                fontSize: 13,
                                color: palette.textSecondary,
                              ),
                            ),
                            if (goalStatus == 'pending')
                              _buildStatusBadge(
                                label: '⏳ Ожидает одобрения',
                                color: AppTheme.warningColor,
                              )
                            else if (goalStatus == 'review')
                              _buildStatusBadge(
                                label: '🎁 На проверке у родителей',
                                color: AppTheme.successColor,
                              )
                            else if (goalStatus == 'active')
                              _buildStatusBadge(
                                label: 'Выполняется',
                                color: palette.primaryAccent,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (goalStatus == 'none' || goalTitle.isEmpty) ...[
                          Text(
                            'Цель ещё не выбрана',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: palette.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Накоплено баллов: $currentPoints Б',
                            style: TextStyle(
                              fontSize: 13,
                              color: currentPoints < 0
                                  ? AppTheme.errorColor
                                  : palette.primaryAccent,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ] else ...[
                          Text(
                            goalTitle,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: palette.textPrimary,
                            ),
                          ),
                          if (goalStatus == 'rejected') ...[
                            const SizedBox(height: 6),
                            Text(
                              'Родители отклонили эту цель. Выбери другую награду или скорректируй баллы.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.errorColor,
                              ),
                            ),
                          ] else if (goalStatus == 'completed') ...[
                            const SizedBox(height: 6),
                            Text(
                              '🎉 Цель достигнута и закрыта родителями! Можно поставить новую.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.successColor,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 10,
                              backgroundColor:
                                  palette.textSecondary.withValues(alpha: 0.25),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                goalStatus == 'pending'
                                    ? AppTheme.warningColor
                                    : (goalStatus == 'review' ||
                                            isGoalPointsReached)
                                        ? AppTheme.successColor
                                        : palette.primaryAccent,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Накоплено: $currentPoints из $targetPoints Б',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: currentPoints < 0
                                      ? AppTheme.errorColor
                                      : palette.primaryAccent,
                                ),
                              ),
                              Text(
                                '${(progress * 100).round()}%',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: palette.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ],

                        if (isGoalPointsReached) ...[
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.successColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () => _sendGoalToReview(goalTitle),
                              icon: const Icon(Icons.card_giftcard_rounded),
                              label: const Text(
                                'ЦЕЛЬ ДОСТИГНУТА! ЗАБРАТЬ НАГРАДУ',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],

                        if (canProposeNewGoal) ...[
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: palette.primaryAccent,
                                side: BorderSide(color: palette.primaryAccent),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () => _showProposeGoalDialog(
                                initialTitle:
                                    goalStatus == 'rejected' ? goalTitle : '',
                                initialTarget:
                                    targetPoints > 0 ? targetPoints : 5000,
                                preservedCurrent: currentPoints,
                              ),
                              icon: const Icon(Icons.flag_rounded),
                              label: const Text('Установить цель'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // БЛОК 2: КНОПКА ЗАПРОСА НОВОГО ЗАДАНИЯ У РОДИТЕЛЕЙ
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: palette.primaryAccent,
                      foregroundColor: palette.background,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: _requestNewTaskFromParent,
                    icon: const Icon(Icons.add_task_rounded),
                    label: const Text(
                      'ЗАПРОСИТЬ ЗАДАНИЕ У РОДИТЕЛЕЙ',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // БЛОК 3: ТЕКУЩИЕ ЗАДАНИЯ ОТ РОДИТЕЛЕЙ
                  Text(
                    'Задания от родителей (${currentTasks.length})',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (currentTasks.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: palette.glassPanel,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'Пока нет активных заданий. Нажми кнопку выше, чтобы попросить задание у родителей и заработать баллы!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: palette.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    )
                  else
                    ...currentTasks.map((task) {
                      final status = task['status'] as String;
                      final key = task['key'] as String;
                      final title = task['title'] as String;
                      final points = task['points'] as int;
                      final bool isDaily = task['isDaily'] as bool;
                      final int penaltyPoints = task['penaltyPoints'] as int;

                      Widget actionWidget;
                      if (status == 'available' || status == 'new') {
                        actionWidget = ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: palette.primaryAccent,
                            foregroundColor: palette.background,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () => _updateTaskStatus(
                            taskKey: key,
                            taskTitle: title,
                            newStatus: 'in_progress',
                          ),
                          child: const Text('Взять'),
                        );
                      } else if (status == 'in_progress') {
                        actionWidget = ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.successColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () => _updateTaskStatus(
                            taskKey: key,
                            taskTitle: title,
                            newStatus: 'review',
                          ),
                          child: const Text('Выполнил'),
                        );
                      } else {
                        actionWidget = Text(
                          'На проверке',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.warningColor,
                          ),
                        );
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: palette.glassPanel,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: status == 'review'
                                ? AppTheme.warningColor.withValues(alpha: 0.6)
                                : palette.primaryAccent.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: palette.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        '+$points Б',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: palette.primaryAccent,
                                        ),
                                      ),
                                      if (isDaily)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: penaltyPoints > 0
                                                ? AppTheme.errorColor
                                                    .withValues(alpha: 0.22)
                                                : palette.secondaryAccent
                                                    .withValues(alpha: 0.25),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            penaltyPoints > 0
                                                ? '🔁 Каждый день • штраф -$penaltyPoints Б'
                                                : '🔁 Каждый день',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: penaltyPoints > 0
                                                  ? AppTheme.errorColor
                                                  : palette.textPrimary,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            actionWidget,
                          ],
                        ),
                      );
                    }),

                  // БЛОК 4: НЕВЫПОЛНЕННЫЕ / ПРОСРОЧЕННЫЕ ЗАДАНИЯ
                  if (uncompletedTasks.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Невыполненные задания (${uncompletedTasks.length})',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.errorColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...uncompletedTasks.take(10).map((task) {
                      final int points = task['points'] as int;
                      final int finishedAt = task['finishedAt'] as int;
                      final String dateStr = _formatDateTime(finishedAt);
                      final String penaltyStr =
                          points < 0 ? '$points Б' : 'Без штрафа';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: palette.glassPanel.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppTheme.errorColor.withValues(alpha: 0.38),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    task['title'] as String,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: palette.textPrimary,
                                    ),
                                  ),
                                  if (dateStr.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      dateStr,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        color: palette.textSecondary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              penaltyStr,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: points < 0
                                    ? AppTheme.errorColor
                                    : palette.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.cancel_rounded,
                              color: AppTheme.errorColor,
                              size: 20,
                            ),
                          ],
                        ),
                      );
                    }),
                  ],

                  // БЛОК 5: ВЫПОЛНЕННЫЕ ЗАДАНИЯ
                  if (completedTasks.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Выполнено (${completedTasks.length})',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: palette.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...completedTasks.map((task) {
                      final points = task['points'] as int;
                      final bool isDaily = task['isDaily'] as bool;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: palette.glassPanel.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                isDaily
                                    ? '${task['title']} 🔁'
                                    : task['title'] as String,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: palette.textSecondary,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            ),
                            Text(
                              '+$points Б',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.successColor,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.check_circle,
                              color: AppTheme.successColor,
                              size: 20,
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusBadge({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }
}