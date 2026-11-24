import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

class AppLogEntry {
  final DateTime timestamp;
  final String tag;
  final String message;
  final bool isError;

  AppLogEntry({
    required this.timestamp,
    required this.tag,
    required this.message,
    this.isError = false,
  });

  String get formattedTime {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class AppLogService {
  AppLogService._();

  static final List<AppLogEntry> _entries = [];
  static const int _maxEntries = 150;

  static List<AppLogEntry> get entries => List.unmodifiable(_entries);

  static void info(String tag, String message) {
    _add(tag, message, isError: false);
  }

  static void error(String tag, Object err, [StackTrace? stack]) {
    _add(tag, err.toString(), isError: true);
  }

  static void _add(String tag, String message, {required bool isError}) {
    _entries.insert(
      0,
      AppLogEntry(
        timestamp: DateTime.now(),
        tag: tag,
        message: message,
        isError: isError,
      ),
    );
    if (_entries.length > _maxEntries) {
      _entries.removeRange(_maxEntries, _entries.length);
    }
    debugPrint('[$tag] $message');
  }

  static void clear() {
    _entries.clear();
  }

  static String exportAsText() {
    if (_entries.isEmpty) return 'Логи пусты';
    return _entries
        .map((e) => '[${e.formattedTime}] [${e.tag}] ${e.message}')
        .join('\n');
  }

  /// Шторка просмотра логов для меню настроек (шестерёнка)
  static void showLogsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (modalContext, setModalState) {
          final logs = AppLogService.entries;
          return DraggableScrollableSheet(
            initialChildSize: 0.72,
            minChildSize: 0.45,
            maxChildSize: 0.92,
            expand: false,
            builder: (context, scrollController) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.bug_report_rounded, color: Colors.indigo),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Системные логи (${logs.length})',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Скопировать все логи',
                        icon: const Icon(Icons.copy_rounded, size: 20),
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: AppLogService.exportAsText()),
                          );
                          if (sheetContext.mounted) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              const SnackBar(
                                content: Text('Логи скопированы в буфер обмена'),
                              ),
                            );
                          }
                        },
                      ),
                      IconButton(
                        tooltip: 'Очистить',
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                        onPressed: () {
                          AppLogService.clear();
                          setModalState(() {});
                        },
                      ),
                    ],
                  ),
                  const Divider(height: 16),
                  Expanded(
                    child: logs.isEmpty
                        ? const Center(
                            child: Text(
                              'Ошибок и событий пока не зафиксировано',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.separated(
                            controller: scrollController,
                            itemCount: logs.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = logs[index];
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 6,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: item.isError
                                                ? Colors.red.shade50
                                                : Colors.blue.shade50,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            item.tag,
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: item.isError
                                                  ? Colors.red.shade700
                                                  : Colors.blue.shade700,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          item.formattedTime,
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Colors.black45,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    SelectableText(
                                      item.message,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: item.isError
                                            ? Colors.red.shade900
                                            : Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}