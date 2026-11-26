import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

class FamilyMapWidget extends StatefulWidget {
  const FamilyMapWidget({
    super.key,
    required this.center,
    this.markerPoint,
    this.childMarker,
    this.initialZoom = 15.0,
    this.tileUrlTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    this.fallbackTileUrlTemplate,
    this.userAgentPackageName = 'ru.familypulse.app',
    this.followMarker = true,
    this.circles = const [],
    this.extraMarkers = const [],
    this.showDefaultMarker = true,
    this.onTap,
    this.onTileError,
    this.onMapReady,
  });

  final LatLng center;
  final LatLng? markerPoint;
  final Marker? childMarker;
  final double initialZoom;
  final String tileUrlTemplate;
  final String? fallbackTileUrlTemplate;
  final String userAgentPackageName;
  final bool followMarker;
  final List<CircleMarker> circles;
  final List<Marker> extraMarkers;
  final bool showDefaultMarker;
  final void Function(LatLng point)? onTap;
  final void Function(int errorCount)? onTileError;
  final VoidCallback? onMapReady;

  @override
  State<FamilyMapWidget> createState() => FamilyMapWidgetState();
}

class FamilyMapWidgetState extends State<FamilyMapWidget> {
  final MapController _mapController = MapController();
  int _tileErrorCount = 0;
  bool _useFallbackTiles = false;

  void moveTo(LatLng point, {double? zoom}) {
    try {
      _mapController.move(point, zoom ?? _mapController.camera.zoom);
    } catch (_) {}
  }

  void resetTileErrors() {
    final hadErrors = _tileErrorCount > 0 || _useFallbackTiles;
    if (!hadErrors) return;
    setState(() {
      _tileErrorCount = 0;
      _useFallbackTiles = false;
    });
    widget.onTileError?.call(0);
  }

  @override
  void didUpdateWidget(covariant FamilyMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.tileUrlTemplate != widget.tileUrlTemplate ||
        oldWidget.fallbackTileUrlTemplate != widget.fallbackTileUrlTemplate) {
      _tileErrorCount = 0;
      _useFallbackTiles = false;
    }

    final target = widget.markerPoint ?? widget.center;
    final oldTarget = oldWidget.markerPoint ?? oldWidget.center;
    if (widget.followMarker &&
        (target.latitude != oldTarget.latitude ||
            target.longitude != oldTarget.longitude)) {
      moveTo(target);
    }
  }

  void _handleTileError(TileImage tile, Object error, StackTrace? stackTrace) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _tileErrorCount++;
        if (!_useFallbackTiles &&
            widget.fallbackTileUrlTemplate != null &&
            widget.fallbackTileUrlTemplate!.isNotEmpty &&
            _tileErrorCount >= 3) {
          _useFallbackTiles = true;
        }
      });
      widget.onTileError?.call(_tileErrorCount);
    });
  }

  String get _activeTileUrl {
    if (_useFallbackTiles &&
        widget.fallbackTileUrlTemplate != null &&
        widget.fallbackTileUrlTemplate!.isNotEmpty) {
      return widget.fallbackTileUrlTemplate!;
    }
    return widget.tileUrlTemplate;
  }

  @override
  Widget build(BuildContext context) {
    final effectiveMarker = widget.markerPoint ?? widget.center;
    final markers = <Marker>[
      ...widget.extraMarkers,
      if (widget.showDefaultMarker)
        Marker(
          point: effectiveMarker,
          width: 48,
          height: 48,
          child: const Icon(
            Icons.location_on,
            size: 48,
            color: Color(0xFF1F6F54),
          ),
        ),
      ?widget.childMarker,
    ];

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: widget.center,
        initialZoom: widget.initialZoom,
        onMapReady: widget.onMapReady,
        onTap: widget.onTap == null
            ? null
            : (_, LatLng point) => widget.onTap!(point),
      ),
      children: [
        TileLayer(
          urlTemplate: widget.tileUrlTemplate,
          userAgentPackageName: widget.userAgentPackageName,
          errorTileCallback: _handleTileError,
        ),
        MarkerLayer(
          markers: [
            Marker(
              point: effectiveMarker,
              width: 48,
              height: 48,
              child: const Icon(
                Icons.location_on,
                size: 48,
                color: Color(0xFF1F6F54),
              ),
            ),
          ],
        ),
        // TileLayer(
        //   key: ValueKey(_activeTileUrl),
        //   urlTemplate: _activeTileUrl,
        //   userAgentPackageName: widget.userAgentPackageName,
        //   errorTileCallback: _handleTileError,
        // ),
        // if (widget.circles.isNotEmpty) CircleLayer(circles: widget.circles),
        // if (markers.isNotEmpty) MarkerLayer(markers: markers),
      ],
    );
  }
}