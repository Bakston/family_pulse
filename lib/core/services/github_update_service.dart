import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_theme.dart';

class GithubUpdateService {
  static const String owner = 'Bakston';
  static const String repo = 'family_pulse';
  static const String githubToken =
      ''; // Оставьте пустым для публичного репозитория

  static const MethodChannel _adminChannel = MethodChannel(
    'com.example.family_pulse/device_admin',
  );

  static const String _updateFileName = 'family_pulse_update.apk';
  static const String _prefVersionKey = 'pending_update_version';
  static const String _prefTotalBytesKey = 'pending_update_total_bytes';
  static const String _prefCompletedKey = 'pending_update_completed';

  static String? _activeDownloadVersion;
  static BuildContext? _latestContext;
  static bool _isInstallSheetOpen = false;

  /// Возвращает путь в каталоге updates external-files-path name="updates" path="updates/".
  static Future<File> _getTargetApkFile() async {
    String? baseDirPath;
    try {
      baseDirPath = await _adminChannel.invokeMethod<String>(
        'getUpdateDirectoryPath',
      );
    } catch (_) {}

    final Directory dir = Directory(
      (baseDirPath != null && baseDirPath.isNotEmpty)
          ? baseDirPath
          : '${Directory.systemTemp.path}/updates',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return File('${dir.path}/$_updateFileName');
  }

  static String _formatSizeMb(int bytes) {
    if (bytes <= 0) return '';
    final double mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} МБ';
  }

  static String _formatHttpErrorMessage(int statusCode, String body) {
    if (statusCode == 403) {
      final lower = body.toLowerCase();
      if (lower.contains('rate limit')) {
        return 'Превышен лимит запросов к GitHub API (60/час). Попробуйте позже или установите APK вручную.';
      }
      return 'GitHub отклонил запрос (HTTP 403). Проверьте сеть/ограничения доступа или установите APK вручную.';
    }
    return 'Не удалось проверить обновление (HTTP $statusCode)';
  }

  /// Проверка обновлений с GitHub Releases (работает и у родителя, и у ребёнка).
  static Future<void> checkForUpdates(
    BuildContext context, {
    bool silent = true,
  }) async {
    _latestContext = context;

    final packageInfo = await PackageInfo.fromPlatform();
    final String currentVer = packageInfo.version;

    final url = Uri.parse(
      'https://api.github.com/repos/$owner/$repo/releases/latest',
    );

    final headers = <String, String>{
      'Accept': 'application/vnd.github+json',
      'User-Agent': 'FamilyPulse/$currentVer',
      if (githubToken.isNotEmpty) 'Authorization': 'Bearer $githubToken',
    };

    try {
      final response = await http
          .get(url, headers: headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String latestTag = data['tag_name']?.toString() ?? '';
        final String releaseNotes = (data['body']?.toString() ?? '').trim();

        final List assets = data['assets'] ?? [];
        String? downloadUrl;
        int assetSizeBytes = 0;
        for (final asset in assets) {
          final String name = asset['name']?.toString() ?? '';
          if (name.endsWith('.apk')) {
            downloadUrl = asset['browser_download_url']?.toString();
            assetSizeBytes = int.tryParse(asset['size']?.toString() ?? '0') ?? 0;
            break;
          }
        }

        final String cleanLatest = latestTag
            .replaceAll(RegExp(r'[^0-9.]'), '')
            .split('.')
            .take(3)
            .join('.');
        final String cleanCurrent = currentVer
            .replaceAll(RegExp(r'[^0-9.]'), '')
            .split('.')
            .take(3)
            .join('.');

        if (cleanLatest.isNotEmpty &&
            cleanLatest != cleanCurrent &&
            downloadUrl != null) {
          final prefs = await SharedPreferences.getInstance();
          final savedVer = prefs.getString(_prefVersionKey);
          final isCompleted = prefs.getBool(_prefCompletedKey) ?? false;
          final expectedTotal = prefs.getInt(_prefTotalBytesKey) ?? 0;
          final apkFile = await _getTargetApkFile();

          if (savedVer != cleanLatest) {
            await prefs.setString(_prefVersionKey, cleanLatest);
            await prefs.setBool(_prefCompletedKey, false);
            await prefs.remove(_prefTotalBytesKey);
            if (await apkFile.exists()) {
              await apkFile.delete();
            }
          }

          final bool fileExists = await apkFile.exists();
          final int currentSize = fileExists ? await apkFile.length() : 0;
          final int effectiveTotal =
              expectedTotal > 0 ? expectedTotal : assetSizeBytes;
          final bool readyToInstall =
              isCompleted &&
              fileExists &&
              currentSize > 0 &&
              (effectiveTotal <= 0 || currentSize == effectiveTotal);

          final targetContext = context.mounted ? context : _latestContext;
          if (targetContext == null || !targetContext.mounted) return;

          if (readyToInstall) {
            _showReadyToInstallSheet(targetContext, cleanLatest, apkFile);
          } else if (_activeDownloadVersion == cleanLatest) {
            if (!silent) {
              ScaffoldMessenger.of(targetContext).showSnackBar(
                SnackBar(
                  content: Text(
                    'Обновление $cleanLatest уже скачивается в фоне',
                  ),
                ),
              );
            }
          } else {
            _showAvailableUpdateSheet(
              targetContext,
              version: cleanLatest,
              sizeBytes: assetSizeBytes > 0 ? assetSizeBytes : expectedTotal,
              releaseNotes: releaseNotes,
              downloadUrl: downloadUrl,
              hasPartialFile: currentSize > 0,
            );
          }
        } else {
          if (!silent && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('У вас установлена самая свежая версия!'),
              ),
            );
          }
        }
      } else {
        if (response.statusCode == 403) {
          debugPrint('GithubUpdateService: HTTP 403 -> ${response.body}');
        }
        final targetContext = context.mounted ? context : _latestContext;
        if (!silent && targetContext != null && targetContext.mounted) {
          ScaffoldMessenger.of(targetContext).showSnackBar(
            SnackBar(
              content: Text(
                _formatHttpErrorMessage(response.statusCode, response.body),
              ),
            ),
          );
        }
      }
    } catch (e) {
      final targetContext = context.mounted ? context : _latestContext;
      if (!silent && targetContext != null && targetContext.mounted) {
        ScaffoldMessenger.of(targetContext).showSnackBar(
          SnackBar(content: Text('Ошибка проверки обновления: $e')),
        );
      }
    }
  }

  static void _showAvailableUpdateSheet(
    BuildContext context, {
    required String version,
    required int sizeBytes,
    required String releaseNotes,
    required String downloadUrl,
    required bool hasPartialFile,
  }) {
    bool showDetails = false;
    final String sizeLabel = _formatSizeMb(sizeBytes);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Доступно обновление',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  hasPartialFile
                      ? 'Найдена незавершённая загрузка версии $version. Продолжить скачивание в фоне? Вы сможете пользоваться приложением.'
                      : 'Чтобы использовать актуальные функции, установите последнюю версию. Во время скачивания вы по-прежнему сможете пользоваться приложением.',
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: Colors.white70,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.asset(
                        AppTheme.parentBackgroundAsset,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 48,
                          height: 48,
                          color: Colors.blue.shade800,
                          child: const Icon(
                            Icons.system_update,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'FamilyPulse',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            sizeLabel.isNotEmpty
                                ? 'Версия $version • $sizeLabel'
                                : 'Версия $version',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setSheetState(() => showDetails = !showDetails),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Что нового',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        Icon(
                          showDetails
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          color: Colors.white70,
                        ),
                      ],
                    ),
                  ),
                ),
                if (showDetails) ...[
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxHeight: 160),
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: SingleChildScrollView(
                      child: Text(
                        releaseNotes.isNotEmpty
                            ? releaseNotes
                            : 'Улучшения стабильности, безопасности сессии и работы обновлений.',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.white70,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        onPressed: () {
                          setSheetState(() => showDetails = !showDetails);
                        },
                        child: Text(showDetails ? 'Скрыть' : 'Подробнее'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: Colors.blue.shade300,
                          foregroundColor: Colors.black87,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          unawaited(
                            _downloadBackground(
                              context,
                              version,
                              downloadUrl,
                            ),
                          );
                        },
                        child: Text(
                          hasPartialFile ? 'Докачать' : 'Обновить',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static void _showReadyToInstallSheet(
    BuildContext context,
    String version,
    File apkFile,
  ) {
    if (_isInstallSheetOpen) return;
    _isInstallSheetOpen = true;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade900,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Обновление загружено',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Версия $version готова к установке. Приложение станет актуальной версией себя.',
                style: const TextStyle(
                  fontSize: 15,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: Colors.grey.shade200,
                  foregroundColor: Colors.black87,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(27),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(sheetContext);
                  unawaited(_launchInstaller(context, apkFile));
                },
                child: const Text(
                  'Установить',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(() {
      _isInstallSheetOpen = false;
    });
  }

  static Future<void> _downloadBackground(
    BuildContext context,
    String version,
    String downloadUrl,
  ) async {
    if (_activeDownloadVersion == version) return;
    _activeDownloadVersion = version;

    final packageInfo = await PackageInfo.fromPlatform();
    final prefs = await SharedPreferences.getInstance();
    final File apkFile = await _getTargetApkFile();
    int existingBytes = await apkFile.exists() ? await apkFile.length() : 0;

    final http.Client client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(downloadUrl));
      request.headers['User-Agent'] = 'FamilyPulse/${packageInfo.version}';
      if (githubToken.isNotEmpty) {
        request.headers['Authorization'] = 'Bearer $githubToken';
      }
      if (existingBytes > 0) {
        request.headers['Range'] = 'bytes=$existingBytes-';
      }

      final streamedResponse = await client
          .send(request)
          .timeout(const Duration(seconds: 20));
      final bool isPartial =
          streamedResponse.statusCode == 206 && existingBytes > 0;

      if (!isPartial) {
        existingBytes = 0;
        if (await apkFile.exists()) {
          await apkFile.delete();
        }
      }

      if (streamedResponse.statusCode == 200 ||
          streamedResponse.statusCode == 206) {
        final int contentLength = streamedResponse.contentLength ?? -1;
        final int totalBytes = contentLength > 0
            ? existingBytes + contentLength
            : -1;
        if (totalBytes > 0) {
          await prefs.setInt(_prefTotalBytesKey, totalBytes);
        }

        final sink = apkFile.openWrite(
          mode: isPartial ? FileMode.append : FileMode.write,
        );

        try {
          await for (final chunk in streamedResponse.stream) {
            sink.add(chunk);
          }
        } finally {
          await sink.flush();
          await sink.close();
        }

        await prefs.setString(_prefVersionKey, version);
        await prefs.setBool(_prefCompletedKey, true);

        final targetContext = context.mounted ? context : _latestContext;
        if (targetContext != null && targetContext.mounted) {
          _showReadyToInstallSheet(targetContext, version, apkFile);
        }
      } else {
        final targetContext = context.mounted ? context : _latestContext;
        if (targetContext != null && targetContext.mounted) {
          ScaffoldMessenger.of(targetContext).showSnackBar(
            SnackBar(
              content: Text(
                'Ошибка при скачивании файла обновления (HTTP ${streamedResponse.statusCode})',
              ),
            ),
          );
        }
      }
    } catch (e) {
      final targetContext = context.mounted ? context : _latestContext;
      if (targetContext != null && targetContext.mounted) {
        ScaffoldMessenger.of(targetContext)
            .showSnackBar(SnackBar(content: Text('Ошибка загрузки: $e')));
      }
    } finally {
      client.close();
      if (_activeDownloadVersion == version) {
        _activeDownloadVersion = null;
      }
    }
  }

  static Future<void> _launchInstaller(
    BuildContext context,
    File apkFile,
  ) async {
    try {
      final bool? started = await _adminChannel.invokeMethod<bool>(
        'installOwnUpdateApk',
        {'filePath': apkFile.path},
      );
      final targetContext = context.mounted ? context : _latestContext;
      if (started == false && targetContext != null && targetContext.mounted) {
        ScaffoldMessenger.of(targetContext).showSnackBar(
          const SnackBar(
            content: Text(
              'Разрешите установку из этого источника в открывшихся настройках и нажмите «Установить» ещё раз',
            ),
          ),
        );
      }
    } catch (e) {
      final targetContext = context.mounted ? context : _latestContext;
      if (targetContext != null && targetContext.mounted) {
        ScaffoldMessenger.of(targetContext).showSnackBar(
          SnackBar(content: Text('Не удалось запустить установщик: $e')),
        );
      }
    }
  }
}