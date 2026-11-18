import 'package:flutter/material.dart';
import '../../core/app_theme.dart';

class FamilyCalendarWidget extends StatefulWidget {
  final DateTime selectedDate;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final ValueChanged<DateTime> onDateSelected;

  /// Задел под будущий календарь событий: дата (без времени) -> список цветов точек
  final Map<DateTime, List<Color>>? eventMarkers;

  /// Необязательная палитра (если null — используется светлый стиль родительской панели)
  final AppPalette? palette;

  /// Показывать ли кнопку быстрого перехода на «Сегодня»
  final bool showTodayButton;

  const FamilyCalendarWidget({
    super.key,
    required this.selectedDate,
    required this.onDateSelected,
    this.firstDate,
    this.lastDate,
    this.eventMarkers,
    this.palette,
    this.showTodayButton = true,
  });

  /// Удобный статический вызов диалога выбора даты (замена стандартного showDatePicker)
  static Future<DateTime?> showPickerDialog({
    required BuildContext context,
    required DateTime initialDate,
    DateTime? firstDate,
    DateTime? lastDate,
    String title = 'Выберите дату',
    AppPalette? palette,
    Map<DateTime, List<Color>>? eventMarkers,
  }) {
    DateTime tempSelected = DateTime(
      initialDate.year,
      initialDate.month,
      initialDate.day,
    );

    final bgColor = palette != null
        ? palette.background.withValues(alpha: 0.97)
        : Colors.white;
    final titleColor = palette?.textPrimary ?? Colors.black87;
    final accentColor = palette?.primaryAccent ?? Colors.blue.shade700;

    return showDialog<DateTime>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (builderContext, setDialogState) => AlertDialog(
          backgroundColor: bgColor,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: palette != null
                ? BorderSide(
                    color: palette.primaryAccent.withValues(alpha: 0.35),
                    width: 1.2,
                  )
                : BorderSide.none,
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          title: Row(
            children: [
              Icon(Icons.calendar_month_rounded, color: accentColor, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: titleColor,
                  ),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width,
            child: FamilyCalendarWidget(
              selectedDate: tempSelected,
              firstDate: firstDate,
              lastDate: lastDate,
              palette: palette,
              eventMarkers: eventMarkers,
              onDateSelected: (date) {
                setDialogState(() => tempSelected = date);
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(
                'Отмена',
                style: TextStyle(
                  color: palette?.textSecondary ?? Colors.black54,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: palette != null ? palette.background : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.pop(dialogContext, tempSelected),
              child: const Text(
                'Выбрать',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  State<FamilyCalendarWidget> createState() => _FamilyCalendarWidgetState();
}

class _FamilyCalendarWidgetState extends State<FamilyCalendarWidget> {
  static const List<String> _monthNames = [
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь',
  ];

  static const List<String> _weekdayShort = [
    'Пн',
    'Вт',
    'Ср',
    'Чт',
    'Пт',
    'Сб',
    'Вс',
  ];

  late DateTime _displayedMonth;
  bool _isYearPickerOpen = false;
  late ScrollController _yearScrollController;

  DateTime get _minDate {
    final d = widget.firstDate ?? DateTime(1950, 1, 1);
    return DateTime(d.year, d.month, d.day);
  }

  DateTime get _maxDate {
    final d = widget.lastDate ?? DateTime(2035, 12, 31);
    return DateTime(d.year, d.month, d.day);
  }

  @override
  void initState() {
    super.initState();
    _displayedMonth = DateTime(
      widget.selectedDate.year,
      widget.selectedDate.month,
      1,
    );
    _yearScrollController = ScrollController();
  }

  @override
  void didUpdateWidget(covariant FamilyCalendarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isSameDay(oldWidget.selectedDate, widget.selectedDate)) {
      _displayedMonth = DateTime(
        widget.selectedDate.year,
        widget.selectedDate.month,
        1,
      );
    }
  }

  @override
  void dispose() {
    _yearScrollController.dispose();
    super.dispose();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isDateDisabled(DateTime date) {
    final normalized = DateTime(date.year, date.month, date.day);
    return normalized.isBefore(_minDate) || normalized.isAfter(_maxDate);
  }

  bool get _canGoPrevMonth {
    final prevLastDay = DateTime(_displayedMonth.year, _displayedMonth.month, 0);
    return !prevLastDay.isBefore(_minDate);
  }

  bool get _canGoNextMonth {
    final nextFirstDay =
        DateTime(_displayedMonth.year, _displayedMonth.month + 1, 1);
    return !nextFirstDay.isAfter(_maxDate);
  }

  void _changeMonth(int delta) {
    final target = DateTime(
      _displayedMonth.year,
      _displayedMonth.month + delta,
      1,
    );
    if (delta < 0 && !_canGoPrevMonth) return;
    if (delta > 0 && !_canGoNextMonth) return;

    setState(() {
      _displayedMonth = target;
    });
  }

  void _jumpToToday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_isDateDisabled(today)) return;

    setState(() {
      _isYearPickerOpen = false;
      _displayedMonth = DateTime(today.year, today.month, 1);
    });
    widget.onDateSelected(today);
  }

  List<Color> _getMarkersForDate(DateTime date) {
    if (widget.eventMarkers == null || widget.eventMarkers!.isEmpty) {
      return const [];
    }
    final key = DateTime(date.year, date.month, date.day);
    return widget.eventMarkers![key] ?? const [];
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final Color primaryText = p?.textPrimary ?? Colors.black87;
    final Color secondaryText = p?.textSecondary ?? Colors.black54;
    final Color accentColor = p?.primaryAccent ?? Colors.blue.shade700;
    final Color selectedTextColor = p != null ? p.background : Colors.white;
    final Color cardBg = p?.glassPanel ?? Colors.white;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final bool canSelectToday = !_isDateDisabled(today);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: p != null
              ? p.primaryAccent.withValues(alpha: 0.25)
              : Colors.grey.shade200,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ШАПКА: МЕСЯЦ/ГОД + ПЕРЕКЛЮЧЕНИЕ + «СЕГОДНЯ»
          Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  setState(() => _isYearPickerOpen = !_isYearPickerOpen);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${_monthNames[_displayedMonth.month - 1]} ${_displayedMonth.year}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: primaryText,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _isYearPickerOpen
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: accentColor,
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              if (widget.showTodayButton &&
                  canSelectToday &&
                  !_isSameDay(widget.selectedDate, today))
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                  ),
                  onPressed: _jumpToToday,
                  child: Text(
                    'Сегодня',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: accentColor,
                    ),
                  ),
                ),
              if (!_isYearPickerOpen) ...[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Предыдущий месяц',
                  onPressed: _canGoPrevMonth ? () => _changeMonth(-1) : null,
                  icon: Icon(
                    Icons.chevron_left_rounded,
                    color: _canGoPrevMonth
                        ? primaryText
                        : secondaryText.withValues(alpha: 0.3),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Следующий месяц',
                  onPressed: _canGoNextMonth ? () => _changeMonth(1) : null,
                  icon: Icon(
                    Icons.chevron_right_rounded,
                    color: _canGoNextMonth
                        ? primaryText
                        : secondaryText.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          if (_isYearPickerOpen)
            _buildYearMonthSelector(
              primaryText: primaryText,
              secondaryText: secondaryText,
              accentColor: accentColor,
              selectedTextColor: selectedTextColor,
            )
          else
            GestureDetector(
              onHorizontalDragEnd: (details) {
                final v = details.primaryVelocity ?? 0;
                if (v < -250) {
                  _changeMonth(1);
                } else if (v > 250) {
                  _changeMonth(-1);
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ДНИ НЕДЕЛИ (ПН - ВС)
                  Row(
                    children: List.generate(7, (idx) {
                      final isWeekend = idx >= 5;
                      return Expanded(
                        child: Center(
                          child: Text(
                            _weekdayShort[idx],
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isWeekend
                                  ? Colors.redAccent.withValues(alpha: 0.85)
                                  : secondaryText,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 6),

                  // СЕТКА ЧИСЕЛ МЕСЯЦА
                  _buildDaysGrid(
                    today: today,
                    primaryText: primaryText,
                    secondaryText: secondaryText,
                    accentColor: accentColor,
                    selectedTextColor: selectedTextColor,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildYearMonthSelector({
    required Color primaryText,
    required Color secondaryText,
    required Color accentColor,
    required Color selectedTextColor,
  }) {
    final int startYear = _minDate.year;
    final int endYear = _maxDate.year;
    final int yearsCount = (endYear - startYear + 1).clamp(1, 150);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 150,
          child: GridView.builder(
            controller: _yearScrollController,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 2.1,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: yearsCount,
            itemBuilder: (context, index) {
              final year = endYear - index; // Сверху свежие годы
              final isSelected = year == _displayedMonth.year;
              return InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  int targetMonth = _displayedMonth.month;
                  if (year == _minDate.year && targetMonth < _minDate.month) {
                    targetMonth = _minDate.month;
                  }
                  if (year == _maxDate.year && targetMonth > _maxDate.month) {
                    targetMonth = _maxDate.month;
                  }
                  setState(() {
                    _displayedMonth = DateTime(year, targetMonth, 1);
                    _isYearPickerOpen = false;
                  });
                },
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? accentColor
                        : accentColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$year',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? selectedTextColor : primaryText,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(height: 16),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: List.generate(12, (idx) {
            final monthNum = idx + 1;
            final candidate = DateTime(_displayedMonth.year, monthNum, 1);
            final candidateEnd =
                DateTime(_displayedMonth.year, monthNum + 1, 0);
            final disabled = candidateEnd.isBefore(_minDate) ||
                candidate.isAfter(_maxDate);
            final isSelected = monthNum == _displayedMonth.month;

            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: disabled
                  ? null
                  : () {
                      setState(() {
                        _displayedMonth =
                            DateTime(_displayedMonth.year, monthNum, 1);
                        _isYearPickerOpen = false;
                      });
                    },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? accentColor
                      : accentColor.withValues(alpha: disabled ? 0.02 : 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _monthNames[idx].substring(0, 3),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: disabled
                        ? secondaryText.withValues(alpha: 0.3)
                        : (isSelected ? selectedTextColor : primaryText),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildDaysGrid({
    required DateTime today,
    required Color primaryText,
    required Color secondaryText,
    required Color accentColor,
    required Color selectedTextColor,
  }) {
    final firstDayOfMonth =
        DateTime(_displayedMonth.year, _displayedMonth.month, 1);
    final int leadingEmptyCells = firstDayOfMonth.weekday - 1; // Пн = 0
    final int daysInMonth =
        DateTime(_displayedMonth.year, _displayedMonth.month + 1, 0).day;
    final int totalCells =
        ((leadingEmptyCells + daysInMonth + 6) ~/ 7) * 7;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 1.05,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: totalCells,
      itemBuilder: (context, index) {
        final dayNumber = index - leadingEmptyCells + 1;
        if (dayNumber < 1 || dayNumber > daysInMonth) {
          return const SizedBox.shrink();
        }

        final cellDate =
            DateTime(_displayedMonth.year, _displayedMonth.month, dayNumber);
        final bool isDisabled = _isDateDisabled(cellDate);
        final bool isSelected = _isSameDay(cellDate, widget.selectedDate);
        final bool isToday = _isSameDay(cellDate, today);
        final bool isWeekend = cellDate.weekday >= 6;
        final markers = _getMarkersForDate(cellDate);

        Color textColor;
        if (isDisabled) {
          textColor = secondaryText.withValues(alpha: 0.3);
        } else if (isSelected) {
          textColor = selectedTextColor;
        } else if (isWeekend) {
          textColor = Colors.redAccent;
        } else {
          textColor = primaryText;
        }

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: isDisabled ? null : () => widget.onDateSelected(cellDate),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? accentColor
                  : (isToday
                      ? accentColor.withValues(alpha: 0.12)
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(12),
              border: isToday && !isSelected
                  ? Border.all(color: accentColor, width: 1.3)
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$dayNumber',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: (isSelected || isToday)
                        ? FontWeight.bold
                        : FontWeight.w500,
                    color: textColor,
                  ),
                ),
                if (markers.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: markers
                        .take(3)
                        .map(
                          (c) => Container(
                            width: 4.5,
                            height: 4.5,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected ? selectedTextColor : c,
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
    );
  }
}