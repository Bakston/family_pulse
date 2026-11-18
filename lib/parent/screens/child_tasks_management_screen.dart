import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/daily_tasks_service.dart';
import '../../core/services/family_chat_service.dart';

class ChildTasksManagementScreen extends StatefulWidget {
  final String childId;
  final String childName;

  const ChildTasksManagementScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<ChildTasksManagementScreen> createState() =>
      _ChildTasksManagementScreenState();
}

class _ChildTasksManagementScreenState
    extends State<ChildTasksManagementScreen> {
  DatabaseReference get _childRef =>
      FirebaseDatabase.instance.ref('children/${widget.childId}');

  @override
  void initState() {
    super.initState();
    DailyTasksService.processDailyTasks(widget.childId);
  }

  String _formatDateTime(dynamic timestamp) {
    if (timestamp == null) return '';
    final int? millis = int.tryParse(timestamp.toString());
    if (millis == null || millis <= 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d.$m.${dt.year} в $h:$min';
  }

  Future<void> _publishParentSystemEvent(
    String Function(String actorName) buildText, {
    Map<String, dynamic>? action,
  }) async {
    if (widget.childId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentUid = prefs.getString('user_uid') ?? '';
      final localRole = prefs.getString('user_role') ?? 'Родитель';
      final localName = prefs.getString('user_name') ?? '';
      final actorName =
          localName.isNotEmpty ? '$localRole $localName' : localRole;

      String primaryParentUid = currentUid;
      if (primaryParentUid.isEmpty) {
        final parentSnap = await _childRef.child('parentUid').get();
        primaryParentUid = parentSnap.value?.toString() ?? '';
      }
      if (primaryParentUid.isEmpty) return;

      final chatId = await FamilyChatService.resolveChatIdForChild(
        primaryParentUid,
      );
      if (chatId.isEmpty) return;

      final memberIds = await FamilyChatService.resolveAllFamilyMemberIds(
        primaryParentUid: primaryParentUid,
      );

      await FamilyChatService.sendSystemEvent(
        chatId: chatId,
        text: buildText(actorName),
        notifyMemberIds: memberIds,
        excludeMemberId: currentUid.isNotEmpty ? currentUid : null,
        action: action ?? {'kind': 'open_tasks', 'childId': widget.childId},
      );
    } catch (e) {
      debugPrint('Ошибка публикации события родителя в чат: $e');
    }
  }

  void _showTaskFormDialog({
    String? existingTaskKey,
    String? initialTitle,
    int initialPoints = 250,
    bool initialIsDaily = false,
    int initialPenaltyPoints = 100,
    String? requestKeyToClose,
  }) {
    final isEditing = existingTaskKey != null;
    final titleController = TextEditingController(text: initialTitle ?? '');
    final pointsController = TextEditingController(
      text: initialPoints.toString(),
    );
    final penaltyController = TextEditingController(
      text: initialPenaltyPoints.toString(),
    );
    bool isDaily = initialIsDaily;

    showDialog(
      context: context,
      builder:
          (dialogContext) => StatefulBuilder(
            builder:
                (builderContext, setDialogState) => AlertDialog(
                  insetPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 24,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  title: Row(
                    children: [
                      Icon(
                        isEditing
                            ? Icons.edit_note_rounded
                            : Icons.add_task_rounded,
                        color: Colors.blue,
                        size: 26,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isEditing
                              ? 'Редактировать задание'
                              : 'Новое задание ребёнку',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  content: SizedBox(
                    width: MediaQuery.of(context).size.width,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: titleController,
                            autofocus: true,
                            decoration: InputDecoration(
                              labelText: 'Описание задания',
                              hintText: 'Например: Заправить кровать',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: pointsController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: 'Награда за выполнение',
                              suffixText: 'Б',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children:
                                [100, 250, 500, 1000]
                                    .map(
                                      (preset) => ActionChip(
                                        label: Text('+$preset Б'),
                                        onPressed: () {
                                          pointsController.text =
                                              preset.toString();
                                        },
                                      ),
                                    )
                                    .toList(),
                          ),
                          const Divider(height: 22),

                          // Переключатель ежедневного повторяющегося задания
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Повторять каждый день',
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: const Text(
                              'Задание обновляется каждые сутки автоматически',
                              style: TextStyle(fontSize: 12),
                            ),
                            value: isDaily,
                            activeThumbColor: Colors.deepPurple,
                            onChanged: (val) {
                              setDialogState(() => isDaily = val);
                            },
                          ),

                          if (isDaily) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: penaltyController,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText:
                                    'Штраф, если не выполнено до конца дня',
                                prefixText: '-',
                                suffixText: 'Б',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              children:
                                  [0, 50, 100, 250]
                                      .map(
                                        (preset) => ActionChip(
                                          label: Text(
                                            preset == 0
                                                ? 'Без штрафа'
                                                : '-$preset Б',
                                          ),
                                          onPressed: () {
                                            penaltyController.text =
                                                preset.toString();
                                          },
                                        ),
                                      )
                                      .toList(),
                            ),
                          ],
                        ],
                      ),
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
                        final points =
                            int.tryParse(pointsController.text.trim()) ?? 0;
                        final penalty =
                            isDaily
                                ? (int.tryParse(
                                          penaltyController.text.trim(),
                                        ) ??
                                        0)
                                    .clamp(0, 100000)
                                : 0;
                        if (title.isEmpty || points <= 0) return;

                        final todayKey = DailyTasksService.buildDateKey(
                          DateTime.now(),
                        );

                        if (isEditing) {
                          await _childRef
                              .child('tasks/$existingTaskKey')
                              .update({
                                'title': title,
                                'points': points,
                                'isDaily': isDaily,
                                'penaltyPoints': penalty,
                                if (isDaily) 'activeDate': todayKey,
                                'updatedAt': ServerValue.timestamp,
                              });
                        } else {
                          final newTaskRef = _childRef.child('tasks').push();
                          final newTaskId = newTaskRef.key ?? '';

                          await newTaskRef.set({
                            'title': title,
                            'points': points,
                            'isDaily': isDaily,
                            'penaltyPoints': penalty,
                            'activeDate': todayKey,
                            'status': 'available',
                            'createdAt': ServerValue.timestamp,
                          });

                          if (newTaskId.isNotEmpty) {
                            final dailyLabel =
                                isDaily
                                    ? (penalty > 0
                                        ? ' (ежедневно, штраф -$penalty Б)'
                                        : ' (ежедневно)')
                                    : '';
                            await _publishParentSystemEvent(
                              (actor) =>
                                  '📋 $actor добавил(а) задание для ${widget.childName}: «$title» (+$points Б)$dailyLabel',
                              action: {
                                'kind': 'accept_task',
                                'childId': widget.childId,
                                'taskId': newTaskId,
                                'buttonLabel': 'Принять задание',
                                'isCompleted': false,
                              },
                            );
                          }
                        }

                        if (requestKeyToClose != null) {
                          await _childRef
                              .child('taskRequests/$requestKeyToClose')
                              .update({'status': 'accepted'});
                        }

                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isEditing
                                  ? 'Задание «$title» обновлено'
                                  : 'Задание «$title» (+$points Б) добавлено',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      },
                      child: Text(isEditing ? 'Сохранить' : 'Добавить'),
                    ),
                  ],
                ),
          ),
    ).whenComplete(() {
      titleController.dispose();
      pointsController.dispose();
      penaltyController.dispose();
    });
  }

  /// Подтвердить выполнение задания -> начислить баллы + записать в историю + отправить событие в чат
  Future<void> _approveTask(String taskKey, String title, int points) async {
    final nowMillis = DateTime.now().millisecondsSinceEpoch;

    await _childRef.child('tasks/$taskKey').update({
      'status': 'done',
      'approvedAt': nowMillis,
    });
    await _childRef.child('goal').update({
      'current': ServerValue.increment(points),
    });
    await _childRef.child('taskHistory').push().set({
      'title': title,
      'points': points,
      'status': 'completed',
      'finishedAt': nowMillis,
    });

    await _publishParentSystemEvent(
      (actor) =>
          '🏆 $actor подтвердил(а) задание «$title» для ${widget.childName} (+$points Б)',
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Выполнение «$title» подтверждено (+$points Б)'),
        backgroundColor: Colors.green,
      ),
    );
  }

  /// Отклонить выполнение задания (или зафиксировать как невыполненное со штрафом)
  Future<void> _rejectTask(
    String taskKey,
    String title,
    int points, {
    bool isDaily = false,
    int penaltyPoints = 0,
  }) async {
    final action = await showDialog<String>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text('Отклонить выполнение?'),
            content: Text(
              penaltyPoints > 0
                  ? 'Вы можете вернуть задание «$title» на доработку или закрыть как невыполненное со штрафом -$penaltyPoints Б.'
                  : 'Вы можете вернуть задание «$title» на доработку ребёнку или закрыть его как невыполненное.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Отмена'),
              ),
              OutlinedButton(
                onPressed: () => Navigator.pop(dialogContext, 'rework'),
                child: const Text('На доработку'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                onPressed: () => Navigator.pop(dialogContext, 'failed'),
                child: Text(
                  penaltyPoints > 0
                      ? 'Не выполнено (-$penaltyPoints Б)'
                      : 'Не выполнено',
                ),
              ),
            ],
          ),
    );

    if (action == null) return;

    if (action == 'rework') {
      await _childRef.child('tasks/$taskKey').update({
        'status': 'available',
        'rejectedAt': ServerValue.timestamp,
      });

      await _publishParentSystemEvent(
        (actor) =>
            '🔄 $actor вернул(а) задание «$title» на доработку для ${widget.childName}',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Задание «$title» возвращено на доработку')),
      );
    } else if (action == 'failed') {
      final nowMillis = DateTime.now().millisecondsSinceEpoch;
      final int appliedPenalty = penaltyPoints > 0 ? penaltyPoints : 0;

      await _childRef.child('taskHistory').push().set({
        'title': title,
        'points': appliedPenalty > 0 ? -appliedPenalty : points,
        'status': appliedPenalty > 0 ? 'penalty' : 'failed',
        'finishedAt': nowMillis,
      });

      if (appliedPenalty > 0) {
        await _childRef.child('goal/current').runTransaction((Object? val) {
          final currentBalance = int.tryParse(val?.toString() ?? '0') ?? 0;
          return Transaction.success(currentBalance - appliedPenalty);
        });
      }

      if (isDaily) {
        // Ежедневное задание оставляем на завтра, но закрываем на сегодня как выполненное/прошедшее
        await _childRef.child('tasks/$taskKey').update({
          'status': 'done',
          'activeDate': DailyTasksService.buildDateKey(DateTime.now()),
        });
      } else {
        await _childRef.child('tasks/$taskKey').remove();
      }

      final penaltyMsg =
          appliedPenalty > 0 ? ' (штраф -$appliedPenalty Б)' : '';
      await _publishParentSystemEvent(
        (actor) =>
            '❌ $actor закрыл(а) задание «$title» как невыполненное$penaltyMsg',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            appliedPenalty > 0
                ? 'Задание закрыто как невыполненное (-$appliedPenalty Б)'
                : 'Задание «$title» отмечено как невыполненное',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _deleteTask(String taskKey) async {
    await _childRef.child('tasks/$taskKey').remove();
  }

  Future<void> _dismissTaskRequest(String requestKey) async {
    await _childRef.child('taskRequests/$requestKey').update({
      'status': 'dismissed',
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Задания: ${widget.childName}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Управление и проверка выполнения',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => _showTaskFormDialog(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Добавить'),
            ),
          ),
        ],
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: _childRef.onValue,
        builder: (context, snapshot) {
          Map<dynamic, dynamic> childData = {};
          if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
            childData = Map<dynamic, dynamic>.from(
              snapshot.data!.snapshot.value as Map,
            );
          }

          final List pendingRequests = [];
          if (childData['taskRequests'] is Map) {
            final rawReqs = Map<dynamic, dynamic>.from(
              childData['taskRequests'] as Map,
            );
            rawReqs.forEach((key, val) {
              if (val is Map && val['status']?.toString() == 'pending') {
                pendingRequests.add({
                  'key': key.toString(),
                  'note': val['note']?.toString() ?? 'Запрос на новое задание',
                });
              }
            });
          }

          final List currentTasks = [];
          final List completedTasks = [];

          if (childData['tasks'] is Map) {
            final rawTasks = Map<dynamic, dynamic>.from(
              childData['tasks'] as Map,
            );
            rawTasks.forEach((key, val) {
              if (val is Map) {
                final status = val['status']?.toString() ?? 'available';
                final item = {
                  'key': key.toString(),
                  'title': val['title']?.toString() ?? 'Задание',
                  'points':
                      int.tryParse(val['points']?.toString() ?? '100') ?? 100,
                  'isDaily': val['isDaily'] == true,
                  'penaltyPoints':
                      int.tryParse(val['penaltyPoints']?.toString() ?? '0') ??
                      0,
                  'status': status,
                  'approvedAt': val['approvedAt'],
                };
                if (status == 'done') {
                  completedTasks.add(item);
                } else {
                  currentTasks.add(item);
                }
              }
            });

            const order = {'review': 0, 'in_progress': 1, 'available': 2};
            currentTasks.sort(
              (a, b) =>
                  (order[a['status']] ?? 9).compareTo(order[b['status']] ?? 9),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Запросы от ребёнка
              if (pendingRequests.isNotEmpty) ...[
                const Text(
                  'Запросы заданий от ребёнка',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepOrange,
                  ),
                ),
                const SizedBox(height: 8),
                ...pendingRequests.map(
                  (req) => Card(
                    color: Colors.orange.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: Colors.orange.shade200),
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.campaign_rounded,
                        color: Colors.deepOrange,
                      ),
                      title: Text(
                        req['note'] as String,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.grey),
                            onPressed:
                                () => _dismissTaskRequest(req['key'] as String),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepOrange,
                              foregroundColor: Colors.white,
                            ),
                            onPressed:
                                () => _showTaskFormDialog(
                                  initialTitle: req['note'] as String,
                                  requestKeyToClose: req['key'] as String,
                                ),
                            child: const Text('Дать'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ТЕКУЩИЕ ЗАДАНИЯ
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Текущие задания (${currentTasks.length})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (currentTasks.isEmpty)
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Активных заданий сейчас нет. Нажмите «+ Добавить» сверху, чтобы создать новое.',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                )
              else
                ...currentTasks.map((task) {
                  final key = task['key'] as String;
                  final title = task['title'] as String;
                  final points = task['points'] as int;
                  final bool isDaily = task['isDaily'] as bool;
                  final int penaltyPoints = task['penaltyPoints'] as int;
                  final status = task['status'] as String;

                  final bool isReview = status == 'review';
                  final String statusText =
                      isReview
                          ? 'Ожидает подтверждения'
                          : (status == 'in_progress'
                              ? 'Выполняется ребёнком'
                              : 'Назначено');
                  final Color statusColor =
                      isReview
                          ? Colors.deepOrange
                          : (status == 'in_progress'
                              ? Colors.blue
                              : Colors.grey);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    color: isReview ? Colors.amber.shade50 : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side:
                          isReview
                              ? BorderSide(
                                color: Colors.amber.shade600,
                                width: 1.3,
                              )
                              : BorderSide.none,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Редактировать',
                                icon: const Icon(
                                  Icons.edit_outlined,
                                  color: Colors.blueGrey,
                                  size: 20,
                                ),
                                onPressed:
                                    () => _showTaskFormDialog(
                                      existingTaskKey: key,
                                      initialTitle: title,
                                      initialPoints: points,
                                      initialIsDaily: isDaily,
                                      initialPenaltyPoints:
                                          penaltyPoints > 0
                                              ? penaltyPoints
                                              : 100,
                                    ),
                              ),
                              IconButton(
                                tooltip: 'Удалить',
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.redAccent,
                                  size: 20,
                                ),
                                onPressed: () => _deleteTask(key),
                              ),
                            ],
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '+$points Б',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                  fontSize: 13,
                                ),
                              ),
                              if (isDaily)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.deepPurple.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    penaltyPoints > 0
                                        ? '🔁 Каждый день • штраф -$penaltyPoints Б'
                                        : '🔁 Каждый день',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.deepPurple.shade700,
                                    ),
                                  ),
                                ),
                              Text(
                                '• $statusText',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: statusColor,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          if (isReview) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onPressed:
                                        () => _approveTask(key, title, points),
                                    icon: const Icon(Icons.check, size: 18),
                                    label: const Text('Подтвердить'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.redAccent,
                                      side: const BorderSide(
                                        color: Colors.redAccent,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onPressed:
                                        () => _rejectTask(
                                          key,
                                          title,
                                          points,
                                          isDaily: isDaily,
                                          penaltyPoints: penaltyPoints,
                                        ),
                                    icon: const Icon(Icons.close, size: 18),
                                    label: const Text('Отклонить'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),

              const SizedBox(height: 16),

              // ВЫПОЛНЕННЫЕ ЗАДАНИЯ
              Text(
                'Выполненные задания (${completedTasks.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              if (completedTasks.isEmpty)
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Выполненных заданий в текущем списке пока нет',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                )
              else
                ...completedTasks.map((task) {
                  final key = task['key'] as String;
                  final title = task['title'] as String;
                  final points = task['points'] as int;
                  final bool isDaily = task['isDaily'] as bool;
                  final dateStr = _formatDateTime(task['approvedAt']);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: Colors.white.withValues(alpha: 0.85),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.green,
                      ),
                      title: Text(
                        isDaily ? '$title 🔁' : title,
                        style: const TextStyle(
                          decoration: TextDecoration.lineThrough,
                          color: Colors.black87,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        dateStr.isNotEmpty
                            ? '+$points Б • Выполнено $dateStr'
                            : '+$points Б',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: IconButton(
                        tooltip: 'Удалить из списка',
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.black45,
                          size: 20,
                        ),
                        onPressed: () => _deleteTask(key),
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}
