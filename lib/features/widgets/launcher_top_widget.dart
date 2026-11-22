import 'dart:convert';
import 'dart:typed_data';
import 'package:material_ui/material_ui.dart';
import '../../core/app_theme.dart';

class LauncherTopWidget extends StatelessWidget {
  final String childName;
  final String childGender;
  final String? childAvatarUrl;
  final int unreadChatCount;
  final int activeTasksCount;
  final int newTasksCount;
  final VoidCallback onOpenTasks;
  final VoidCallback onOpenChat;
  final VoidCallback onAvatarLongPress;

  const LauncherTopWidget({
    super.key,
    required this.childName,
    required this.childGender,
    this.childAvatarUrl,
    required this.unreadChatCount,
    required this.activeTasksCount,
    required this.newTasksCount,
    required this.onOpenTasks,
    required this.onOpenChat,
    required this.onAvatarLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;

    final surfaceColor = isDark
        ? const Color(0xCC1B1E24)
        : const Color(0xD9FFFFFF);
    final tileColor = isDark
        ? const Color(0x33FFFFFF)
        : const Color(0x14000000);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.black.withValues(alpha: 0.08);
    final primaryText = isDark ? Colors.white : const Color(0xFF181A1F);
    final secondaryText =
        isDark ? Colors.white70 : const Color(0xFF5C6270);
    final accentColor = isDark
        ? const Color(0xFF7CB8FF)
        : const Color(0xFF1D63B8);

    final tasksBadge = newTasksCount > 0 ? newTasksCount : activeTasksCount;
    final tasksSubtitle = newTasksCount > 0
        ? 'Новых: $newTasksCount'
        : (activeTasksCount > 0 ? 'Активных: $activeTasksCount' : 'Список дел');

    final chatSubtitle =
        unreadChatCount > 0 ? 'Новых: $unreadChatCount' : 'Семья';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TopActionTile(
              icon: Icons.assignment_turned_in_rounded,
              title: 'Задания',
              subtitle: tasksSubtitle,
              badgeCount: tasksBadge,
              badgeColor: newTasksCount > 0
                  ? const Color(0xFFE67E22)
                  : accentColor,
              tileColor: tileColor,
              primaryText: primaryText,
              secondaryText: secondaryText,
              iconColor: accentColor,
              onTap: onOpenTasks,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _TopActionTile(
              icon: Icons.chat_bubble_rounded,
              title: 'Чат',
              subtitle: chatSubtitle,
              badgeCount: unreadChatCount,
              badgeColor: AppTheme.errorColor,
              tileColor: tileColor,
              primaryText: primaryText,
              secondaryText: secondaryText,
              iconColor: accentColor,
              onTap: onOpenChat,
            ),
          ),
          const SizedBox(width: 8),
          _ChildAvatarTile(
            childName: childName,
            childGender: childGender,
            avatarSource: childAvatarUrl,
            onLongPress: onAvatarLongPress,
          ),
        ],
      ),
    );
  }
}

class _ChildAvatarTile extends StatelessWidget {
  final String childName;
  final String childGender;
  final String? avatarSource;
  final VoidCallback onLongPress;

  const _ChildAvatarTile({
    required this.childName,
    required this.childGender,
    required this.avatarSource,
    required this.onLongPress,
  });

  Uint8List? _tryDecodeBase64(String raw) {
    if (raw.isEmpty) return null;
    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return null;
    }
    try {
      final clean = raw.contains(',') ? raw.split(',').last.trim() : raw.trim();
      if (clean.length < 32) return null;
      return base64Decode(clean);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final trimmedName = childName.trim();
    final initial = trimmedName.isNotEmpty
        ? trimmedName.characters.first.toUpperCase()
        : 'Р';
    final isGirl = childGender == 'girl';
    final gradientColors = isGirl
        ? const [Color(0xFFFF4D94), Color(0xFFB83280)]
        : const [Color(0xFF2563EB), Color(0xFF00B4D8)];
    final ringColor = isGirl
        ? const Color(0xFFFF2A85).withValues(alpha: 0.45)
        : const Color(0xFF3B82F6).withValues(alpha: 0.45);

    final rawSource = (avatarSource ?? '').trim();
    final isHttpUrl =
        rawSource.startsWith('http://') || rawSource.startsWith('https://');
    final Uint8List? memoryBytes =
        isHttpUrl ? null : _tryDecodeBase64(rawSource);

    Widget avatarContent;
    if (memoryBytes != null) {
      avatarContent = Image.memory(
        memoryBytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _buildFallback(
          initial: initial,
          gradientColors: gradientColors,
        ),
      );
    } else if (isHttpUrl) {
      avatarContent = Image.network(
        rawSource,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _buildFallback(
          initial: initial,
          gradientColors: gradientColors,
        ),
      );
    } else {
      avatarContent = _buildFallback(
        initial: initial,
        gradientColors: gradientColors,
      );
    }

    return Tooltip(
      message: 'Удерживайте для входа родителя',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: onLongPress,
        child: Container(
          width: 52,
          height: 52,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ringColor, width: 2),
          ),
          child: ClipOval(child: avatarContent),
        ),
      ),
    );
  }

  Widget _buildFallback({
    required String initial,
    required List<Color> gradientColors,
  }) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _TopActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final int badgeCount;
  final Color badgeColor;
  final Color tileColor;
  final Color primaryText;
  final Color secondaryText;
  final Color iconColor;
  final VoidCallback onTap;

  const _TopActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badgeCount,
    required this.badgeColor,
    required this.tileColor,
    required this.primaryText,
    required this.secondaryText,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tileColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 20, color: iconColor),
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          style: const TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: primaryText,
                      ),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 11,
                        color: secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}