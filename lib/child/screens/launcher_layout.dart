enum DockSlotType {
  messages,
  camera,
  dialer,
  gallery,
  appDrawer,
  app,
}

class LauncherDockSlot {
  final DockSlotType type;
  final String? packageName;

  const LauncherDockSlot({
    required this.type,
    this.packageName,
  });

  LauncherDockSlot copyWith({
    DockSlotType? type,
    String? packageName,
    bool clearPackageName = false,
  }) {
    return LauncherDockSlot(
      type: type ?? this.type,
      packageName: clearPackageName ? null : (packageName ?? this.packageName),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        if (packageName != null) 'packageName': packageName,
      };

  factory LauncherDockSlot.fromJson(Map<String, dynamic> json) {
    final rawType = json['type']?.toString() ?? 'app';
    final type = DockSlotType.values.firstWhere(
      (e) => e.name == rawType,
      orElse: () => DockSlotType.app,
    );
    return LauncherDockSlot(
      type: type,
      packageName: json['packageName']?.toString(),
    );
  }
}

class LauncherDragPayload {
  final bool fromDock;
  final int index;
  final String? packageName;

  const LauncherDragPayload({
    required this.fromDock,
    required this.index,
    this.packageName,
  });
}

class LauncherLayoutState {
  static const int totalGridSlots = 20; // 4 колонки x 5 рядов
  static const int maxDockSlots = 5;

  final List<String?> gridSlots;
  final List<LauncherDockSlot> dockSlots;

  const LauncherLayoutState({
    this.gridSlots = const [],
    this.dockSlots = defaultDock,
  });

  static const List<LauncherDockSlot> defaultDock = [
    LauncherDockSlot(type: DockSlotType.messages),
    LauncherDockSlot(type: DockSlotType.camera),
    LauncherDockSlot(type: DockSlotType.dialer),
    LauncherDockSlot(type: DockSlotType.gallery),
  ];

  static List<String?> _normalizeGridSlots(List<String?> raw) {
    final result = List<String?>.filled(totalGridSlots, null);
    final seen = <String>{};
    for (int i = 0; i < raw.length && i < totalGridSlots; i++) {
      final pkg = raw[i]?.trim();
      if (pkg != null && pkg.isNotEmpty && !seen.contains(pkg)) {
        result[i] = pkg;
        seen.add(pkg);
      }
    }
    return result;
  }

  List<String?> get normalizedGridSlots => _normalizeGridSlots(gridSlots);

  LauncherLayoutState copyWith({
    List<String?>? gridSlots,
    List<LauncherDockSlot>? dockSlots,
  }) {
    final nextDock = dockSlots != null
        ? dockSlots
            .where((s) => s.type != DockSlotType.appDrawer)
            .take(maxDockSlots)
            .toList()
        : List<LauncherDockSlot>.from(this.dockSlots);

    return LauncherLayoutState(
      gridSlots: gridSlots != null
          ? _normalizeGridSlots(gridSlots)
          : normalizedGridSlots,
      dockSlots: nextDock.isEmpty ? List<LauncherDockSlot>.from(defaultDock) : nextDock,
    );
  }

  bool containsOnGrid(String packageName) {
    final clean = packageName.trim();
    if (clean.isEmpty) return false;
    return gridSlots.contains(clean);
  }

  bool containsInDock(String packageName) {
    final clean = packageName.trim();
    if (clean.isEmpty) return false;
    return dockSlots.any((s) => s.packageName == clean);
  }

  LauncherLayoutState addAppToGrid(String packageName) {
    final clean = packageName.trim();
    if (clean.isEmpty || containsOnGrid(clean)) {
      return this;
    }
    final next = normalizedGridSlots;
    final emptyIdx = next.indexOf(null);
    if (emptyIdx == -1) {
      return this;
    }
    next[emptyIdx] = clean;
    return copyWith(gridSlots: next);
  }

  LauncherLayoutState removeAppFromGrid(String packageName) {
    final clean = packageName.trim();
    final next = normalizedGridSlots;
    final idx = next.indexOf(clean);
    if (idx == -1) {
      return this;
    }
    next[idx] = null;
    return copyWith(gridSlots: next);
  }

  LauncherLayoutState moveAppToSlot(int fromIndex, int toIndex) {
    if (fromIndex < 0 ||
        fromIndex >= totalGridSlots ||
        toIndex < 0 ||
        toIndex >= totalGridSlots ||
        fromIndex == toIndex) {
      return this;
    }
    final next = normalizedGridSlots;
    final movingPkg = next[fromIndex];
    if (movingPkg == null) return this;

    final targetPkg = next[toIndex];
    next[toIndex] = movingPkg;
    next[fromIndex] = targetPkg;
    return copyWith(gridSlots: next);
  }

  LauncherLayoutState moveDockSlot(int fromIndex, int toIndex) {
    if (fromIndex < 0 ||
        fromIndex >= dockSlots.length ||
        toIndex < 0 ||
        toIndex >= dockSlots.length ||
        fromIndex == toIndex) {
      return this;
    }
    final next = List<LauncherDockSlot>.from(dockSlots);
    final moved = next.removeAt(fromIndex);
    next.insert(toIndex, moved);
    return copyWith(dockSlots: next);
  }

  LauncherLayoutState addAppToDock(String packageName, {int? targetIndex}) {
    final clean = packageName.trim();
    if (clean.isEmpty) return this;

    final nextDock = List<LauncherDockSlot>.from(dockSlots);
    final newSlot = LauncherDockSlot(type: DockSlotType.app, packageName: clean);

    if (targetIndex != null && targetIndex >= 0 && targetIndex < nextDock.length) {
      nextDock[targetIndex] = newSlot;
    } else if (nextDock.length < maxDockSlots) {
      nextDock.add(newSlot);
    } else {
      return this;
    }
    return copyWith(dockSlots: nextDock);
  }

  LauncherLayoutState removeDockSlot(int index) {
    if (index < 0 || index >= dockSlots.length || dockSlots.length <= 1) {
      return this;
    }
    final nextDock = List<LauncherDockSlot>.from(dockSlots)..removeAt(index);
    return copyWith(dockSlots: nextDock);
  }

  /// Переносит ярлык из сетки в док (в указанный слот или добавляет 5-м)
  LauncherLayoutState moveGridAppToDock(int gridIndex, {int? dockIndex}) {
    final nextGrid = normalizedGridSlots;
    if (gridIndex < 0 || gridIndex >= nextGrid.length) return this;
    final pkg = nextGrid[gridIndex];
    if (pkg == null) return this;

    final nextDock = List<LauncherDockSlot>.from(dockSlots);
    if (dockIndex != null && dockIndex >= 0 && dockIndex < nextDock.length) {
      final displaced = nextDock[dockIndex];
      nextDock[dockIndex] = LauncherDockSlot(type: DockSlotType.app, packageName: pkg);
      nextGrid[gridIndex] =
          (displaced.type == DockSlotType.app && displaced.packageName != null)
              ? displaced.packageName
              : null;
    } else if (nextDock.length < maxDockSlots) {
      nextDock.add(LauncherDockSlot(type: DockSlotType.app, packageName: pkg));
      nextGrid[gridIndex] = null;
    } else {
      return this;
    }

    return copyWith(gridSlots: nextGrid, dockSlots: nextDock);
  }

  /// Переносит ярлык из дока в свободную ячейку сетки (если это пользовательский слот)
  LauncherLayoutState moveDockAppToGrid(int dockIndex, int gridIndex) {
    if (dockIndex < 0 || dockIndex >= dockSlots.length) return this;
    final nextGrid = normalizedGridSlots;
    if (gridIndex < 0 || gridIndex >= nextGrid.length) return this;

    final slot = dockSlots[dockIndex];
    final pkg = slot.packageName;
    if (pkg == null || pkg.isEmpty) return this;

    final nextDock = List<LauncherDockSlot>.from(dockSlots);
    final existingGridPkg = nextGrid[gridIndex];

    nextGrid[gridIndex] = pkg;
    if (existingGridPkg != null) {
      nextDock[dockIndex] =
          LauncherDockSlot(type: DockSlotType.app, packageName: existingGridPkg);
    } else if (slot.type == DockSlotType.app) {
      nextDock.removeAt(dockIndex);
    } else {
      nextDock[dockIndex] = slot.copyWith(clearPackageName: true);
    }

    return copyWith(gridSlots: nextGrid, dockSlots: nextDock);
  }

  LauncherLayoutState pruneUnavailableApps(Set<String> availablePackageNames) {
    final next = normalizedGridSlots;
    bool changed = false;
    for (int i = 0; i < next.length; i++) {
      final pkg = next[i];
      if (pkg != null && !availablePackageNames.contains(pkg)) {
        next[i] = null;
        changed = true;
      }
    }
    if (!changed) return this;
    return copyWith(gridSlots: next);
  }

  Map<String, dynamic> toJson() => {
        'gridSlots': normalizedGridSlots,
        'dockSlots': dockSlots.map((e) => e.toJson()).toList(),
      };

  factory LauncherLayoutState.fromJson(Map<String, dynamic> json) {
    List<String?> parsedSlots;
    if (json['gridSlots'] is List) {
      final raw = json['gridSlots'] as List;
      parsedSlots = _normalizeGridSlots(
        raw.map((e) => e?.toString()).toList(),
      );
    } else if (json['gridPackages'] is List) {
      final raw = json['gridPackages'] as List;
      parsedSlots = _normalizeGridSlots(
        raw.map((e) => e?.toString()).toList(),
      );
    } else {
      parsedSlots = List<String?>.filled(totalGridSlots, null);
    }

    final rawDock = json['dockSlots'];
    final dock = rawDock is List
        ? rawDock
            .whereType()
            .map((e) => LauncherDockSlot.fromJson(Map<String, dynamic>.from(e)))
            .where((slot) => slot.type != DockSlotType.appDrawer)
            .take(maxDockSlots)
            .toList()
        : List<LauncherDockSlot>.from(defaultDock);

    return LauncherLayoutState(
      gridSlots: parsedSlots,
      dockSlots: dock.isEmpty ? List<LauncherDockSlot>.from(defaultDock) : dock,
    );
  }
}