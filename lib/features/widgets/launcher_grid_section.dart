import 'dart:typed_data';
import 'package:device_apps_ng/device_apps_ng.dart';
import 'package:material_ui/material_ui.dart';
import '../../child/screens/launcher_layout.dart';
import '../../core/app_theme.dart';

class LauncherGridSection extends StatefulWidget {
  final List<String?> gridSlots;
  final List<Application> allowedApps;
  final void Function(String packageName) onLaunchApp;
  final void Function(String packageName) onRemoveApp;
  final void Function(int fromIndex, int toIndex) onMoveAppToSlot;
  final void Function(int dockIndex, int gridIndex) onMoveDockAppToGrid;

  const LauncherGridSection({
    super.key,
    required this.gridSlots,
    required this.allowedApps,
    required this.onLaunchApp,
    required this.onRemoveApp,
    required this.onMoveAppToSlot,
    required this.onMoveDockAppToGrid,
  });

  @override
  State<LauncherGridSection> createState() => _LauncherGridSectionState();
}

class _LauncherGridSectionState extends State<LauncherGridSection> {
  final Map<int, GlobalKey> _slotKeys = {};
  OverlayEntry? _popupEntry;
  int? _popupSlotIndex;
  Offset? _dragStartPosition;
  bool _hasMovedDuringDrag = false;

  @override
  void dispose() {
    _dismissPopup();
    super.dispose();
  }

  GlobalKey _keyForSlot(int index) {
    return _slotKeys.putIfAbsent(index, () => GlobalKey());
  }

  Application? _findApp(String? packageName) {
    if (packageName == null || packageName.isEmpty) return null;
    for (final app in widget.allowedApps) {
      if (app.packageName == packageName) {
        return app;
      }
    }
    return null;
  }

  void _dismissPopup() {
    _popupEntry?.remove();
    _popupEntry = null;
    _popupSlotIndex = null;
  }

  void _showIconPopupMenu(int slotIndex, Application app) {
    _dismissPopup();
    final slotContext = _keyForSlot(slotIndex).currentContext;
    if (slotContext == null) return;

    final renderBox = slotContext.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final overlay = Overlay.of(context);
    final screenSize = MediaQuery.of(context).size;
    final topLeft = renderBox.localToGlobal(Offset.zero);
    final tileSize = renderBox.size;
    final anchorCenterX = topLeft.dx + tileSize.width / 2;

    const double menuWidth = 172.0;
    const double menuHeight = 52.0;
    const double arrowHeight = 8.0;
    const double screenPadding = 12.0;

    final double left = (anchorCenterX - menuWidth / 2).clamp(
      screenPadding,
      screenSize.width - menuWidth - screenPadding,
    );

    final bool showBelow = topLeft.dy < (menuHeight + arrowHeight + 48);
    final double top = showBelow
        ? (topLeft.dy + tileSize.height + 2)
        : (topLeft.dy - menuHeight - arrowHeight - 2);

    final double arrowOffsetX = (anchorCenterX - left - 8).clamp(
      18.0,
      menuWidth - 34.0,
    );

    _popupSlotIndex = slotIndex;
    _popupEntry = OverlayEntry(
      builder: (overlayContext) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _dismissPopup,
                onPanStart: (_) => _dismissPopup(),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: menuWidth,
              child: Material(
                color: Colors.transparent,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showBelow)
                      Padding(
                        padding: EdgeInsets.only(left: arrowOffsetX),
                        child: CustomPaint(
                          size: const Size(16, arrowHeight),
                          painter: _TrianglePainter(pointUp: true),
                        ),
                      ),
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          onTap: () {
                            _dismissPopup();
                            widget.onRemoveApp(app.packageName);
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.remove_rounded,
                                  size: 22,
                                  color: Color(0xFF7A7E87),
                                ),
                                SizedBox(width: 14),
                                Text(
                                  'Убрать',
                                  style: TextStyle(
                                    fontFamily: AppTheme.fontFamily,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF181A1F),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (!showBelow)
                      Padding(
                        padding: EdgeInsets.only(left: arrowOffsetX),
                        child: CustomPaint(
                          size: const Size(16, arrowHeight),
                          painter: _TrianglePainter(pointUp: false),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );

    overlay.insert(_popupEntry!);
  }

  @override
  Widget build(BuildContext context) {
    final slots = List<String?>.filled(
      LauncherLayoutState.totalGridSlots,
      null,
    );
    for (int i = 0; i < widget.gridSlots.length && i < slots.length; i++) {
      slots[i] = widget.gridSlots[i];
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const int crossAxisCount = 4;
        const int rowCount = 5;
        const double horizontalPadding = 12.0;
        const double verticalPadding = 8.0;
        const double mainAxisSpacing = 10.0;
        const double crossAxisSpacing = 8.0;

        final availableWidth = constraints.maxWidth -
            horizontalPadding * 2 -
            crossAxisSpacing * (crossAxisCount - 1);
        final availableHeight = constraints.maxHeight -
            verticalPadding * 2 -
            mainAxisSpacing * (rowCount - 1);

        final itemWidth = (availableWidth / crossAxisCount).clamp(48.0, 200.0);
        final itemHeight = (availableHeight / rowCount).clamp(64.0, 200.0);
        final aspectRatio = itemWidth / itemHeight;

        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: mainAxisSpacing,
            crossAxisSpacing: crossAxisSpacing,
            childAspectRatio: aspectRatio,
          ),
          itemCount: slots.length,
          itemBuilder: (context, slotIndex) {
            final app = _findApp(slots[slotIndex]);

            return DragTarget<LauncherDragPayload>(
              onWillAcceptWithDetails: (details) {
                final payload = details.data;
                if (!payload.fromDock && payload.index == slotIndex) {
                  return false;
                }
                if (payload.fromDock &&
                    (payload.packageName == null ||
                        payload.packageName!.isEmpty)) {
                  return false;
                }
                return true;
              },
              onAcceptWithDetails: (details) {
                _dismissPopup();
                final payload = details.data;
                if (payload.fromDock) {
                  widget.onMoveDockAppToGrid(payload.index, slotIndex);
                } else {
                  widget.onMoveAppToSlot(payload.index, slotIndex);
                }
              },
              builder: (context, candidateData, rejectedData) {
                final isDropTarget = candidateData.isNotEmpty;

                if (app == null) {
                  return Container(
                    key: _keyForSlot(slotIndex),
                    decoration: isDropTarget
                        ? BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.65),
                              width: 1.5,
                            ),
                          )
                        : null,
                  );
                }

                final iconWidget = _AppShortcutTile(
                  app: app,
                  onTap: () {
                    if (_popupSlotIndex != null) {
                      _dismissPopup();
                      return;
                    }
                    widget.onLaunchApp(app.packageName);
                  },
                );

                return LongPressDraggable<LauncherDragPayload>(
                  data: LauncherDragPayload(
                    fromDock: false,
                    index: slotIndex,
                    packageName: app.packageName,
                  ),
                  hapticFeedbackOnStart: true,
                  onDragStarted: () {
                    _dragStartPosition = null;
                    _hasMovedDuringDrag = false;
                    _showIconPopupMenu(slotIndex, app);
                  },
                  onDragUpdate: (details) {
                    _dragStartPosition ??= details.globalPosition;
                    if (!_hasMovedDuringDrag &&
                        (details.globalPosition - _dragStartPosition!)
                                .distance >
                            12.0) {
                      _hasMovedDuringDrag = true;
                      _dismissPopup();
                    }
                  },
                  onDragEnd: (_) {
                    if (_hasMovedDuringDrag) {
                      _dismissPopup();
                    }
                    _dragStartPosition = null;
                    _hasMovedDuringDrag = false;
                  },
                  onDraggableCanceled: (_, _) {
                    if (_hasMovedDuringDrag) {
                      _dismissPopup();
                    }
                    _dragStartPosition = null;
                    _hasMovedDuringDrag = false;
                  },
                  feedback: Material(
                    color: Colors.transparent,
                    child: Transform.scale(
                      scale: 1.08,
                      child: SizedBox(
                        width: itemWidth,
                        height: itemHeight,
                        child: _AppShortcutVisual(app: app),
                      ),
                    ),
                  ),
                  childWhenDragging: Opacity(
                    opacity: _hasMovedDuringDrag ? 0.25 : 1.0,
                    child: Container(
                      key: _keyForSlot(slotIndex),
                      child: iconWidget,
                    ),
                  ),
                  child: Container(
                    key: _keyForSlot(slotIndex),
                    decoration: isDropTarget
                        ? BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.65),
                              width: 1.5,
                            ),
                          )
                        : null,
                    child: iconWidget,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _AppShortcutTile extends StatelessWidget {
  final Application app;
  final VoidCallback onTap;

  const _AppShortcutTile({
    required this.app,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: _AppShortcutVisual(app: app),
    );
  }
}

class _AppShortcutVisual extends StatelessWidget {
  final Application app;

  const _AppShortcutVisual({required this.app});

  @override
  Widget build(BuildContext context) {
    final Uint8List? iconBytes =
        app is ApplicationWithIcon ? (app as ApplicationWithIcon).icon : null;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 52,
          height: 52,
          child: iconBytes != null
              ? Image.memory(
                  iconBytes,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                )
              : const Icon(
                  Icons.apps_rounded,
                  size: 32,
                  color: Colors.white,
                ),
        ),
        const SizedBox(height: 5),
        Text(
          app.appName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.white,
            shadows: [
              Shadow(
                color: Color(0xB3000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrianglePainter extends CustomPainter {
  final bool pointUp;

  const _TrianglePainter({required this.pointUp});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final path = Path();
    if (pointUp) {
      path.moveTo(0, size.height);
      path.lineTo(size.width / 2, 0);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, 0);
      path.lineTo(size.width / 2, size.height);
      path.lineTo(size.width, 0);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TrianglePainter oldDelegate) =>
      oldDelegate.pointUp != pointUp;
}