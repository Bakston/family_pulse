import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/app_log_service.dart';
import 'family_map_widget.dart';
import 'map_markers.dart';

class GeofencePoint {
  final String id;
  final String title;
  final String iconType;
  final LatLng center;
  final double radiusMeters;

  const GeofencePoint({
    required this.id,
    required this.title,
    required this.iconType,
    required this.center,
    this.radiusMeters = 150,
  });
}

class ChildLocationCard extends StatefulWidget {
  final String childName;
  final String childAvatarBase64;
  final double? lat;
  final double? lng;
  final double accuracy;
  final double speedKmh;
  final String formattedTimestamp;
  final VoidCallback? onMapReady;
  final List<GeofencePoint> geofences;
  final Future<void> Function() onForceRefresh;
  final VoidCallback onAddGeofencePressed;
  final VoidCallback onHistoryPressed;

  const ChildLocationCard({
    super.key,
    required this.childName,
    required this.childAvatarBase64,
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.speedKmh,
    required this.formattedTimestamp,
    this.onMapReady,
    required this.geofences,
    required this.onForceRefresh,
    required this.onAddGeofencePressed,
    required this.onHistoryPressed,
  });

  @override
  State<ChildLocationCard> createState() => _ChildLocationCardState();
}

class _ChildLocationCardState extends State<ChildLocationCard>
    with SingleTickerProviderStateMixin {
  final GlobalKey<FamilyMapWidgetState> _mapKey =
      GlobalKey<FamilyMapWidgetState>();
  late final AnimationController _spinController;
  bool _isRefreshing = false;
  String? _activeZoneTitle;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _recomputeActiveGeofence();
  }

  @override
  void didUpdateWidget(covariant ChildLocationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lat != widget.lat ||
        oldWidget.lng != widget.lng ||
        !_areGeofencesEqual(oldWidget.geofences, widget.geofences)) {
      _recomputeActiveGeofence();
    }
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  bool _areGeofencesEqual(List<GeofencePoint> a, List<GeofencePoint> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].title != b[i].title ||
          a[i].iconType != b[i].iconType ||
          a[i].radiusMeters != b[i].radiusMeters ||
          a[i].center.latitude != b[i].center.latitude ||
          a[i].center.longitude != b[i].center.longitude) {
        return false;
      }
    }
    return true;
  }

  void _recomputeActiveGeofence() {
    if (widget.lat == null || widget.lng == null) {
      _activeZoneTitle = null;
      return;
    }
    final childPos = LatLng(widget.lat!, widget.lng!);
    _activeZoneTitle = _detectCurrentGeofence(childPos);
  }

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);
    _spinController.repeat();

    try {
      await widget.onForceRefresh();
    } finally {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        _spinController.stop();
        _spinController.reset();
        setState(() => _isRefreshing = false);
      }
    }
  }

  String? _detectCurrentGeofence(LatLng childPos) {
    const distance = Distance();
    for (final zone in widget.geofences) {
      final meters = distance.as(LengthUnit.Meter, childPos, zone.center);
      if (meters <= zone.radiusMeters) {
        return zone.title;
      }
    }
    return null;
  }

  Future<void> _openExternalRoute(LatLng target) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${target.latitude},${target.longitude}',
    );
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e, st) {
      AppLogService.error('MAP_ROUTE', 'Ошибка открытия маршрута: $e', st);
    }
  }

  void _centerOnChild(LatLng childPosition) {
    try {
      _mapKey.currentState?.moveTo(childPosition, zoom: 16.5);
    } catch (e, st) {
      AppLogService.error('MAP_CTRL', 'Ошибка центрирования карты: $e', st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasCoords = widget.lat != null && widget.lng != null;
    final LatLng childPosition = hasCoords
        ? LatLng(widget.lat!, widget.lng!)
        : const LatLng(56.8389, 60.6057);

    final String? activeZoneTitle = _activeZoneTitle;

    return Card(
      elevation: 6,
      color: Colors.white.withValues(alpha: 0.94),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color:
                        (activeZoneTitle != null ? Colors.green : Colors.blue)
                            .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    activeZoneTitle != null
                        ? Icons.verified_user_rounded
                        : Icons.location_on_rounded,
                    color: activeZoneTitle != null
                        ? Colors.green.shade700
                        : Colors.blue.shade700,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        activeZoneTitle != null
                            ? 'В зоне: $activeZoneTitle'
                            : (hasCoords
                                  ? 'Геолокация активна'
                                  : 'Ожидание сигнала GPS'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _isRefreshing
                            ? 'Запрашиваем свежие координаты...'
                            : 'Обновлено: ${widget.formattedTimestamp}',
                        style: TextStyle(
                          fontSize: 12,
                          color: _isRefreshing
                              ? Colors.green.shade700
                              : Colors.black54,
                          fontWeight: _isRefreshing
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: 'Обновить геопозицию сейчас',
                  child: Material(
                    color: Colors.blue.shade50,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _handleRefresh,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: RotationTransition(
                          turns: _spinController,
                          child: Icon(
                            Icons.refresh_rounded,
                            color: Colors.blue.shade700,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 250,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  children: [
                    !hasCoords
                        ? Container(
                            color: Colors.grey.shade100,
                            child: const Center(
                              child: Padding(
                                padding: EdgeInsets.all(20.0),
                                child: Text(
                                  'Ожидание геопозиции от устройства ребёнка...',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.black54,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : FamilyMapWidget(
                            key: _mapKey,
                            center: childPosition,
                            markerPoint: childPosition,
                            initialZoom: 16.0,
                            followMarker: true,
                            showDefaultMarker: false,
                            userAgentPackageName: 'com.familypulse.app',
                            tileUrlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            onMapReady: widget.onMapReady,
                            onTileError: (errorCount) {
                              AppLogService.error(
                                'MAP_TILE',
                                'Ошибок загрузки тайлов: $errorCount',
                                null,
                              );
                            },
                            circles: [
                              ...widget.geofences.map(
                                (zone) => CircleMarker(
                                  point: zone.center,
                                  radius: zone.radiusMeters,
                                  useRadiusInMeter: true,
                                  color: Colors.indigo.withValues(alpha: 0.12),
                                  borderColor: Colors.indigo.withValues(
                                    alpha: 0.5,
                                  ),
                                  borderStrokeWidth: 1.5,
                                ),
                              ),
                              if (widget.accuracy > 0)
                                CircleMarker(
                                  point: childPosition,
                                  radius: widget.accuracy,
                                  useRadiusInMeter: true,
                                  color: const Color(
                                    0xFF2ECC71,
                                  ).withValues(alpha: 0.18),
                                  borderColor: const Color(0xFF2ECC71),
                                  borderStrokeWidth: 1.5,
                                ),
                            ],
                            extraMarkers: [
                              ...widget.geofences.map(
                                (zone) => Marker(
                                  point: zone.center,
                                  width: 90,
                                  height: 56,
                                  alignment: Alignment.topCenter,
                                  child: GeofenceMapMarker(
                                    title: zone.title,
                                    iconType: zone.iconType,
                                  ),
                                ),
                              ),
                            ],
                            childMarker: Marker(
                              point: childPosition,
                              width: 110,
                              height: 82,
                              alignment: Alignment.topCenter,
                              child: ChildAvatarMapMarker(
                                avatarBase64: widget.childAvatarBase64,
                                childName: widget.childName,
                                isOnline: true,
                                isMoving: widget.speedKmh > 12.0,
                              ),
                            ),
                          ),
                    if (hasCoords)
                      Positioned(
                        right: 10,
                        bottom: 10,
                        child: FloatingActionButton.small(
                          heroTag: 'center_child_map',
                          backgroundColor: Colors.white,
                          onPressed: () => _centerOnChild(childPosition),
                          child: const Icon(
                            Icons.my_location_rounded,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _CardActionChip(
                    icon: Icons.directions_rounded,
                    label: 'Маршрут',
                    color: Colors.blue.shade700,
                    onTap: hasCoords
                        ? () => _openExternalRoute(childPosition)
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CardActionChip(
                    icon: Icons.add_location_alt_rounded,
                    label: 'Места (${widget.geofences.length})',
                    color: Colors.teal.shade700,
                    onTap: widget.onAddGeofencePressed,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _CardActionChip(
                    icon: Icons.history_rounded,
                    label: 'История',
                    color: Colors.indigo.shade700,
                    onTap: widget.onHistoryPressed,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CardActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _CardActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = onTap == null ? Colors.grey : color;
    return Material(
      color: effectiveColor.withValues(alpha: 0.09),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: effectiveColor),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: effectiveColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}