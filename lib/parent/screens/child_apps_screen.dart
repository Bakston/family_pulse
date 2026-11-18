import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/app_control_service.dart';
import '../../core/services/family_chat_service.dart';
import '../../core/services/web_filter_service.dart';

class ChildAppsScreen extends StatefulWidget {
  final String childId;
  final String childName;
  final String? initialPackageName;

  const ChildAppsScreen({
    super.key,
    required this.childId,
    required this.childName,
    this.initialPackageName,
  });

  @override
  State<ChildAppsScreen> createState() => _ChildAppsScreenState();
}

class _ChildAppsScreenState extends State<ChildAppsScreen> {
  static const List<String> _dayLabels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  bool _initialAppOpened = false;

  DatabaseReference get _childRef =>
      FirebaseDatabase.instance.ref('children/${widget.childId}');

  String _formatMinutesToTime(int totalMinutes) {
    final h = (totalMinutes ~/ 60).toString().padLeft(2, '0');
    final m = (totalMinutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatSingleRuleText(Map<dynamic, dynamic> ruleMap) {
    final parts = <String>[];

    final rawDays = ruleMap['allowedDays'];
    if (rawDays is List && rawDays.isNotEmpty && rawDays.length < 7) {
      final days = rawDays
          .map((e) => int.tryParse(e.toString()) ?? 0)
          .where((d) => d >= 1 && d <= 7)
          .toList()
        ..sort();
      if (days.isNotEmpty) {
        parts.add(days.map((d) => _dayLabels[d - 1]).join(', '));
      }
    } else {
      parts.add('Пн–Вс');
    }

    if (ruleMap['useTimeWindow'] == true) {
      final start = int.tryParse(ruleMap['startMinutes']?.toString() ?? '0') ?? 0;
      final end = int.tryParse(ruleMap['endMinutes']?.toString() ?? '1439') ?? 1439;
      parts.add('${_formatMinutesToTime(start)}–${_formatMinutesToTime(end)}');
    }

    final limit =
        int.tryParse(ruleMap['dailyLimitMinutes']?.toString() ?? '0') ?? 0;
    if (limit > 0) {
      parts.add('лимит $limit мин');
    }

    return parts.join(' • ');
  }

  String _buildCategorySummary(Map<dynamic, dynamic> catData) {
    if (catData['isBlocked'] == true) {
      return 'Заблокировано полностью';
    }

    final rules = AppControlService.extractCategoryRules(catData);
    if (rules.isEmpty) {
      return 'Без ограничений';
    }

    return rules.map((r) => _formatSingleRuleText(r as Map)).join(' | ');
  }

  /// Отправка системного уведомления в семейный чат при выдаче, отмене или отклонении доступа
  Future<void> _notifyChildTempAccessChanged({
    required String appName,
    required String actionType, // 'granted', 'cancelled', 'rejected'
    int? grantedMinutes,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final currentActorUid = prefs.getString('user_uid') ?? '';

      final parentSnap = await _childRef.child('parentUid').get();
      final parentUid = parentSnap.value?.toString() ?? '';
      if (parentUid.isEmpty) return;

      final chatId = await FamilyChatService.resolveChatIdForChild(parentUid);
      if (chatId.isEmpty) return;

      final memberIds = await FamilyChatService.resolveAllFamilyMemberIds(
        primaryParentUid: parentUid,
      );

      final String eventText;
      if (actionType == 'granted' && grantedMinutes != null) {
        eventText = '🔓 Приложение «$appName» разблокировано на $grantedMinutes мин.';
      } else if (actionType == 'rejected') {
        eventText = '❌ Запрос на доступ к приложению «$appName» отклонён';
      } else {
        eventText = '🔒 Временный доступ к приложению «$appName» отменён';
      }

      await FamilyChatService.sendSystemEvent(
        chatId: chatId,
        text: eventText,
        notifyMemberIds: [...memberIds, widget.childId],
        excludeMemberId: currentActorUid.isNotEmpty ? currentActorUid : parentUid,
      );
    } catch (e) {
      debugPrint('[ChildAppsScreen] Ошибка отправки уведомления в чат: $e');
    }
  }

  /// Шторка настройки фильтрации контента в интернете (DNS-VPN)
  void _showWebFilterSheet() {
    final domainController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StreamBuilder<DatabaseEvent>(
        stream: _childRef.child('webFilter').onValue,
        builder: (modalContext, snapshot) {
          final filterMap =
              (snapshot.hasData && snapshot.data!.snapshot.value is Map)
                  ? Map<dynamic, dynamic>.from(
                      snapshot.data!.snapshot.value as Map,
                    )
                  : <dynamic, dynamic>{};

          final bool enabled = filterMap['enabled'] != false;
          final String mode = filterMap['mode']?.toString() == 'whitelist'
              ? 'whitelist'
              : 'blacklist';
          final bool blockAdult = filterMap['blockAdult'] != false;
          final String activeListKey =
              mode == 'whitelist' ? 'allowedDomains' : 'blockedDomains';
          final List<String> domains =
              WebFilterService.extractDomains(filterMap[activeListKey]);

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.of(modalContext).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.vpn_lock_rounded, color: Colors.teal.shade700),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Фильтрация интернета',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Включить веб-фильтр на устройстве',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Работает во всех браузерах и приложениях через локальный DNS-фильтр',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: enabled,
                    activeThumbColor: Colors.teal,
                    onChanged: (val) => WebFilterService.updateFilterSettings(
                      childId: widget.childId,
                      enabled: val,
                      mode: mode,
                      blockAdult: blockAdult,
                    ),
                  ),
                  if (enabled) ...[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Блокировать сайты 18+ и SafeSearch',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Отсекает взрослый контент, казино и включает безопасный поиск в Google/Яндекс/YouTube',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: blockAdult,
                      activeThumbColor: Colors.teal,
                      onChanged: (val) => WebFilterService.updateFilterSettings(
                        childId: widget.childId,
                        enabled: enabled,
                        mode: mode,
                        blockAdult: val,
                      ),
                    ),
                    const Divider(height: 20),
                    const Text(
                      'Режим фильтрации сайтов:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'blacklist',
                          label: Text(
                            'Чёрный список',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        ButtonSegment(
                          value: 'whitelist',
                          label: Text(
                            'Только разрешённые',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                      selected: {mode},
                      onSelectionChanged: (newSet) =>
                          WebFilterService.updateFilterSettings(
                        childId: widget.childId,
                        enabled: enabled,
                        mode: newSet.first,
                        blockAdult: blockAdult,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      mode == 'whitelist'
                          ? 'Разрешённые сайты (остальные будут заблокированы):'
                          : 'Заблокированные сайты (дополнительно к 18+):',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: domainController,
                            keyboardType: TextInputType.url,
                            decoration: InputDecoration(
                              hintText: mode == 'whitelist'
                                  ? 'Например: uchi.ru'
                                  : 'Например: tiktok.com',
                              isDense: true,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 13,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () async {
                            final text = domainController.text.trim();
                            if (text.isEmpty) return;
                            await WebFilterService.addDomain(
                              childId: widget.childId,
                              listType: activeListKey,
                              rawDomain: text,
                            );
                            domainController.clear();
                          },
                          child: const Text('Добавить'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (domains.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          mode == 'whitelist'
                              ? 'Список пуст — добавьте учебные и разрешённые сайты (например, uchi.ru, wikipedia.org).'
                              : 'Дополнительных сайтов в чёрном списке пока нет.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: domains
                            .map(
                              (domain) => Chip(
                                label: Text(domain),
                                deleteIcon: const Icon(Icons.close, size: 16),
                                onDeleted: () => WebFilterService.removeDomain(
                                  childId: widget.childId,
                                  listType: activeListKey,
                                  domain: domain,
                                ),
                              ),
                            )
                            .toList(),
                      ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(domainController.dispose);
  }

  /// Диалог создания новой категории
  void _showAddCategoryDialog() {
    final nameController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.create_new_folder_outlined, color: Colors.blue, size: 26),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Новая категория',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: MediaQuery.of(context).size.width,
          child: TextField(
            controller: nameController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Название (например: Видео, Мессенджеры)',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
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
              final title = nameController.text.trim();
              if (title.isEmpty) return;

              final catId = 'cat_${DateTime.now().millisecondsSinceEpoch}';
              await _childRef.child('appCategories/$catId').set({
                'title': title,
                'isBlocked': false,
                'rules': [],
                'createdAt': ServerValue.timestamp,
              });

              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    ).whenComplete(nameController.dispose);
  }

  /// Диалог добавления или редактирования ОДНОГО правила внутри категории
  Future _showRuleBuilderDialog({
    Map<dynamic, dynamic>? existingRule,
  }) async {
    final Set<int> selectedDays = {1, 2, 3, 4, 5, 6, 7};
    if (existingRule != null && existingRule['allowedDays'] is List) {
      final parsed = (existingRule['allowedDays'] as List)
          .map((e) => int.tryParse(e.toString()) ?? 0)
          .where((d) => d >= 1 && d <= 7)
          .toSet();
      if (parsed.isNotEmpty) {
        selectedDays
          ..clear()
          ..addAll(parsed);
      }
    }

    bool useTimeWindow = existingRule?['useTimeWindow'] == true;
    int startMinutes =
        int.tryParse(existingRule?['startMinutes']?.toString() ?? '1140') ??
            1140;
    int endMinutes =
        int.tryParse(existingRule?['endMinutes']?.toString() ?? '1200') ??
            1200;
    final limitController = TextEditingController(
      text:
          (int.tryParse(existingRule?['dailyLimitMinutes']?.toString() ?? '0') ??
                  0)
              .toString(),
    );

    final result = await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (builderContext, setDialogState) {
          return AlertDialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(
              existingRule == null
                  ? 'Добавить правило доступа'
                  : 'Редактировать правило',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            content: SizedBox(
              width: MediaQuery.of(context).size.width,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Дни недели:',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: List.generate(7, (idx) {
                        final dayNum = idx + 1;
                        return FilterChip(
                          label: Text(_dayLabels[idx]),
                          selected: selectedDays.contains(dayNum),
                          onSelected: (val) {
                            setDialogState(() {
                              if (val) {
                                selectedDays.add(dayNum);
                              } else if (selectedDays.length > 1) {
                                selectedDays.remove(dayNum);
                              }
                            });
                          },
                        );
                      }),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        ActionChip(
                          label: const Text('Будни (Пн–Пт)'),
                          onPressed: () => setDialogState(() {
                            selectedDays
                              ..clear()
                              ..addAll([1, 2, 3, 4, 5]);
                          }),
                        ),
                        ActionChip(
                          label: const Text('Выходные (Сб–Вс)'),
                          onPressed: () => setDialogState(() {
                            selectedDays
                              ..clear()
                              ..addAll([6, 7]);
                          }),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Ограничить по часам',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      value: useTimeWindow,
                      onChanged: (val) =>
                          setDialogState(() => useTimeWindow = val),
                    ),
                    if (useTimeWindow)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay(
                                    hour: startMinutes ~/ 60,
                                    minute: startMinutes % 60,
                                  ),
                                );
                                if (picked != null) {
                                  setDialogState(() {
                                    startMinutes =
                                        picked.hour * 60 + picked.minute;
                                  });
                                }
                              },
                              child: Text(
                                'С ${_formatMinutesToTime(startMinutes)}',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () async {
                                final picked = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay(
                                    hour: endMinutes ~/ 60,
                                    minute: endMinutes % 60,
                                  ),
                                );
                                if (picked != null) {
                                  setDialogState(() {
                                    endMinutes =
                                        picked.hour * 60 + picked.minute;
                                  });
                                }
                              },
                              child: Text(
                                'До ${_formatMinutesToTime(endMinutes)}',
                              ),
                            ),
                          ),
                        ],
                      ),
                    const Divider(height: 20),
                    TextField(
                      controller: limitController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Лимит времени в день (0 = без лимита)',
                        suffixText: 'мин',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [0, 60, 120, 180]
                          .map(
                            (m) => ActionChip(
                              label: Text(
                                m == 0
                                    ? 'Без лимита'
                                    : m % 60 == 0
                                        ? '${m ~/ 60} ч'
                                        : '$m мин',
                              ),
                              onPressed: () =>
                                  limitController.text = m.toString(),
                            ),
                          )
                          .toList(),
                    ),
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
                onPressed: () {
                  final limit =
                      int.tryParse(limitController.text.trim()) ?? 0;
                  final sortedDays = selectedDays.toList()..sort();
                  Navigator.pop(dialogContext, {
                    'allowedDays': sortedDays,
                    'useTimeWindow': useTimeWindow,
                    'startMinutes': startMinutes,
                    'endMinutes': endMinutes,
                    'dailyLimitMinutes': limit < 0 ? 0 : limit,
                  });
                },
                child: const Text('Готово'),
              ),
            ],
          );
        },
      ),
    );

    limitController.dispose();
    return result;
  }

  /// Панель редактирования КАТЕГОРИИ
  void _showCategoryEditorSheet(
    String categoryId,
    String currentTitle,
    bool isDefault,
    Map<dynamic, dynamic> currentCatData,
    Map<dynamic, dynamic> allAppsMap,
  ) {
    final titleController = TextEditingController(text: currentTitle);
    bool isBlocked = currentCatData['isBlocked'] == true;
    final List rules =
        AppControlService.extractCategoryRules(currentCatData);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (modalContext, setSheetState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'Настройка категории',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (!isDefault)
                        IconButton(
                          tooltip: 'Удалить категорию',
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.red,
                          ),
                          onPressed: () async {
                            final updates = <String, dynamic>{};
                            allAppsMap.forEach((k, v) {
                              if (!k.toString().startsWith('_') &&
                                  v is Map &&
                                  v['category']?.toString() == categoryId) {
                                updates['installedApps/$k/category'] = 'other';
                              }
                            });
                            updates['appCategories/$categoryId'] = null;
                            await _childRef.update(updates);

                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: titleController,
                    decoration: InputDecoration(
                      labelText: 'Название категории',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Заблокировать категорию полностью',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    activeThumbColor: Colors.red,
                    value: isBlocked,
                    onChanged: (val) => setSheetState(() => isBlocked = val),
                  ),
                  if (!isBlocked) ...[
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Правила доступа:',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () async {
                            final newRule = await _showRuleBuilderDialog();
                            if (newRule != null) {
                              setSheetState(() => rules.add(newRule));
                            }
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Добавить правило'),
                        ),
                      ],
                    ),
                    if (rules.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Правил нет — категория доступна в любое время без лимитов. Нажмите «+ Добавить правило», чтобы задать расписание по дням и часам.',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      )
                    else
                      ...List.generate(rules.length, (idx) {
                        final rule = rules[idx];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _formatSingleRuleText(rule as Map),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Изменить правило',
                                icon: const Icon(
                                  Icons.edit_outlined,
                                  size: 19,
                                  color: Colors.blueGrey,
                                ),
                                onPressed: () async {
                                  final edited = await _showRuleBuilderDialog(
                                    existingRule: rule,
                                  );
                                  if (edited != null) {
                                    setSheetState(() => rules[idx] = edited);
                                  }
                                },
                              ),
                              IconButton(
                                tooltip: 'Удалить правило',
                                icon: const Icon(
                                  Icons.close,
                                  size: 19,
                                  color: Colors.red,
                                ),
                                onPressed: () =>
                                    setSheetState(() => rules.removeAt(idx)),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () async {
                      final newTitle = titleController.text.trim().isEmpty
                          ? currentTitle
                          : titleController.text.trim();

                      await _childRef.child('appCategories/$categoryId').update({
                        'title': newTitle,
                        'isBlocked': isBlocked,
                        'rules': rules,
                        'allowedDays': null,
                        'useTimeWindow': null,
                        'startMinutes': null,
                        'endMinutes': null,
                        'dailyLimitMinutes': null,
                        'updatedAt': ServerValue.timestamp,
                      });

                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                    child: const Text(
                      'Сохранить настройки категории',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(titleController.dispose);
  }

  /// Панель редактирования ПРИЛОЖЕНИЯ (мгновенное временное разрешение, отклонение и отмена с уведомлением в чат)
  void _showAppEditorSheet(
    String appKey,
    Map<dynamic, dynamic> appData,
    List allCategories,
  ) {
    final appName = appData['appName']?.toString() ?? 'Приложение';
    final packageName = appData['packageName']?.toString() ?? '';
    final timeSpent = appData['timeSpentMinutes'] ?? 0;

    final validIds = allCategories.map((c) => c['id'].toString()).toSet();
    String category = appData['category']?.toString() ?? 'other';
    if (!validIds.contains(category)) {
      category = 'other';
    }

    String ruleMode = appData['ruleMode']?.toString() ?? 'inherit';
    bool isBlocked = appData['isBlocked'] == true;

    final Set<int> selectedDays = {1, 2, 3, 4, 5, 6, 7};
    if (appData['allowedDays'] is List) {
      final parsed = (appData['allowedDays'] as List)
          .map((e) => int.tryParse(e.toString()) ?? 0)
          .where((d) => d >= 1 && d <= 7)
          .toSet();
      if (parsed.isNotEmpty) {
        selectedDays
          ..clear()
          ..addAll(parsed);
      }
    }

    bool useTimeWindow = appData['useTimeWindow'] == true;
    int startMinutes =
        int.tryParse(appData['startMinutes']?.toString() ?? '1140') ?? 1140;
    int endMinutes =
        int.tryParse(appData['endMinutes']?.toString() ?? '1260') ?? 1260;
    final limitController = TextEditingController(
      text: (int.tryParse(appData['dailyLimitMinutes']?.toString() ?? '0') ?? 0)
          .toString(),
    );

    final int tempAllowUntil =
        int.tryParse(appData['tempAllowUntil']?.toString() ?? '0') ?? 0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (modalContext, setSheetState) {
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          final bool isTempActive = tempAllowUntil > nowMs;
          final int remainingTempMins = isTempActive
              ? ((tempAllowUntil - nowMs) / 60000).ceil()
              : 0;

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    appName,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '$packageName • Сегодня: $timeSpent мин.',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),

                  // 1. Временное разрешение / Отклонение (срабатывает в 1 клик сразу в БД + уведомление ребёнку в чат)
                  const Text(
                    'Быстрое решение по доступу (срабатывает сразу):',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  if (isTempActive)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Разрешено ещё $remainingTempMins мин.',
                            style: TextStyle(
                              color: Colors.green.shade800,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              await _childRef
                                  .child('installedApps/$appKey')
                                  .update({'tempAllowUntil': 0});

                              await _notifyChildTempAccessChanged(
                                appName: appName,
                                actionType: 'cancelled',
                              );

                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Временный доступ к «$appName» отменён',
                                  ),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            },
                            child: const Text(
                              'Отменить',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        ...[15, 30, 60].map(
                          (mins) => ActionChip(
                            avatar: const Icon(
                              Icons.bolt_rounded,
                              size: 16,
                              color: Colors.green,
                            ),
                            label: Text('Разрешить на $mins мин'),
                            onPressed: () async {
                              final untilMs = DateTime.now()
                                  .add(Duration(minutes: mins))
                                  .millisecondsSinceEpoch;

                              await _childRef
                                  .child('installedApps/$appKey')
                                  .update({'tempAllowUntil': untilMs});

                              await _notifyChildTempAccessChanged(
                                appName: appName,
                                actionType: 'granted',
                                grantedMinutes: mins,
                              );

                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '«$appName» разрешено на $mins мин',
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            },
                          ),
                        ),
                        ActionChip(
                          avatar: const Icon(
                            Icons.block_rounded,
                            size: 16,
                            color: Colors.red,
                          ),
                          label: const Text('Отклонить'),
                          onPressed: () async {
                            await _childRef
                                .child('installedApps/$appKey')
                                .update({'tempAllowUntil': 0});

                            await _notifyChildTempAccessChanged(
                              appName: appName,
                              actionType: 'rejected',
                            );

                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Запрос по «$appName» отклонён',
                                ),
                                backgroundColor: Colors.redAccent,
                              ),
                            );
                          },
                        ),
                      ],
                    ),

                  const Divider(height: 24),

                  // 2. Выбор категории из полного списка
                  const Text(
                    'Категория приложения:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: allCategories.map((cat) {
                      final catId = cat['id'].toString();
                      final catTitle = cat['title'].toString();
                      return ChoiceChip(
                        label: Text(catTitle),
                        selected: category == catId,
                        onSelected: (selected) {
                          if (selected) {
                            setSheetState(() => category = catId);
                          }
                        },
                      );
                    }).toList(),
                  ),
                  const Divider(height: 24),

                  // 3. Режим доступа
                  const Text(
                    'Постоянные правила доступа:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'inherit',
                        label: Text('Как категория',
                            style: TextStyle(fontSize: 12)),
                      ),
                      ButtonSegment(
                        value: 'custom',
                        label: Text('Своё правило',
                            style: TextStyle(fontSize: 12)),
                      ),
                      ButtonSegment(
                        value: 'always_allowed',
                        label:
                            Text('Разрешить', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                    selected: {ruleMode},
                    onSelectionChanged: (newSet) {
                      setSheetState(() => ruleMode = newSet.first);
                    },
                  ),

                  if (ruleMode == 'custom') ...[
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Заблокировать это приложение',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      activeThumbColor: Colors.red,
                      value: isBlocked,
                      onChanged: (val) => setSheetState(() => isBlocked = val),
                    ),
                    if (!isBlocked) ...[
                      Wrap(
                        spacing: 6,
                        children: List.generate(7, (idx) {
                          final dayNum = idx + 1;
                          return FilterChip(
                            label: Text(_dayLabels[idx]),
                            selected: selectedDays.contains(dayNum),
                            onSelected: (val) {
                              setSheetState(() {
                                if (val) {
                                  selectedDays.add(dayNum);
                                } else if (selectedDays.length > 1) {
                                  selectedDays.remove(dayNum);
                                }
                              });
                            },
                          );
                        }),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Индивидуальные часы доступа'),
                        value: useTimeWindow,
                        onChanged: (val) =>
                            setSheetState(() => useTimeWindow = val),
                      ),
                      if (useTimeWindow)
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay(
                                      hour: startMinutes ~/ 60,
                                      minute: startMinutes % 60,
                                    ),
                                  );
                                  if (picked != null) {
                                    setSheetState(() {
                                      startMinutes =
                                          picked.hour * 60 + picked.minute;
                                    });
                                  }
                                },
                                child: Text(
                                  'С ${_formatMinutesToTime(startMinutes)}',
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () async {
                                  final picked = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay(
                                      hour: endMinutes ~/ 60,
                                      minute: endMinutes % 60,
                                    ),
                                  );
                                  if (picked != null) {
                                    setSheetState(() {
                                      endMinutes =
                                          picked.hour * 60 + picked.minute;
                                    });
                                  }
                                },
                                child: Text(
                                  'До ${_formatMinutesToTime(endMinutes)}',
                                ),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: limitController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'Лимит приложения в день (0 = без лимита)',
                          suffixText: 'мин',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ],

                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () async {
                      final limit =
                          int.tryParse(limitController.text.trim()) ?? 0;
                      final sortedDays = selectedDays.toList()..sort();

                      await _childRef.child('installedApps/$appKey').update({
                        'category': category,
                        'ruleMode': ruleMode,
                        'isBlocked': ruleMode == 'custom' ? isBlocked : false,
                        'allowedDays': sortedDays,
                        'useTimeWindow': useTimeWindow,
                        'startMinutes': startMinutes,
                        'endMinutes': endMinutes,
                        'dailyLimitMinutes': limit < 0 ? 0 : limit,
                      });

                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                    },
                    child: const Text(
                      'Сохранить настройки приложения',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(limitController.dispose);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Приложения: ${widget.childName}'),
        actions: [
          IconButton(
            tooltip: 'Добавить категорию',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: _showAddCategoryDialog,
          ),
        ],
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: _childRef.onValue,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
            return const Center(
              child: Text('Нет данных об устройстве ребёнка.'),
            );
          }

          final childData = Map<dynamic, dynamic>.from(
            snapshot.data!.snapshot.value as Map,
          );

          final webFilterMap = childData['webFilter'] is Map
              ? Map<dynamic, dynamic>.from(childData['webFilter'] as Map)
              : <dynamic, dynamic>{};
          final bool isWebFilterEnabled = webFilterMap['enabled'] != false;
          final String webFilterMode =
              webFilterMap['mode']?.toString() == 'whitelist'
                  ? 'whitelist'
                  : 'blacklist';
          final bool blockAdult = webFilterMap['blockAdult'] != false;

          if (childData['installedApps'] is! Map) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text(
                  'Список приложений ещё не синхронизирован с устройством ребёнка.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 16),
                ),
              ),
            );
          }

          final appsMap = Map<dynamic, dynamic>.from(
            childData['installedApps'] as Map,
          );
          final allCategories =
              AppControlService.getOrderedCategories(childData);
          final validIds =
              allCategories.map((c) => c['id'].toString()).toSet();

          // Автооткрытие шторки запрошенного приложения при переходе из семейного чата
          final targetPkg = widget.initialPackageName;
          if (!_initialAppOpened &&
              targetPkg != null &&
              targetPkg.isNotEmpty) {
            _initialAppOpened = true;
            String? foundKey;
            Map<dynamic, dynamic>? foundData;

            final safeKey = targetPkg.replaceAll('.', '_');
            if (appsMap[safeKey] is Map) {
              foundKey = safeKey;
              foundData = Map<dynamic, dynamic>.from(appsMap[safeKey] as Map);
            } else {
              appsMap.forEach((k, v) {
                if (foundKey == null &&
                    !k.toString().startsWith('_') &&
                    v is Map &&
                    v['packageName']?.toString() == targetPkg) {
                  foundKey = k.toString();
                  foundData = Map<dynamic, dynamic>.from(v);
                }
              });
            }

            if (foundKey != null && foundData != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _showAppEditorSheet(foundKey!, foundData!, allCategories);
                }
              });
            }
          }

          final grouped = <String, List>{};
          for (final id in validIds) {
            grouped[id] = [];
          }

          appsMap.forEach((key, val) {
            if (key.toString().startsWith('_') || val is! Map) return;
            final rawCat = val['category']?.toString() ?? 'other';
            final cat = validIds.contains(rawCat) ? rawCat : 'other';
            grouped[cat]!.add({
              'key': key.toString(),
              'data': Map<dynamic, dynamic>.from(val),
            });
          });

          for (final id in validIds) {
            grouped[id]!.sort(
              (a, b) => (a['data']['appName']?.toString() ?? '')
                  .toLowerCase()
                  .compareTo(
                    (b['data']['appName']?.toString() ?? '').toLowerCase(),
                  ),
            );
          }

          final nowMs = DateTime.now().millisecondsSinceEpoch;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              // КАРТОЧКА ФИЛЬТРАЦИИ ИНТЕРНЕТ-КОНТЕНТА
              Card(
                margin: const EdgeInsets.only(bottom: 14),
                color: isWebFilterEnabled
                    ? Colors.teal.shade50
                    : Colors.grey.shade100,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isWebFilterEnabled
                        ? Colors.teal.shade300
                        : Colors.grey.shade300,
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  leading: Icon(
                    Icons.vpn_lock_rounded,
                    color: isWebFilterEnabled
                        ? Colors.teal.shade700
                        : Colors.grey,
                    size: 30,
                  ),
                  title: const Text(
                    'Фильтрация интернета',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    !isWebFilterEnabled
                        ? 'Фильтр отключён'
                        : webFilterMode == 'whitelist'
                            ? 'Режим: только разрешённые сайты'
                            : (blockAdult
                                ? 'Блокировка 18+, SafeSearch и чёрный список'
                                : 'Активен чёрный список сайтов'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.tune_rounded),
                  onTap: _showWebFilterSheet,
                ),
              ),

              ...allCategories.map((cat) {
                final catId = cat['id'].toString();
                final catTitle = cat['title'].toString();
                final isDefault = cat['isDefault'] == true;
                final catData = cat['data'] is Map
                    ? Map<dynamic, dynamic>.from(cat['data'] as Map)
                    : <dynamic, dynamic>{};
                final catApps = grouped[catId] ?? [];
                final catBlocked = catData['isBlocked'] == true;

                return Card(
                  margin: const EdgeInsets.only(bottom: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ЗАГОЛОВОК КАТЕГОРИИ С КАРАНДАШОМ
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                        decoration: BoxDecoration(
                          color: catBlocked
                              ? Colors.red.shade50
                              : Colors.blue.shade50,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '$catTitle (${catApps.length})',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: catBlocked
                                          ? Colors.red.shade800
                                          : Colors.blue.shade900,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _buildCategorySummary(catData),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: catBlocked
                                          ? Colors.red.shade700
                                          : Colors.blueGrey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Настроить категорию',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _showCategoryEditorSheet(
                                catId,
                                catTitle,
                                isDefault,
                                catData,
                                appsMap,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // СПИСОК ПРИЛОЖЕНИЙ КАТЕГОРИИ
                      if (catApps.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(14),
                          child: Text(
                            'Нет приложений в этой категории',
                            style: TextStyle(fontSize: 13, color: Colors.grey),
                          ),
                        )
                      else
                        ...List.generate(catApps.length, (idx) {
                          final item = catApps[idx];
                          final appKey = item['key'] as String;
                          final appData =
                              item['data'] as Map<dynamic, dynamic>;
                          final appName =
                              appData['appName']?.toString() ?? 'Приложение';
                          final ruleMode =
                              appData['ruleMode']?.toString() ?? 'inherit';
                          final tempUntil = int.tryParse(
                                appData['tempAllowUntil']?.toString() ?? '0',
                              ) ??
                              0;

                          String? badge;
                          Color badgeColor = Colors.blueGrey;
                          if (tempUntil > nowMs) {
                            badge = 'Временный доступ';
                            badgeColor = Colors.green;
                          } else if (ruleMode == 'always_allowed') {
                            badge = 'Всегда разрешено';
                            badgeColor = Colors.green;
                          } else if (ruleMode == 'custom') {
                            badge = appData['isBlocked'] == true
                                ? 'Заблокировано'
                                : 'Своё правило';
                            badgeColor = appData['isBlocked'] == true
                                ? Colors.red
                                : Colors.deepOrange;
                          }

                          return Column(
                            children: [
                              if (idx > 0) const Divider(height: 1),
                              ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.only(
                                  left: 16,
                                  right: 8,
                                ),
                                title: Text(
                                  appName,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                subtitle: badge != null
                                    ? Text(
                                        badge,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: badgeColor,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      )
                                    : null,
                                trailing: IconButton(
                                  tooltip: 'Редактировать приложение',
                                  icon: const Icon(
                                    Icons.edit_outlined,
                                    size: 20,
                                  ),
                                  onPressed: () => _showAppEditorSheet(
                                    appKey,
                                    appData,
                                    allCategories,
                                  ),
                                ),
                              ),
                            ],
                          );
                        }),
                    ],
                  ),
                );
              }),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _showAddCategoryDialog,
                icon: const Icon(Icons.add),
                label: const Text('Добавить новую категорию'),
              ),
            ],
          );
        },
      ),
    );
  }
}