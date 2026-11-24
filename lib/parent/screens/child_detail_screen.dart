import 'package:material_ui/material_ui.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/app_theme.dart';
import '../../core/services/app_control_service.dart';
import '../../core/services/daily_tasks_service.dart';
import '../../core/services/family_chat_service.dart';
import '../../features/widgets/child_goal_card.dart';
import '../../features/widgets/child_location_card.dart';
import '../../features/widgets/user_avatar_widget.dart';
import 'child_apps_screen.dart';
import 'child_location_history_screen.dart';
import 'child_profile_edit_screen.dart';
import 'child_tasks_history_screen.dart';
import 'child_tasks_management_screen.dart';

class ChildDetailScreen extends StatefulWidget {
  final String childId;
  final String childName;

  const ChildDetailScreen({
    super.key,
    required this.childId,
    required this.childName,
  });

  @override
  State<ChildDetailScreen> createState() => _ChildDetailScreenState();
}

class _ChildDetailScreenState extends State<ChildDetailScreen> {
  final MapController _mapController = MapController();
  bool _hasCenteredInitially = false;

  DatabaseReference get _childRef =>
      FirebaseDatabase.instance.ref('children/${widget.childId}');

  @override
  void initState() {
    super.initState();
    DailyTasksService.processDailyTasks(widget.childId);
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Неизвестно';
    final int? millis = int.tryParse(timestamp.toString());
    if (millis == null) return 'Неизвестно';

    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inSeconds < 60) {
      return 'Только что';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes} мин. назад';
    } else {
      final hours = date.hour.toString().padLeft(2, '0');
      final minutes = date.minute.toString().padLeft(2, '0');
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      return '$day.$month в $hours:$minutes';
    }
  }

  String _formatDurationRu(int minutes) {
    if (minutes <= 0) return '0 мин';
    if (minutes < 60) return '$minutes мин';
    final hours = minutes / 60.0;
    return '${hours.toStringAsFixed(1).replaceAll('.', ',')} ч';
  }

  IconData _resolveGeofenceIcon(String iconType) {
    switch (iconType) {
      case 'home':
        return Icons.home_rounded;
      case 'school':
        return Icons.school_rounded;
      case 'sport':
        return Icons.sports_soccer_rounded;
      default:
        return Icons.place_rounded;
    }
  }

  Future<void> _publishParentGoalEvent(
    String Function(String actorName) buildText,
  ) async {
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
        action: {'kind': 'open_tasks', 'childId': widget.childId},
      );
    } catch (e) {
      debugPrint('Ошибка отправки события цели в чат: $e');
    }
  }

  void _openProfileEditScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChildProfileEditScreen(childId: widget.childId),
      ),
    );
  }

  void _openAppsScreen(String currentChildName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChildAppsScreen(
          childId: widget.childId,
          childName: currentChildName,
        ),
      ),
    );
  }

  void _openHistoryScreen({
    required String currentChildName,
    required List<GeofencePoint> geofencesList,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChildLocationHistoryScreen(
          childId: widget.childId,
          childName: currentChildName,
          geofences: geofencesList,
        ),
      ),
    );
  }

  void _openTasksManagementScreen(String currentChildName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChildTasksManagementScreen(
          childId: widget.childId,
          childName: currentChildName,
        ),
      ),
    );
  }

  void _openTasksHistoryScreen(String currentChildName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChildTasksHistoryScreen(
          childId: widget.childId,
          childName: currentChildName,
        ),
      ),
    );
  }

  void _showGeofencesManagerSheet({
    required LatLng? currentChildPos,
    required List<GeofencePoint> existingGeofences,
  }) {
    final titleController = TextEditingController();
    final previewMapController = MapController();
    String selectedIcon = 'home';
    double radiusMeters = 150;
    LatLng selectedPoint =
        currentChildPos ?? const LatLng(56.8389, 60.6057);
    String? editingGeofenceId;

    void resetForm(StateSetter setModalState) {
      setModalState(() {
        editingGeofenceId = null;
        titleController.clear();
        selectedIcon = 'home';
        radiusMeters = 150;
        selectedPoint = currentChildPos ?? const LatLng(56.8389, 60.6057);
      });
      try {
        previewMapController.move(selectedPoint, 15.5);
      } catch (_) {}
    }

    void startEditingZone(GeofencePoint zone, StateSetter setModalState) {
      setModalState(() {
        editingGeofenceId = zone.id;
        titleController.text = zone.title;
        selectedIcon = zone.iconType;
        radiusMeters = zone.radiusMeters.clamp(50.0, 500.0);
        selectedPoint = zone.center;
      });
      try {
        previewMapController.move(zone.center, 16.0);
      } catch (_) {}
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (modalContext, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Назад',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 20,
                        color: Colors.black87,
                      ),
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        editingGeofenceId != null
                            ? 'Редактирование места'
                            : 'Важные точки (геозоны)',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (editingGeofenceId != null)
                      TextButton(
                        onPressed: () => resetForm(setModalState),
                        child: const Text('Отмена'),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  editingGeofenceId != null
                      ? 'Нажмите на карту, чтобы изменить центр выбранной точки'
                      : 'Нажмите на карту, чтобы выбрать центр зоны',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 185,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: FlutterMap(
                      mapController: previewMapController,
                      options: MapOptions(
                        initialCenter: selectedPoint,
                        initialZoom: 15.5,
                        onTap: (tapPosition, point) {
                          setModalState(() {
                            selectedPoint = point;
                          });
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile2.maps.2gis.com/tiles?x={x}&y={y}&z={z}&v=1',
                          userAgentPackageName: 'com.familypulse.app',
                        ),
                        CircleLayer(
                          circles: [
                            CircleMarker(
                              point: selectedPoint,
                              radius: radiusMeters,
                              useRadiusInMeter: true,
                              color: Colors.teal.withValues(alpha: 0.2),
                              borderColor: Colors.teal,
                              borderStrokeWidth: 2,
                            ),
                          ],
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: selectedPoint,
                              width: 40,
                              height: 40,
                              child: const Icon(
                                Icons.location_pin,
                                color: Colors.teal,
                                size: 38,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    labelText: 'Название точки',
                    hintText: 'Например: Дом, Школа №12, Секция',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      avatar: const Icon(Icons.home_rounded, size: 16),
                      label: const Text('Дом'),
                      selected: selectedIcon == 'home',
                      onSelected: (_) {
                        setModalState(() {
                          selectedIcon = 'home';
                          if (titleController.text.isEmpty) {
                            titleController.text = 'Дом';
                          }
                        });
                      },
                    ),
                    ChoiceChip(
                      avatar: const Icon(Icons.school_rounded, size: 16),
                      label: const Text('Школа'),
                      selected: selectedIcon == 'school',
                      onSelected: (_) {
                        setModalState(() {
                          selectedIcon = 'school';
                          if (titleController.text.isEmpty) {
                            titleController.text = 'Школа';
                          }
                        });
                      },
                    ),
                    ChoiceChip(
                      avatar: const Icon(
                        Icons.sports_soccer_rounded,
                        size: 16,
                      ),
                      label: const Text('Кружок'),
                      selected: selectedIcon == 'sport',
                      onSelected: (_) {
                        setModalState(() {
                          selectedIcon = 'sport';
                          if (titleController.text.isEmpty) {
                            titleController.text = 'Кружок';
                          }
                        });
                      },
                    ),
                    ChoiceChip(
                      avatar: const Icon(Icons.place_rounded, size: 16),
                      label: const Text('Другое'),
                      selected: selectedIcon == 'other',
                      onSelected: (_) =>
                          setModalState(() => selectedIcon = 'other'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'Радиус: ${radiusMeters.toInt()} м',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Expanded(
                      child: Slider(
                        min: 50,
                        max: 500,
                        divisions: 9,
                        value: radiusMeters,
                        onChanged: (val) =>
                            setModalState(() => radiusMeters = val),
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () async {
                      final title = titleController.text.trim();
                      if (title.isEmpty) return;

                      if (editingGeofenceId != null) {
                        await _childRef
                            .child('geofences/$editingGeofenceId')
                            .update({
                          'title': title,
                          'iconType': selectedIcon,
                          'latitude': selectedPoint.latitude,
                          'longitude': selectedPoint.longitude,
                          'radius': radiusMeters.toInt(),
                          'updatedAt': ServerValue.timestamp,
                        });
                      } else {
                        await _childRef.child('geofences').push().set({
                          'title': title,
                          'iconType': selectedIcon,
                          'latitude': selectedPoint.latitude,
                          'longitude': selectedPoint.longitude,
                          'radius': radiusMeters.toInt(),
                          'createdAt': ServerValue.timestamp,
                        });
                      }

                      if (sheetContext.mounted) {
                        Navigator.pop(sheetContext);
                      }
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            editingGeofenceId != null
                                ? 'Точка «$title» обновлена'
                                : 'Точка «$title» добавлена на карту',
                          ),
                          backgroundColor: Colors.teal,
                        ),
                      );
                    },
                    icon: Icon(
                      editingGeofenceId != null
                          ? Icons.save_rounded
                          : Icons.add_location_alt_rounded,
                    ),
                    label: Text(
                      editingGeofenceId != null
                          ? 'Сохранить изменения'
                          : 'Сохранить точку',
                    ),
                  ),
                ),
                if (existingGeofences.isNotEmpty) ...[
                  const Divider(height: 24),
                  const Text(
                    'Сохранённые точки (нажмите для редактирования):',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                  const SizedBox(height: 6),
                  ...existingGeofences.map((z) {
                    final bool isBeingEdited = editingGeofenceId == z.id;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      decoration: BoxDecoration(
                        color: isBeingEdited
                            ? Colors.teal.withValues(alpha: 0.1)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 6),
                        leading: Icon(
                          _resolveGeofenceIcon(z.iconType),
                          color: Colors.teal,
                        ),
                        title: Text(
                          z.title,
                          style: TextStyle(
                            fontWeight: isBeingEdited
                                ? FontWeight.bold
                                : FontWeight.w500,
                          ),
                        ),
                        subtitle: Text('Радиус: ${z.radiusMeters.toInt()} м'),
                        onTap: () => startEditingZone(z, setModalState),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Редактировать',
                              icon: const Icon(
                                Icons.edit_outlined,
                                color: Colors.teal,
                                size: 20,
                              ),
                              onPressed: () =>
                                  startEditingZone(z, setModalState),
                            ),
                            IconButton(
                              tooltip: 'Удалить',
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.redAccent,
                                size: 20,
                              ),
                              onPressed: () async {
                                await _childRef
                                    .child('geofences/${z.id}')
                                    .remove();
                                if (sheetContext.mounted) {
                                  Navigator.pop(sheetContext);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      titleController.dispose();
      previewMapController.dispose();
    });
  }

  void _showScreenTimeDetailsSheet(
    String childName,
    Map<dynamic, dynamic> childData,
  ) {
    final categories = AppControlService.getOrderedCategories(childData);
    final titleById = <String, String>{};
    for (final c in categories) {
      titleById[c['id'].toString()] = c['title'].toString();
    }

    final List appsList = [];
    if (childData['installedApps'] is Map) {
      final appsMap = Map<dynamic, dynamic>.from(
        childData['installedApps'] as Map,
      );
      appsMap.forEach((key, val) {
        if (key.toString().startsWith('_') || val is! Map) return;
        final mins =
            int.tryParse(val['timeSpentMinutes']?.toString() ?? '0') ?? 0;
        if (mins > 0) {
          final rawCat = val['category']?.toString() ?? 'other';
          appsList.add({
            'appName': val['appName']?.toString() ?? 'Приложение',
            'category': titleById[rawCat] ?? 'Прочее',
            'minutes': mins,
          });
        }
      });
    }

    appsList.sort(
      (a, b) => (b['minutes'] as int).compareTo(a['minutes'] as int),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Экранное время: $childName',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Подробная статистика использования приложений за сегодня',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const Divider(height: 20),
              Expanded(
                child: appsList.isEmpty
                    ? const Center(
                        child: Text(
                          'Сегодня приложения ещё не использовались',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: appsList.length,
                        separatorBuilder: (context, idx) =>
                            const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final item = appsList[idx];
                          final mins = item['minutes'] as int;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              item['appName'] as String,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            subtitle: Text(
                              item['category'] as String,
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: Text(
                              _formatDurationRu(mins),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParentUsageRow({
    required String label,
    required int minutes,
    required int totalMinutes,
    required Color color,
  }) {
    final double ratio =
        totalMinutes > 0 ? (minutes / totalMinutes).clamp(0.0, 1.0) : 0.0;
    return Row(
      children: [
        SizedBox(
          width: 82,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            _formatDurationRu(minutes),
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
      ],
    );
  }

  void _showEditGoalDialog({
    required String currentChildName,
    required String currentTitle,
    required int currentTarget,
    required int currentPoints,
    required bool isPendingApproval,
  }) {
    final titleController = TextEditingController(text: currentTitle);
    final targetController = TextEditingController(
      text: currentTarget > 0 ? currentTarget.toString() : '5000',
    );
    final pointsController = TextEditingController(
      text: currentPoints.toString(),
    );

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 24,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Row(
          children: [
            const Icon(Icons.emoji_events, color: Colors.amber, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isPendingApproval
                    ? 'Согласование цели'
                    : 'Редактировать цель',
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: InputDecoration(
                  labelText: 'Название цели (награда)',
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
                  labelText: 'Стоимость цели в баллах',
                  suffixText: 'Б',
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
                  labelText: 'Текущий баланс ребёнка',
                  suffixText: 'Б',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
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
              final current =
                  int.tryParse(pointsController.text.trim()) ?? currentPoints;
              if (title.isEmpty || target <= 0) return;

              await _childRef.child('goal').update({
                'title': title,
                'target': target,
                'current': current < 0 ? 0 : current,
                'status': 'active',
                'approvedAt': ServerValue.timestamp,
              });

              await _publishParentGoalEvent(
                (actor) => isPendingApproval
                    ? '🎉 $actor одобрил(а) цель для $currentChildName: «$title» ($target Б)'
                    : '✏️ $actor обновил(а) цель для $currentChildName: «$title» ($target Б)',
              );

              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    isPendingApproval
                        ? 'Цель «$title» одобрена!'
                        : 'Условия цели обновлены',
                  ),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: Text(
              isPendingApproval ? 'Сохранить и принять' : 'Сохранить',
            ),
          ),
        ],
      ),
    ).whenComplete(() {
      titleController.dispose();
      targetController.dispose();
      pointsController.dispose();
    });
  }

  Future<void> _approveGoalDirectly(
    String currentChildName,
    String goalTitle,
    int targetPoints,
  ) async {
    await _childRef.child('goal').update({
      'status': 'active',
      'approvedAt': ServerValue.timestamp,
    });

    final titlePart = goalTitle.isNotEmpty ? ' «$goalTitle»' : '';
    final ptsPart = targetPoints > 0 ? ' ($targetPoints Б)' : '';
    await _publishParentGoalEvent(
      (actor) =>
          '🎉 $actor одобрил(а) цель$titlePart$ptsPart для $currentChildName!',
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Цель ребёнка принята!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _rejectGoal(
    String currentChildName,
    String goalTitle,
    int targetPoints,
  ) async {
    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    if (goalTitle.isNotEmpty) {
      await _childRef.child('taskHistory').push().set({
        'title': goalTitle,
        'points': targetPoints,
        'status': 'failed',
        'isGoal': true,
        'finishedAt': nowMillis,
      });
    }

    await _childRef.child('goal').update({
      'status': 'rejected',
      'rejectedAt': nowMillis,
    });

    final titlePart = goalTitle.isNotEmpty ? ' «$goalTitle»' : '';
    await _publishParentGoalEvent(
      (actor) => '🚫 $actor отклонил(а) цель$titlePart для $currentChildName',
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Цель отклонена — ребёнок сможет предложить новую'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<void> _completeGoalEarly(
    String currentChildName,
    String goalTitle,
    int currentPoints,
    int targetPoints,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('Завершить цель и выдать награду?'),
        content: Text(
          'Цель «$goalTitle» будет отмечена как выполненная (накоплено $currentPoints из $targetPoints Б), а счётчик баллов обнулится для новой цели.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Выдать награду'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final nowMillis = DateTime.now().millisecondsSinceEpoch;
    await _childRef.child('taskHistory').push().set({
      'title': goalTitle,
      'points': targetPoints,
      'status': 'completed',
      'isGoal': true,
      'finishedAt': nowMillis,
    });

    await _childRef.child('goal').update({
      'status': 'completed',
      'current': 0,
      'completedAt': nowMillis,
    });

    await _publishParentGoalEvent(
      (actor) =>
          '🎁 $actor выдал(а) награду за цель «$goalTitle» ($targetPoints Б) для $currentChildName!',
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Награда за цель «$goalTitle» выдана!'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 1. ФИРМЕННЫЙ ФОН
        Positioned.fill(
          child: Image.asset(
            AppTheme.parentBackgroundAsset,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.blueGrey.shade900, Colors.blue.shade900],
                  ),
                ),
              );
            },
          ),
        ),
        Positioned.fill(
          child: Container(color: Colors.black.withValues(alpha: 0.4)),
        ),

        // 2. ОСНОВНОЙ ЭКРАН С ПОДПИСКОЙ НА ПРОФИЛЬ РЕБЁНКА
        StreamBuilder<DatabaseEvent>(
          stream: _childRef.onValue,
          builder: (context, childSnapshot) {
            Map<dynamic, dynamic> childData = {};
            if (childSnapshot.hasData &&
                childSnapshot.data!.snapshot.value != null) {
              childData = Map<dynamic, dynamic>.from(
                childSnapshot.data!.snapshot.value as Map,
              );
            }

            final currentChildName =
                childData['name']?.toString() ?? widget.childName;
            final childAvatarHash = childData['avatarHash']?.toString() ?? '';

            Map<dynamic, dynamic> locData = {};
            if (childData['location'] != null) {
              locData = Map<dynamic, dynamic>.from(
                childData['location'] as Map,
              );
            }

            final double? lat = double.tryParse(
              locData['latitude']?.toString() ?? '',
            );
            final double? lng = double.tryParse(
              locData['longitude']?.toString() ?? '',
            );
            final double accuracy =
                double.tryParse(locData['accuracy']?.toString() ?? '0') ?? 0.0;
            final double speed =
                double.tryParse(locData['speed']?.toString() ?? '0') ?? 0.0;
            final dynamic timestamp = locData['timestamp'];

            final int batteryLevel =
                int.tryParse(locData['batteryLevel']?.toString() ?? '100') ??
                100;
            final bool isCharging = locData['isCharging'] == true;

            final LatLng childPosition =
                (lat != null && lng != null)
                    ? LatLng(lat, lng)
                    : const LatLng(56.8389, 60.6057);

            if (lat != null && lng != null && !_hasCenteredInitially) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _mapController.move(childPosition, 16.0);
                _hasCenteredInitially = true;
              });
            }

            final double speedValueKmh = speed > 0 ? speed * 3.6 : 0.0;
            final speedKmh = speedValueKmh.toStringAsFixed(1);

            // Парсинг геозон (важных точек: Дом, Школа, Кружки)
            final List<GeofencePoint> geofencesList = [];
            if (childData['geofences'] is Map) {
              final rawZones = Map<dynamic, dynamic>.from(
                childData['geofences'] as Map,
              );
              rawZones.forEach((key, val) {
                if (val is Map) {
                  final zLat = double.tryParse(
                    val['latitude']?.toString() ?? '',
                  );
                  final zLng = double.tryParse(
                    val['longitude']?.toString() ?? '',
                  );
                  if (zLat != null && zLng != null) {
                    geofencesList.add(
                      GeofencePoint(
                        id: key.toString(),
                        title: val['title']?.toString() ?? 'Точка',
                        iconType: val['iconType']?.toString() ?? 'other',
                        center: LatLng(zLat, zLng),
                        radiusMeters:
                            double.tryParse(
                              val['radius']?.toString() ?? '150',
                            ) ??
                            150,
                      ),
                    );
                  }
                }
              });
            }

            // Данные цели, задач и запросов для виджета ChildGoalCard
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

            int pendingRequestsCount = 0;
            if (childData['taskRequests'] is Map) {
              final rawReqs = Map<dynamic, dynamic>.from(
                childData['taskRequests'] as Map,
              );
              rawReqs.forEach((key, val) {
                if (val is Map && val['status']?.toString() == 'pending') {
                  pendingRequestsCount++;
                }
              });
            }

            int activeTasksCount = 0;
            int reviewTasksCount = 0;
            if (childData['tasks'] is Map) {
              final rawTasks = Map<dynamic, dynamic>.from(
                childData['tasks'] as Map,
              );
              rawTasks.forEach((key, val) {
                if (val is Map) {
                  final status = val['status']?.toString() ?? 'available';
                  if (status != 'done') {
                    activeTasksCount++;
                  }
                  if (status == 'review') {
                    reviewTasksCount++;
                  }
                }
              });
            }

            final categories = AppControlService.getOrderedCategories(
              childData,
            );
            final catStats = AppControlService.calculateCategoryMinutes(
              childData,
            );
            final totalMins = catStats['total'] ?? 0;
            const paletteColors = [
              Colors.deepPurple,
              Colors.blue,
              Colors.green,
              Colors.orange,
              Colors.teal,
              Colors.pink,
              Colors.indigo,
            ];

            return Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                iconTheme: const IconThemeData(color: Colors.white),
                title: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _openProfileEditScreen,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        UserAvatarWidget(
                          avatarBase64: childAvatarHash,
                          radius: 16,
                          fallbackIcon: Icons.child_care,
                          fallbackBackgroundColor: Colors.purple.shade400,
                          fallbackIconColor: Colors.white,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            currentChildName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.edit_rounded,
                          size: 18,
                          color: Colors.white70,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              body: SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 24.0),
                  children: [
                    // ВИДЖЕТ-ПАНЕЛЬ 1: ГЕОЛОКАЦИЯ С АВАТАРКОЙ, ОБНОВЛЕНИЕМ И ТОЧКАМИ
                    ChildLocationCard(
                      childName: currentChildName,
                      childAvatarBase64: childAvatarHash,
                      lat: lat,
                      lng: lng,
                      accuracy: accuracy,
                      speedKmh: speedValueKmh,
                      formattedTimestamp: _formatTimestamp(timestamp),
                      mapController: _mapController,
                      geofences: geofencesList,
                      onForceRefresh: () async {
                        await _childRef.child('commands').update({
                          'forceLocationAt': ServerValue.timestamp,
                        });
                      },
                      onAddGeofencePressed: () => _showGeofencesManagerSheet(
                        currentChildPos: (lat != null && lng != null)
                            ? childPosition
                            : null,
                        existingGeofences: geofencesList,
                      ),
                      onHistoryPressed: () => _openHistoryScreen(
                        currentChildName: currentChildName,
                        geofencesList: geofencesList,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ВИДЖЕТ-ПАНЕЛЬ 2: ТЕЛЕМЕТРИЯ
                    Card(
                      elevation: 4,
                      color: Colors.white.withValues(alpha: 0.9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 14.0,
                          horizontal: 16.0,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildMetricItem(
                              icon: isCharging
                                  ? Icons.battery_charging_full
                                  : batteryLevel > 20
                                      ? Icons.battery_full
                                      : Icons.battery_alert,
                              iconColor:
                                  batteryLevel > 20 ? Colors.green : Colors.red,
                              label: 'Заряд',
                              value: '$batteryLevel%${isCharging ? ' ⚡' : ''}',
                            ),
                            _buildMetricItem(
                              icon: Icons.speed,
                              iconColor: Colors.blue.shade700,
                              label: 'Скорость',
                              value: '$speedKmh км/ч',
                            ),
                            _buildMetricItem(
                              icon: Icons.gps_fixed,
                              iconColor: Colors.indigo,
                              label: 'Точность',
                              value: accuracy > 0
                                  ? '${accuracy.toStringAsFixed(0)} м'
                                  : '—',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ВИДЖЕТ-ПАНЕЛЬ 3: ЭКРАННОЕ ВРЕМЯ СЕГОДНЯ
                    InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => _showScreenTimeDetailsSheet(
                        currentChildName,
                        childData,
                      ),
                      child: Card(
                        elevation: 4,
                        color: Colors.white.withValues(alpha: 0.92),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.bar_chart_rounded,
                                        color: Colors.indigo,
                                        size: 20,
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        'Экранное время сегодня',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: Colors.black45,
                                    size: 20,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ...List.generate(categories.length, (idx) {
                                final cat = categories[idx];
                                final catId = cat['id'].toString();
                                final catTitle = cat['title'].toString();
                                final mins = catStats[catId] ?? 0;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: _buildParentUsageRow(
                                    label: catTitle,
                                    minutes: mins,
                                    totalMinutes: totalMins,
                                    color: paletteColors[
                                        idx % paletteColors.length],
                                  ),
                                );
                              }),
                              const Divider(height: 14),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Итого:',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  Text(
                                    AppControlService.formatTotalDuration(
                                      totalMins,
                                    ),
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.indigo.shade700,
                                    side: BorderSide(
                                      color: Colors.indigo.shade200,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () =>
                                      _openAppsScreen(currentChildName),
                                  icon: const Icon(
                                    Icons.phonelink_lock_rounded,
                                    size: 18,
                                  ),
                                  label: const Text(
                                    'Настроить экранное время',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // ВИДЖЕТ-ПАНЕЛЬ 4: ЦЕЛИ И ЗАДАНИЯ
                    ChildGoalCard(
                      goalTitle: goalTitle,
                      goalStatus: goalStatus,
                      currentPoints: currentPoints,
                      targetPoints: targetPoints,
                      activeTasksCount: activeTasksCount,
                      pendingActionsCount:
                          reviewTasksCount + pendingRequestsCount,
                      onApproveGoal: () => _approveGoalDirectly(
                        currentChildName,
                        goalTitle,
                        targetPoints,
                      ),
                      onEditGoal: () => _showEditGoalDialog(
                        currentChildName: currentChildName,
                        currentTitle: goalTitle,
                        currentTarget: targetPoints,
                        currentPoints: currentPoints,
                        isPendingApproval: goalStatus == 'pending',
                      ),
                      onRejectGoal: () => _rejectGoal(
                        currentChildName,
                        goalTitle,
                        targetPoints,
                      ),
                      onFinishGoalEarly: () => _completeGoalEarly(
                        currentChildName,
                        goalTitle,
                        currentPoints,
                        targetPoints,
                      ),
                      onOpenTasksPressed: () =>
                          _openTasksManagementScreen(currentChildName),
                      onOpenHistoryPressed: () =>
                          _openTasksHistoryScreen(currentChildName),
                    ),
                    const SizedBox(height: 10),

                    // ВИДЖЕТ-ПАНЕЛЬ 5: СТАТИСТИКА УСТРОЙСТВА
                    Card(
                      elevation: 4,
                      color: Colors.white.withValues(alpha: 0.92),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Статистика устройства',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                            const Divider(),
                            _buildStatRow(
                              icon: Icons.wifi_tethering,
                              color: lat != null ? Colors.green : Colors.orange,
                              title: 'Статус связи',
                              value:
                                  lat != null ? 'В сети' : 'Ожидание сигнала',
                            ),
                            const SizedBox(height: 10),
                            _buildStatRow(
                              icon: Icons.shield_outlined,
                              color: Colors.blue.shade700,
                              title: 'Защита и контроль',
                              value: 'Активны',
                            ),
                            const SizedBox(height: 10),
                            _buildStatRow(
                              icon: Icons.update,
                              color: Colors.blueGrey,
                              title: 'Последний отклик',
                              value: _formatTimestamp(timestamp),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMetricItem({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.black54),
        ),
      ],
    );
  }

  Widget _buildStatRow({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}