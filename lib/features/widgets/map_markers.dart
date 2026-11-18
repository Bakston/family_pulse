import 'package:flutter/material.dart';
import 'user_avatar_widget.dart';

/// Маркер ребёнка с аватаркой и рамкой статуса
class ChildAvatarMapMarker extends StatelessWidget {
  final String avatarBase64;
  final String childName;
  final bool isOnline;
  final bool isMoving;

  const ChildAvatarMapMarker({
    super.key,
    required this.avatarBase64,
    required this.childName,
    this.isOnline = true,
    this.isMoving = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color statusColor = isOnline ? const Color(0xFF2ECC71) : Colors.grey;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Плашка с именем (опционально, компактная сверху)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          margin: const EdgeInsets.only(bottom: 3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                childName,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),

        // Круглый пин с аватаркой
        Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Хвостик снизу
            Positioned(
              bottom: -5,
              child: Transform.rotate(
                angle: 0.785398, // 45 градусов
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
            // Ободок и аватар
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: UserAvatarWidget(
                  avatarBase64: avatarBase64,
                  radius: 21,
                  fallbackIcon: Icons.child_care,
                  fallbackBackgroundColor: Colors.blue.shade50,
                  fallbackIconColor: Colors.blue.shade700,
                ),
              ),
            ),
            // Мини-бейдж движения (если едет на транспорте/машине)
            if (isMoving)
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade700,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.directions_car_rounded,
                    size: 11,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Маркер важной точки / геозоны (Дом, Школа, Кружок)
class GeofenceMapMarker extends StatelessWidget {
  final String title;
  final String iconType; // 'home', 'school', 'sport', 'other'

  const GeofenceMapMarker({
    super.key,
    required this.title,
    required this.iconType,
  });

  IconData _resolveIcon() {
    switch (iconType) {
      case 'home':
        return Icons.home_rounded;
      case 'school':
        return Icons.school_rounded;
      case 'sport':
        return Icons.sports_soccer_rounded;
      default:
        return Icons.place_rounded;
    }
  }

  Color _resolveColor() {
    switch (iconType) {
      case 'home':
        return Colors.teal;
      case 'school':
        return Colors.indigo;
      case 'sport':
        return Colors.orange.shade700;
      default:
        return Colors.deepPurple;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _resolveColor();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(_resolveIcon(), color: Colors.white, size: 16),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}