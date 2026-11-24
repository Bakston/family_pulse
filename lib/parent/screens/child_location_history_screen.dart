import 'package:material_ui/material_ui.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/services/app_log_service.dart';
import '../../features/widgets/child_location_card.dart';
import '../../features/widgets/map_markers.dart';
import '../../features/widgets/family_calendar_widget.dart';

class _TrackPoint {
  final String id;
  final LatLng position;
  final DateTime startTime;
  final DateTime endTime;
  final double speedKmh;
  final int batteryLevel;
  final String? geofenceTitle;

  const _TrackPoint({
    required this.id,
    required this.position,
    required this.startTime,
    required this.endTime,
    required this.speedKmh,
    required this.batteryLevel,
    this.geofenceTitle,
  });

  int get stayDurationMinutes =>
      endTime.difference(startTime).inMinutes.clamp(0, 1440);
}

class ChildLocationHistoryScreen extends StatefulWidget {
  final String childId;
  final String childName;
  final List<GeofencePoint> geofences;

  const ChildLocationHistoryScreen({
    super.key,
    required this.childId,
    required this.childName,
    this.geofences = const [],
  });

  @override
  State<ChildLocationHistoryScreen> createState() =>
      _ChildLocationHistoryScreenState();
}

class _ChildLocationHistoryScreenState
    extends State<ChildLocationHistoryScreen> {
  final MapController _mapController = MapController();
  DateTime _selectedDate = DateTime.now();

  bool _isLoading = true;
  bool _isMapReady = false;
  List<_TrackPoint> _cleanPoints = [];
  List<LatLng> _polylinePoints = [];
  double _totalDistanceKm = 0.0;

  String? _selectedPointId;
  bool _cleanupDone = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      _loadDayRoute();
      _cleanupOldHistoryInBackground();
    });
  }

  void _fitRouteToCamera() {
    if (!_isMapReady || !mounted || _cleanPoints.isEmpty) return;
    try {
      if (_polylinePoints.length < 2) {
        _mapController.move(_cleanPoints.last.position, 16.0);
        return;
      }

      final bounds = LatLngBounds.fromPoints(_polylinePoints);
      final latSpan = (bounds.north - bounds.south).abs();
      final lngSpan = (bounds.east - bounds.west).abs();

      if (latSpan < 0.0002 && lngSpan < 0.0002) {
        _mapController.move(_cleanPoints.last.position, 16.0);
      } else {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(52),
            maxZoom: 16.5,
          ),
        );
      }
    } catch (_) {}
  }

  String _formatDateKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _formatDateHuman(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    final diffDays = today.difference(target).inDays;

    if (diffDays == 0) return 'Сегодня';
    if (diffDays == 1) return 'Вчера';

    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d.$m.${dt.year}';
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatStayDuration(int mins) {
    if (mins < 2) return '';
    if (mins < 60) return '$mins мин';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '$h ч' : '$h ч $m мин';
  }

  String? _findGeofenceTitle(LatLng pos) {
    const distance = Distance();
    for (final zone in widget.geofences) {
      if (distance.as(LengthUnit.Meter, pos, zone.center) <=
          zone.radiusMeters) {
        return zone.title;
      }
    }
    return null;
  }

  /// Фоновая очистка истории маршрутов старше 14 дней, чтобы база не разрасталась
  Future<void> _cleanupOldHistoryInBackground() async {
    if (_cleanupDone || widget.childId.isEmpty) return;
    _cleanupDone = true;
    try {
      final rootRef = FirebaseDatabase.instance.ref(
        'children/${widget.childId}/locationHistory',
      );
      final snap = await rootRef.get();
      if (!snap.exists || snap.value is! Map) return;

      final cutoff = DateTime.now().subtract(const Duration(days: 14));
      final cutoffKey = _formatDateKey(cutoff);

      final rawDays = Map<dynamic, dynamic>.from(snap.value as Map);
      final updates = <String, dynamic>{};
      rawDays.forEach((key, _) {
        final dayKey = key.toString();
        if (dayKey.compareTo(cutoffKey) < 0) {
          updates[dayKey] = null;
        }
      });

      if (updates.isNotEmpty) {
        await rootRef.update(updates);
      }
    } catch (_) {}
  }

  /// Загрузка маршрута только за выбранный день + удаление GPS-«лучей» и дубликатов стоянки
  Future<void> _loadDayRoute() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _selectedPointId = null;
    });

    final dateKey = _formatDateKey(_selectedDate);
    try {
      final snap = await FirebaseDatabase.instance
          .ref('children/${widget.childId}/locationHistory/$dateKey')
          .get();

      final List<_TrackPoint> rawPoints = [];
      if (snap.exists && snap.value is Map) {
        final rawMap = Map<dynamic, dynamic>.from(snap.value as Map);
        rawMap.forEach((key, val) {
          if (val is Map) {
            final lat = double.tryParse(val['latitude']?.toString() ?? '');
            final lng = double.tryParse(val['longitude']?.toString() ?? '');
            final ts = int.tryParse(val['timestamp']?.toString() ?? '0') ?? 0;
            final acc =
                double.tryParse(val['accuracy']?.toString() ?? '0') ?? 0.0;

            if (lat != null && lng != null && ts > 0 && acc <= 85.0) {
              final rawSpeed =
                  double.tryParse(val['speed']?.toString() ?? '0') ?? 0.0;
              final pos = LatLng(lat, lng);
              final dt = DateTime.fromMillisecondsSinceEpoch(ts);
              rawPoints.add(
                _TrackPoint(
                  id: key.toString(),
                  position: pos,
                  startTime: dt,
                  endTime: dt,
                  speedKmh: rawSpeed > 0 ? rawSpeed * 3.6 : 0.0,
                  batteryLevel:
                      int.tryParse(val['batteryLevel']?.toString() ?? '100') ??
                      100,
                  geofenceTitle:
                      val['geofenceTitle']?.toString() ??
                      _findGeofenceTitle(pos),
                ),
              );
            }
          }
        });
        rawPoints.sort((a, b) => a.startTime.compareTo(b.startTime));
      }

      final noSpikes = _filterGpsSpikes(rawPoints);
      final mergedStops = _mergeDuplicateStops(noSpikes);
      final distKm = _calculateTotalDistanceKm(mergedStops);
      final simplifiedPolyline = _downsamplePolyline(
        mergedStops,
        maxPoints: 220,
      );

      if (!mounted) return;
      setState(() {
        _cleanPoints = mergedStops;
        _polylinePoints = simplifiedPolyline;
        _totalDistanceKm = distKm;
        _isLoading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) => _fitRouteToCamera());
    } catch (_) {
      if (mounted) {
        setState(() {
          _cleanPoints = [];
          _polylinePoints = [];
          _totalDistanceKm = 0.0;
          _isLoading = false;
        });
      }
    }
  }

  List<_TrackPoint> _filterGpsSpikes(List<_TrackPoint> points) {
    if (points.length < 3) return points;
    const distance = Distance();
    final result = <_TrackPoint>[points.first];

    int i = 1;
    while (i < points.length - 1) {
      final a = result.last;
      final b = points[i];
      final c = points[i + 1];

      final distAB = distance.as(LengthUnit.Meter, a.position, b.position);
      final distAC = distance.as(LengthUnit.Meter, a.position, c.position);
      final distBC = distance.as(LengthUnit.Meter, b.position, c.position);

      final dtACSec = c.startTime.difference(a.startTime).inSeconds.abs();
      final dtABSec = b.startTime.difference(a.startTime).inSeconds.abs();

      final bool isClassicRay =
          distAB > 100.0 && distAC <= 60.0 && dtACSec <= 180;
      final bool isTeleport =
          dtABSec > 0 && (distAB / dtABSec) > 35.0 && distBC > 100.0;

      if (isClassicRay || isTeleport) {
        i++;
      } else {
        result.add(b);
        i++;
      }
    }

    result.add(points.last);
    return result;
  }

  List<_TrackPoint> _mergeDuplicateStops(List<_TrackPoint> points) {
    if (points.isEmpty) return [];
    const distance = Distance();
    final merged = <_TrackPoint>[points.first];

    for (int i = 1; i < points.length; i++) {
      final prev = merged.last;
      final curr = points[i];

      final dist = distance.as(LengthUnit.Meter, prev.position, curr.position);
      final bool sameZone =
          prev.geofenceTitle != null &&
          prev.geofenceTitle == curr.geofenceTitle;

      if (dist < 30.0 || sameZone) {
        merged[merged.length - 1] = _TrackPoint(
          id: prev.id,
          position: prev.position,
          startTime: prev.startTime,
          endTime: curr.endTime,
          speedKmh: prev.speedKmh,
          batteryLevel: curr.batteryLevel,
          geofenceTitle: prev.geofenceTitle ?? curr.geofenceTitle,
        );
      } else {
        merged.add(curr);
      }
    }
    return merged;
  }

  List<LatLng> _downsamplePolyline(
    List<_TrackPoint> points, {
    int maxPoints = 220,
  }) {
    if (points.length <= maxPoints) {
      return points.map((p) => p.position).toList();
    }
    final step = points.length / maxPoints;
    final sampled = <LatLng>[];
    for (int i = 0; i < maxPoints - 1; i++) {
      sampled.add(points[(i * step).floor()].position);
    }
    sampled.add(points.last.position);
    return sampled;
  }

  double _calculateTotalDistanceKm(List<_TrackPoint> points) {
    if (points.length < 2) return 0.0;
    const distance = Distance();
    double totalMeters = 0.0;
    for (int i = 1; i < points.length; i++) {
      totalMeters += distance.as(
        LengthUnit.Meter,
        points[i - 1].position,
        points[i].position,
      );
    }
    return totalMeters / 1000.0;
  }

  void _selectDate(DateTime newDate) {
    setState(() {
      _selectedDate = newDate;
    });
    _loadDayRoute();
  }

  Future<void> _pickCustomDate() async {
    final now = DateTime.now();
    final picked = await FamilyCalendarWidget.showPickerDialog(
      context: context,
      initialDate: _selectedDate,
      firstDate: now.subtract(const Duration(days: 14)),
      lastDate: now,
      title: 'Дата маршрута',
    );
    if (picked != null && mounted) {
      _selectDate(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateKey = _formatDateKey(_selectedDate);
    final now = DateTime.now();
    final isToday = _formatDateKey(now) == dateKey;
    final isYesterday =
        _formatDateKey(now.subtract(const Duration(days: 1))) == dateKey;

    final _TrackPoint? highlightedPoint = _selectedPointId == null
        ? null
        : _cleanPoints.where((p) => p.id == _selectedPointId).firstOrNull;

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
              'Маршрут: ${widget.childName}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            Text(
              _formatDateHuman(_selectedDate),
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          if (isToday)
            IconButton(
              tooltip: 'Обновить маршрут',
              icon: const Icon(Icons.refresh_rounded, color: Colors.indigo),
              onPressed: _isLoading ? null : _loadDayRoute,
            ),
          IconButton(
            tooltip: 'Выбрать дату в календаре',
            icon: const Icon(
              Icons.calendar_month_rounded,
              color: Colors.indigo,
            ),
            onPressed: _pickCustomDate,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Сегодня'),
                  selected: isToday,
                  onSelected: (_) => _selectDate(DateTime.now()),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Вчера'),
                  selected: isYesterday,
                  onSelected: (_) => _selectDate(
                    DateTime.now().subtract(const Duration(days: 1)),
                  ),
                ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(Icons.date_range_rounded, size: 16),
                  label: Text(
                    (!isToday && !isYesterday)
                        ? _formatDateHuman(_selectedDate)
                        : 'Другой день',
                  ),
                  onPressed: _pickCustomDate,
                ),
              ],
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      Expanded(
                        flex: 6,
                        child: Stack(
                          children: [
                            FlutterMap(
                              mapController: _mapController,
                              options: MapOptions(
                                initialCenter: _cleanPoints.isNotEmpty
                                    ? _cleanPoints.last.position
                                    : const LatLng(56.8389, 60.6057),
                                initialZoom: 15.0,
                                onMapReady: () {
                                  _isMapReady = true;
                                  _fitRouteToCamera();
                                },
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate: 'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                                  subdomains: const ['a', 'b', 'c', 'd'],
                                  userAgentPackageName: 'com.familypulse.app',
                                  fallbackUrl: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  errorTileCallback: (tile, error, stackTrace) {
                                    AppLogService.error(
                                      'MAP_TILE',
                                      'z=${tile.coordinates.z} x=${tile.coordinates.x} y=${tile.coordinates.y}: $error',
                                      stackTrace,
                                    );
                                  },
                                ),
                                CircleLayer(
                                  circles: widget.geofences
                                      .map(
                                        (z) => CircleMarker(
                                          point: z.center,
                                          radius: z.radiusMeters,
                                          useRadiusInMeter: true,
                                          color: Colors.indigo.withValues(
                                            alpha: 0.1,
                                          ),
                                          borderColor: Colors.indigo.withValues(
                                            alpha: 0.4,
                                          ),
                                          borderStrokeWidth: 1.5,
                                        ),
                                      )
                                      .toList(),
                                ),

                                if (_polylinePoints.length >= 2)
                                  PolylineLayer(
                                    polylines: [
                                      Polyline(
                                        points: _polylinePoints,
                                        strokeWidth: 5.0,
                                        color: Colors.blue.shade700,
                                        borderStrokeWidth: 2.0,
                                        borderColor: Colors.white,
                                      ),
                                    ],
                                  ),

                                MarkerLayer(
                                  markers: [
                                    ...widget.geofences.map(
                                      (z) => Marker(
                                        point: z.center,
                                        width: 84,
                                        height: 52,
                                        alignment: Alignment.topCenter,
                                        child: GeofenceMapMarker(
                                          title: z.title,
                                          iconType: z.iconType,
                                        ),
                                      ),
                                    ),
                                    if (_cleanPoints.isNotEmpty)
                                      Marker(
                                        point: _cleanPoints.first.position,
                                        width: 34,
                                        height: 34,
                                        child: _buildPinBadge(
                                          color: Colors.green,
                                          icon: Icons.play_arrow_rounded,
                                        ),
                                      ),
                                    if (_cleanPoints.length >= 2)
                                      Marker(
                                        point: _cleanPoints.last.position,
                                        width: 36,
                                        height: 36,
                                        child: _buildPinBadge(
                                          color: Colors.redAccent,
                                          icon: Icons.flag_rounded,
                                        ),
                                      ),
                                    if (highlightedPoint != null)
                                      Marker(
                                        point: highlightedPoint.position,
                                        width: 44,
                                        height: 44,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.amber.shade700,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 3,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withValues(
                                                  alpha: 0.3,
                                                ),
                                                blurRadius: 6,
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.person_pin_circle,
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),

                            if (_cleanPoints.isNotEmpty)
                              Positioned(
                                top: 12,
                                left: 12,
                                right: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.94),
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.08,
                                        ),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceAround,
                                    children: [
                                      _buildSummaryStat(
                                        label: 'Пройдено',
                                        value:
                                            '${_totalDistanceKm.toStringAsFixed(1)} км',
                                      ),
                                      _buildSummaryStat(
                                        label: 'Начало',
                                        value: _formatTime(
                                          _cleanPoints.first.startTime,
                                        ),
                                      ),
                                      _buildSummaryStat(
                                        label: 'Крайняя точка',
                                        value: _formatTime(
                                          _cleanPoints.last.endTime,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      Expanded(
                        flex: 4,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(20),
                            ),
                          ),
                          child: _cleanPoints.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24.0),
                                    child: Text(
                                      'За ${_formatDateHuman(_selectedDate).toLowerCase()} записей маршрута нет',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.black54,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    16,
                                    20,
                                  ),
                                  itemCount: _cleanPoints.length,
                                  separatorBuilder: (_, _) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final point =
                                        _cleanPoints[_cleanPoints.length -
                                            1 -
                                            index];
                                    final isSelected =
                                        point.id == _selectedPointId;
                                    final zoneTitle = point.geofenceTitle;

                                    final stayMins = point.stayDurationMinutes;
                                    final stayText = _formatStayDuration(
                                      stayMins,
                                    );
                                    final timeRange = stayMins >= 2
                                        ? '${_formatTime(point.startTime)} – ${_formatTime(point.endTime)}${stayText.isNotEmpty ? ' ($stayText)' : ''}'
                                        : _formatTime(point.startTime);

                                    return ListTile(
                                      selected: isSelected,
                                      selectedTileColor: Colors.blue.withValues(
                                        alpha: 0.08,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      leading: CircleAvatar(
                                        radius: 18,
                                        backgroundColor: zoneTitle != null
                                            ? Colors.teal.shade50
                                            : Colors.blue.shade50,
                                        child: Icon(
                                          zoneTitle != null
                                              ? Icons.place_rounded
                                              : (stayMins >= 5
                                                    ? Icons.pause_circle_filled
                                                    : Icons
                                                          .my_location_rounded),
                                          size: 18,
                                          color: zoneTitle != null
                                              ? Colors.teal
                                              : Colors.blue.shade700,
                                        ),
                                      ),
                                      title: Text(
                                        zoneTitle ??
                                            (stayMins >= 5
                                                ? 'Стоянка • ${point.position.latitude.toStringAsFixed(4)}, ${point.position.longitude.toStringAsFixed(4)}'
                                                : '${point.position.latitude.toStringAsFixed(5)}, ${point.position.longitude.toStringAsFixed(5)}'),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                      subtitle: Text(
                                        '$timeRange • Заряд ${point.batteryLevel}%${point.speedKmh > 3 ? ' • ${point.speedKmh.toStringAsFixed(0)} км/ч' : ''}',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      trailing: const Icon(
                                        Icons.chevron_right_rounded,
                                        color: Colors.black38,
                                      ),
                                      onTap: () {
                                        setState(() {
                                          _selectedPointId = point.id;
                                        });
                                        _mapController.move(
                                          point.position,
                                          16.5,
                                        );
                                      },
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPinBadge({required Color color, required IconData icon}) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }

  Widget _buildSummaryStat({required String label, required String value}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 15,
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
}
