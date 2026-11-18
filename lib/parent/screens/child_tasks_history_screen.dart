import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../../features/widgets/family_calendar_widget.dart';

class ChildTasksHistoryScreen extends StatefulWidget {
  final String childId;
  final String childName;

  const ChildTasksHistoryScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<ChildTasksHistoryScreen> createState() =>
      _ChildTasksHistoryScreenState();
}

class _ChildTasksHistoryScreenState extends State<ChildTasksHistoryScreen> {
  String _filter = 'all'; // 'all', 'completed', 'failed', 'penalty'
  DateTime? _selectedDate;

  DatabaseReference get _historyRef =>
      FirebaseDatabase.instance.ref('children/${widget.childId}/taskHistory');

  String _formatDateTime(int millis) {
    if (millis <= 0) return 'Дата неизвестна';
    final dt = DateTime.fromMillisecondsSinceEpoch(millis);
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d.$m.${dt.year} в $h:$min';
  }

  String _formatShortDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d.$m.${dt.year}';
  }

  Future<void> _pickFilterDate() async {
    final now = DateTime.now();
    final picked = await FamilyCalendarWidget.showPickerDialog(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      title: 'Фильтр по дате',
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
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
              'История: ${widget.childName}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            Text(
              _selectedDate != null
                  ? 'За дату: ${_formatShortDate(_selectedDate!)}'
                  : 'Архив выполненных заданий, пропусков и штрафов',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          if (_selectedDate != null)
            IconButton(
              tooltip: 'Сбросить дату',
              icon: const Icon(Icons.filter_alt_off_rounded, color: Colors.redAccent),
              onPressed: () => setState(() => _selectedDate = null),
            ),
          IconButton(
            tooltip: 'Выбрать дату в календаре',
            icon: Icon(
              Icons.calendar_month_rounded,
              color: _selectedDate != null ? Colors.blue.shade700 : Colors.indigo,
            ),
            onPressed: _pickFilterDate,
          ),
        ],
      ),
      body: Column(
        children: [
          // Фильтры
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('Все'),
                    selected: _filter == 'all',
                    onSelected: (_) => setState(() => _filter = 'all'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Выполнено'),
                    selected: _filter == 'completed',
                    onSelected: (_) => setState(() => _filter = 'completed'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Не выполнено'),
                    selected: _filter == 'failed',
                    onSelected: (_) => setState(() => _filter = 'failed'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Штрафы'),
                    selected: _filter == 'penalty',
                    onSelected: (_) => setState(() => _filter = 'penalty'),
                  ),
                ],
              ),
            ),
          ),

          Expanded(
            child: StreamBuilder<DatabaseEvent>(
              stream: _historyRef.onValue,
              builder: (context, snapshot) {
                final List items = [];

                if (snapshot.hasData &&
                    snapshot.data!.snapshot.value != null) {
                  final rawMap = Map<dynamic, dynamic>.from(
                    snapshot.data!.snapshot.value as Map,
                  );
                  rawMap.forEach((key, val) {
                    if (val is Map) {
                      final status = val['status']?.toString() ?? 'completed';
                      final int finishedAt = int.tryParse(
                            val['finishedAt']?.toString() ?? '0',
                          ) ??
                          0;

                      if (_selectedDate != null && finishedAt > 0) {
                        final dt = DateTime.fromMillisecondsSinceEpoch(finishedAt);
                        if (dt.year != _selectedDate!.year ||
                            dt.month != _selectedDate!.month ||
                            dt.day != _selectedDate!.day) {
                          return;
                        }
                      }

                      if (_filter == 'completed' && status != 'completed') {
                        return;
                      }
                      if (_filter == 'failed' &&
                          status != 'failed' &&
                          status != 'penalty') {
                        return;
                      }
                      if (_filter == 'penalty' && status != 'penalty') {
                        return;
                      }

                      items.add({
                        'key': key.toString(),
                        'title': val['title']?.toString() ?? 'Задание',
                        'points': int.tryParse(
                              val['points']?.toString() ?? '0',
                            ) ??
                            0,
                        'status': status,
                        'isGoal': val['isGoal'] == true,
                        'finishedAt': finishedAt,
                      });
                    }
                  });

                  items.sort(
                    (a, b) => (b['finishedAt'] as int)
                        .compareTo(a['finishedAt'] as int),
                  );
                }

                if (items.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Text(
                        _selectedDate != null
                            ? 'За ${_formatShortDate(_selectedDate!)} записей не найдено'
                            : 'Записей в истории заданий пока нет',
                        style: const TextStyle(color: Colors.black54, fontSize: 14),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final String status = item['status'] as String;
                    final bool isCompleted = status == 'completed';
                    final bool isPenalty = status == 'penalty';
                    final bool isGoal = item['isGoal'] == true;
                    final int points = item['points'] as int;
                    final int finishedAt = item['finishedAt'] as int;

                    final String statusLabel = isCompleted
                        ? 'Выполнено'
                        : (isPenalty ? 'Штраф за пропуск' : 'Не выполнено');

                    final String pointsLabel = points == 0
                        ? ''
                        : (points > 0 ? '+$points Б' : '$points Б');

                    return Card(
                      margin: EdgeInsets.zero,
                      color: isPenalty
                          ? Colors.red.shade50.withValues(alpha: 0.65)
                          : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: isPenalty
                            ? BorderSide(color: Colors.red.shade200)
                            : BorderSide.none,
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isCompleted
                              ? Colors.green.shade50
                              : Colors.red.shade50,
                          child: Icon(
                            isGoal
                                ? Icons.emoji_events_rounded
                                : (isCompleted
                                    ? Icons.check_circle_rounded
                                    : (isPenalty
                                        ? Icons.warning_amber_rounded
                                        : Icons.cancel_rounded)),
                            color: isCompleted ? Colors.green : Colors.redAccent,
                          ),
                        ),
                        title: Text(
                          isGoal
                              ? 'Цель: ${item['title']}'
                              : item['title'] as String,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          '$statusLabel • ${_formatDateTime(finishedAt)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: isCompleted
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                          ),
                        ),
                        trailing: pointsLabel.isNotEmpty
                            ? Text(
                                pointsLabel,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: isCompleted
                                      ? Colors.blue.shade700
                                      : (isPenalty
                                          ? Colors.red.shade700
                                          : Colors.black45),
                                ),
                              )
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}