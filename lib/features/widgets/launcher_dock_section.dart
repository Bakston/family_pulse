import 'dart:typed_data';
import 'package:device_apps_ng/device_apps_ng.dart';
import 'package:material_ui/material_ui.dart';
import '../../child/screens/launcher_layout.dart';
import '../../core/app_theme.dart';

class LauncherDockSection extends StatefulWidget {
  final List<LauncherDockSlot> dockSlots;
  final List<Application> allowedApps;
  final Uint8List? dialerIconBytes;
  final VoidCallback onOpenDialer;
  final void Function(String packageName) onLaunchApp;
  final void Function(List<LauncherDockSlot> updatedSlots) onDockChanged;
  final void Function(int fromIndex, int toIndex) onMoveDockSlot;
  final void Function(int gridIndex, {int? dockIndex}) onMoveGridAppToDock;

  const LauncherDockSection({
    super.key,
    required this.dockSlots,
    required this.allowedApps,
    required this.dialerIconBytes,
    required this.onOpenDialer,
    required this.onLaunchApp,
    required this.onDockChanged,
    required this.onMoveDockSlot,
    required this.onMoveGridAppToDock,
  });

  @override
  State<LauncherDockSection> createState() => _LauncherDockSectionState();
}

class _LauncherDockSectionState extends State<LauncherDockSection> {
  final Map<int, GlobalKey> _dockKeys = {};
  OverlayEntry? _popupEntry;
  int? _popupSlotIndex;
  Offset? _dragStartPosition;
  bool _hasMovedDuringDrag = false;

  @override
  void dispose() {
    _dismissPopup();
    super.dispose();
  }

  GlobalKey _keyForDockSlot(int index) {
    return _dockKeys.putIfAbsent(index, () => GlobalKey());
  }

  void _dismissPopup() {
    _popupEntry?.remove();
    _popupEntry = null;
    _popupSlotIndex = null;
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

  Application? _findByKeywords(
    List<String> packageKeywords,
    List<String> nameKeywords, {
    List<String> excludeNameKeywords = const [],
  }) {
    bool isExcluded(Application app) {
      final lowerName = app.appName.toLowerCase();
      for (final ex in excludeNameKeywords) {
        if (lowerName == ex || lowerName.contains(ex)) {
          return true;
        }
      }
      return false;
    }

    for (final kw in nameKeywords) {
      for (final app in widget.allowedApps) {
        if (isExcluded(app)) continue;
        if (app.appName.toLowerCase() == kw) {
          return app;
        }
      }
    }

    for (final kw in packageKeywords) {
      for (final app in widget.allowedApps) {
        if (isExcluded(app)) continue;
        if (app.packageName.toLowerCase().contains(kw)) {
          return app;
        }
      }
    }

    for (final kw in nameKeywords) {
      for (final app in widget.allowedApps) {
        if (isExcluded(app)) continue;
        if (app.appName.toLowerCase().contains(kw)) {
          return app;
        }
      }
    }
    return null;
  }

  Application? _resolveSystemSlotApp(LauncherDockSlot slot) {
    if (slot.packageName != null && slot.packageName!.isNotEmpty) {
      final explicit = _findApp(slot.packageName);
      if (explicit != null) return explicit;
    }

    switch (slot.type) {
      case DockSlotType.messages:
        return _findByKeywords(
          const ['messaging', 'mms', 'sms', 'messages'],
          const ['сообщения', 'смс', 'messages'],
        );
      case DockSlotType.camera:
        return _findByKeywords(
          const ['camera', 'opencamera'],
          const ['камера', 'фотоаппарат', 'camera'],
        );
      case DockSlotType.dialer:
        return _findByKeywords(
          const ['dialer', 'telecom', 'incallui', 'phone'],
          const ['телефон', 'вызовы', 'звонки', 'phone'],
          excludeNameKeywords: const ['контакты', 'contacts'],
        );
      case DockSlotType.gallery:
        return _findByKeywords(
          const ['gallery', 'photos', 'album', 'mediatek.gallery'],
          const ['галерея', 'фото', 'альбомы', 'gallery', 'photos'],
        );
      case DockSlotType.app:
      case DockSlotType.appDrawer:
        return null;
    }
  }

  void _pickAppForDock({int? replaceIndex}) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1C1F26) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.65,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  replaceIndex != null
                      ? 'Заменить ярлык в доке'
                      : 'Добавить ярлык в док',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF181A1F),
                  ),
                ),
              ),
              Expanded(
                child: widget.allowedApps.isEmpty
                    ? Center(
                        child: Text(
                          'Нет доступных приложений',
                          style: TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: widget.allowedApps.length,
                        itemBuilder: (context, index) {
                          final app = widget.allowedApps[index];
                          final Uint8List? itemIconBytes =
                              app is ApplicationWithIcon
                                  ? app.icon
                                  : null;
                          return ListTile(
                            leading: SizedBox(
                              width: 36,
                              height: 36,
                              child: itemIconBytes != null
                                  ? Image.memory(
                                      itemIconBytes,
                                      fit: BoxFit.contain,
                                      gaplessPlayback: true,
                                    )
                                  : const Icon(Icons.apps_rounded),
                            ),
                            title: Text(
                              app.appName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: AppTheme.fontFamily,
                                color: isDark
                                    ? Colors.white
                                    : const Color(0xFF181A1F),
                              ),
                            ),
                            onTap: () {
                              final nextSlots = List<LauncherDockSlot>.from(
                                widget.dockSlots,
                              );
                              final newSlot = LauncherDockSlot(
                                type: DockSlotType.app,
                                packageName: app.packageName,
                              );
                              if (replaceIndex != null &&
                                  replaceIndex >= 0 &&
                                  replaceIndex < nextSlots.length) {
                                nextSlots[replaceIndex] = newSlot;
                              } else if (nextSlots.length <
                                  LauncherLayoutState.maxDockSlots) {
                                nextSlots.add(newSlot);
                              }
                              Navigator.pop(sheetContext);
                              widget.onDockChanged(nextSlots);
                            },
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

  void _showDockPopupMenu(int slotIndex, LauncherDockSlot slot) {
    _dismissPopup();
    final slotContext = _keyForDockSlot(slotIndex).currentContext;
    if (slotContext == null) return;

    final renderBox = slotContext.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final overlay = Overlay.of(context);
    final screenSize = MediaQuery.of(context).size;
    final topLeft = renderBox.localToGlobal(Offset.zero);
    final tileSize = renderBox.size;
    final anchorCenterX = topLeft.dx + tileSize.width / 2;

    final bool canAddMore =
        widget.dockSlots.length < LauncherLayoutState.maxDockSlots;
    final bool canRemove = widget.dockSlots.length > 1;
    final int itemCount = 1 + (canAddMore ? 1 : 0) + (canRemove ? 1 : 0);

    const double menuWidth = 198.0;
    final double menuHeight = itemCount * 50.0 + (itemCount - 1) * 1.0;
    const double arrowHeight = 8.0;
    const double screenPadding = 12.0;

    final double left = (anchorCenterX - menuWidth / 2).clamp(
      screenPadding,
      screenSize.width - menuWidth - screenPadding,
    );
    final double top = topLeft.dy - menuHeight - arrowHeight - 6;
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
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              onTap: () {
                                _dismissPopup();
                                _pickAppForDock(replaceIndex: slotIndex);
                              },
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 13,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.swap_horiz_rounded,
                                      size: 21,
                                      color: Color(0xFF7A7E87),
                                    ),
                                    SizedBox(width: 12),
                                    Text(
                                      'Заменить',
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
                            if (canAddMore) ...[
                              Divider(
                                height: 1,
                                thickness: 1,
                                color: Colors.black.withValues(alpha: 0.06),
                              ),
                              InkWell(
                                onTap: () {
                                  _dismissPopup();
                                  _pickAppForDock();
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 13,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.add_rounded,
                                        size: 21,
                                        color: Color(0xFF7A7E87),
                                      ),
                                      SizedBox(width: 12),
                                      Text(
                                        'Добавить в док',
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
                            ],
                            if (canRemove) ...[
                              Divider(
                                height: 1,
                                thickness: 1,
                                color: Colors.black.withValues(alpha: 0.06),
                              ),
                              InkWell(
                                onTap: () {
                                  _dismissPopup();
                                  final nextSlots = List<LauncherDockSlot>.from(
                                    widget.dockSlots,
                                  )..removeAt(slotIndex);
                                  widget.onDockChanged(nextSlots);
                                },
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 13,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.remove_rounded,
                                        size: 21,
                                        color: Color(0xFF7A7E87),
                                      ),
                                      SizedBox(width: 12),
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
                            ],
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.only(left: arrowOffsetX),
                      child: CustomPaint(
                        size: const Size(16, arrowHeight),
                        painter: _DockTrianglePainter(),
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

  Widget _buildAppIconWidget(
    LauncherDockSlot slot,
    Application? app, {
    required IconData fallbackIcon,
    required Color fallbackBg,
  }) {
    if (slot.type == DockSlotType.dialer &&
        slot.packageName == null &&
        widget.dialerIconBytes != null &&
        widget.dialerIconBytes!.isNotEmpty) {
      return SizedBox(
        width: 52,
        height: 52,
        child: Image.memory(
          widget.dialerIconBytes!,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        ),
      );
    }

    final Uint8List? iconBytes =
        app is ApplicationWithIcon ? app.icon : null;

    if (iconBytes != null) {
      return SizedBox(
        width: 52,
        height: 52,
        child: Image.memory(
          iconBytes,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        ),
      );
    }

    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fallbackBg,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Icon(
        fallbackIcon,
        size: 26,
        color: Colors.white,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final slots = widget.dockSlots;

    return DragTarget<LauncherDragPayload>(
      onWillAcceptWithDetails: (details) {
        final payload = details.data;
        if (!payload.fromDock &&
            slots.length < LauncherLayoutState.maxDockSlots) {
          return true;
        }
        return false;
      },
      onAcceptWithDetails: (details) {
        _dismissPopup();
        widget.onMoveGridAppToDock(details.data.index);
      },
      builder: (context, outerCandidate, _) {
        final isOuterDropTarget = outerCandidate.isNotEmpty;

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(10, 4, 10, 14),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: isOuterDropTarget
              ? BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.55),
                    width: 1.5,
                  ),
                )
              : null,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(slots.length, (index) {
              final slot = slots[index];
              final resolvedApp = _resolveSystemSlotApp(slot);

              IconData fallbackIcon;
              Color fallbackBg;

              switch (slot.type) {
                case DockSlotType.messages:
                  fallbackIcon = Icons.sms_rounded;
                  fallbackBg = const Color(0xFF2563EB);
                  break;
                case DockSlotType.camera:
                  fallbackIcon = Icons.photo_camera_rounded;
                  fallbackBg = const Color(0xFF374151);
                  break;
                case DockSlotType.dialer:
                  fallbackIcon = Icons.call_rounded;
                  fallbackBg = const Color(0xFF16A34A);
                  break;
                case DockSlotType.gallery:
                  fallbackIcon = Icons.photo_library_rounded;
                  fallbackBg = const Color(0xFFEA580C);
                  break;
                case DockSlotType.app:
                case DockSlotType.appDrawer:
                  fallbackIcon = Icons.add_rounded;
                  fallbackBg = Colors.white.withValues(alpha: 0.22);
                  break;
              }

              final iconWidget = _buildAppIconWidget(
                slot,
                resolvedApp,
                fallbackIcon: fallbackIcon,
                fallbackBg: fallbackBg,
              );

              return Expanded(
                child: DragTarget<LauncherDragPayload>(
                  onWillAcceptWithDetails: (details) {
                    final payload = details.data;
                    if (payload.fromDock && payload.index == index) {
                      return false;
                    }
                    return true;
                  },
                  onAcceptWithDetails: (details) {
                    _dismissPopup();
                    final payload = details.data;
                    if (payload.fromDock) {
                      widget.onMoveDockSlot(payload.index, index);
                    } else {
                      widget.onMoveGridAppToDock(
                        payload.index,
                        dockIndex: index,
                      );
                    }
                  },
                  builder: (context, slotCandidate, _) {
                    final isSlotTarget = slotCandidate.isNotEmpty;

                    final tile = GestureDetector(
                      key: _keyForDockSlot(index),
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (_popupSlotIndex != null) {
                          _dismissPopup();
                          return;
                        }
                        if (slot.type == DockSlotType.dialer &&
                            slot.packageName == null) {
                          if (resolvedApp != null) {
                            widget.onLaunchApp(resolvedApp.packageName);
                          } else {
                            widget.onOpenDialer();
                          }
                        } else if (resolvedApp != null) {
                          widget.onLaunchApp(resolvedApp.packageName);
                        } else {
                          _pickAppForDock(replaceIndex: index);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: isSlotTarget
                            ? BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.65),
                                  width: 1.5,
                                ),
                              )
                            : null,
                        child: Center(child: iconWidget),
                      ),
                    );

                    return LongPressDraggable<LauncherDragPayload>(
                      data: LauncherDragPayload(
                        fromDock: true,
                        index: index,
                        packageName: resolvedApp?.packageName ?? slot.packageName,
                      ),
                      hapticFeedbackOnStart: true,
                      onDragStarted: () {
                        _dragStartPosition = null;
                        _hasMovedDuringDrag = false;
                        _showDockPopupMenu(index, slot);
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
                          scale: 1.12,
                          child: iconWidget,
                        ),
                      ),
                      childWhenDragging: Opacity(
                        opacity: _hasMovedDuringDrag ? 0.25 : 1.0,
                        child: tile,
                      ),
                      child: tile,
                    );
                  },
                ),
              );
            }),
          ),
        );
      },
    );
  }
}

class _DockTrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}