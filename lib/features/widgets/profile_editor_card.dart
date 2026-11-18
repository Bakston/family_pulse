import 'dart:convert';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'family_calendar_widget.dart';

import 'user_avatar_widget.dart';

class ProfileEditorCard extends StatefulWidget {
  final String name;
  final String role;
  final String birthDate;
  final String login;
  final String password;
  final String pin;
  final String avatarHash;

  /// Показывать ли поле ПИН-кода (если false / отсутствует в БД — скрывается)
  final bool showPinField;
  final List<String> availableRoles;
  final String defaultDisplayName;
  final String loginSubtitleHint;

  final IconData fallbackAvatarIcon;
  final Color accentColor;
  final DateTime initialBirthDate;
  final DateTime firstBirthDate;
  final DateTime lastBirthDate;

  final bool isSaving;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onRoleChanged;
  final ValueChanged<String> onBirthDateChanged;
  final ValueChanged<String> onLoginChanged;
  final ValueChanged<String> onPasswordChanged;
  final ValueChanged<String>? onPinChanged;
  final ValueChanged<String> onAvatarChanged;
  final VoidCallback onSave;
  final VoidCallback onClose;
  final VoidCallback? onDelete;

  const ProfileEditorCard({
    super.key,
    required this.name,
    required this.role,
    required this.birthDate,
    required this.login,
    required this.password,
    this.pin = '',
    required this.avatarHash,
    this.showPinField = false,
    required this.availableRoles,
    required this.defaultDisplayName,
    this.loginSubtitleHint = 'Логин не задан',
    required this.fallbackAvatarIcon,
    required this.accentColor,
    required this.initialBirthDate,
    required this.firstBirthDate,
    required this.lastBirthDate,
    required this.isSaving,
    required this.onNameChanged,
    required this.onRoleChanged,
    required this.onBirthDateChanged,
    required this.onLoginChanged,
    required this.onPasswordChanged,
    this.onPinChanged,
    required this.onAvatarChanged,
    required this.onSave,
    required this.onClose,
    this.onDelete,
  });

  @override
  State<ProfileEditorCard> createState() => _ProfileEditorCardState();
}

class _ProfileEditorCardState extends State<ProfileEditorCard> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _pickAvatar(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 200,
        maxHeight: 200,
        imageQuality: 70,
      );

      if (image == null) return;

      final bytes = await image.readAsBytes();
      final String base64String = base64Encode(bytes);
      widget.onAvatarChanged(base64String);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось выбрать изображение: $e')),
      );
    }
  }

  void _showAvatarOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Фото профиля',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ListTile(
                dense: true,
                leading: const Icon(Icons.photo_library, color: Colors.blue),
                title: const Text('Выбрать из галереи'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickAvatar(ImageSource.gallery);
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.camera_alt, color: Colors.green),
                title: const Text('Сделать фото'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickAvatar(ImageSource.camera);
                },
              ),
              if (widget.avatarHash.isNotEmpty)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text(
                    'Удалить фото',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    widget.onAvatarChanged('');
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _editTextField({
    required String title,
    required String currentValue,
    required ValueChanged<String> onApply,
    bool isPin = false,
    bool obscure = false,
  }) {
    final controller = TextEditingController(text: currentValue);
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontSize: 18)),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: obscure,
          keyboardType: isPin ? TextInputType.number : TextInputType.text,
          inputFormatters: isPin
              ? [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ]
              : null,
          decoration: InputDecoration(
            hintText: isPin ? '4 цифры (например, 1234)' : 'Введите значение',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = controller.text.trim();
              if (isPin && val.isNotEmpty && val.length != 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('ПИН-код должен состоять из 4 цифр'),
                  ),
                );
                return;
              }
              onApply(val);
              Navigator.pop(dialogContext);
            },
            child: const Text('Готово'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  void _editRole() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Роль в семье', style: TextStyle(fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: widget.availableRoles.map((roleOption) {
            return ListTile(
              dense: true,
              title: Text(roleOption),
              trailing: widget.role == roleOption
                  ? Icon(Icons.check, color: widget.accentColor)
                  : null,
              onTap: () {
                widget.onRoleChanged(roleOption);
                Navigator.pop(dialogContext);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _editBirthDate() async {
    DateTime resolvedInitial = widget.initialBirthDate;
    final parts = widget.birthDate.split('.');
    if (parts.length == 3) {
      final d = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final y = int.tryParse(parts[2]);
      if (d != null && m != null && y != null) {
        resolvedInitial = DateTime(y, m, d);
      }
    }

    final picked = await FamilyCalendarWidget.showPickerDialog(
      context: context,
      initialDate: resolvedInitial,
      firstDate: widget.firstBirthDate,
      lastDate: widget.lastBirthDate,
      title: 'Дата рождения',
    );
    if (picked != null && mounted) {
      final d = picked.day.toString().padLeft(2, '0');
      final m = picked.month.toString().padLeft(2, '0');
      widget.onBirthDateChanged('$d.$m.${picked.year}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 38),
          padding: const EdgeInsets.fromLTRB(16, 46, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.name.isNotEmpty
                    ? widget.name
                    : widget.defaultDisplayName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.login.isNotEmpty
                    ? '${widget.role} • ${widget.login}'
                    : '${widget.role} • ${widget.loginSubtitleHint}',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),

              _buildCompactRow(
                icon: Icons.person_outline,
                title: 'Имя',
                value: widget.name.isNotEmpty ? widget.name : 'Не указано',
                onTap: () => _editTextField(
                  title: 'Изменить имя',
                  currentValue: widget.name,
                  onApply: widget.onNameChanged,
                ),
              ),
              const Divider(height: 1, indent: 38),

              _buildCompactRow(
                icon: Icons.family_restroom,
                title: 'Роль в семье',
                value: widget.role,
                onTap: _editRole,
              ),
              const Divider(height: 1, indent: 38),

              _buildCompactRow(
                icon: Icons.cake_outlined,
                title: 'Дата рождения',
                value: widget.birthDate.isNotEmpty
                    ? widget.birthDate
                    : 'Не указана',
                onTap: _editBirthDate,
              ),
              const Divider(height: 1),

              _buildCompactRow(
                icon: Icons.alternate_email,
                title: 'Логин',
                value: widget.login.isNotEmpty
                    ? widget.login
                    : 'Нажмите, чтобы задать',
                highlightEmpty: widget.login.isEmpty,
                onTap: () => _editTextField(
                  title: 'Задать логин',
                  currentValue: widget.login,
                  onApply: widget.onLoginChanged,
                ),
              ),
              const Divider(height: 1, indent: 38),

              _buildCompactRow(
                icon: Icons.lock_outline,
                title: 'Пароль',
                value: widget.password.isNotEmpty
                    ? '•' * widget.password.length
                    : 'Нажмите, чтобы задать',
                highlightEmpty: widget.password.isEmpty,
                onTap: () => _editTextField(
                  title: 'Задать пароль',
                  currentValue: widget.password,
                  obscure: true,
                  onApply: widget.onPasswordChanged,
                ),
              ),

              if (widget.showPinField) ...[
                const Divider(height: 1, indent: 38),
                _buildCompactRow(
                  icon: Icons.pin_outlined,
                  title: 'ПИН-код (4 цифры)',
                  value: widget.pin.isNotEmpty
                      ? '•••• (установлен)'
                      : 'Для быстрого входа',
                  highlightEmpty: widget.pin.isEmpty,
                  onTap: () => _editTextField(
                    title: 'Быстрый ПИН-код',
                    currentValue: widget.pin,
                    isPin: true,
                    onApply: (v) => widget.onPinChanged?.call(v),
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Полноширинная кнопка «Сохранить»
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    backgroundColor: widget.accentColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: widget.isSaving ? null : widget.onSave,
                  child: widget.isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Сохранить',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),

              // Полноширинная кнопка «Закрыть»
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(44),
                    foregroundColor: Colors.blueGrey.shade800,
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: widget.isSaving ? null : widget.onClose,
                  child: const Text(
                    'Закрыть',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Иконка удаления профиля в правом верхнем углу самой карточки
        if (widget.onDelete != null)
          Positioned(
            top: 48,
            right: 10,
            child: Material(
              color: Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: widget.isSaving ? null : widget.onDelete,
                child: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Icon(
                    Icons.delete_forever_rounded,
                    color: Colors.redAccent,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),

        // Компактный круглый аватар с кнопкой камеры
        GestureDetector(
          onTap: _showAvatarOptions,
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              UserAvatarWidget(
                avatarBase64: widget.avatarHash,
                radius: 38,
                fallbackIcon: widget.fallbackAvatarIcon,
                fallbackBackgroundColor: widget.accentColor,
                fallbackIconColor: Colors.white,
                borderWidth: 3.5,
                borderColor: Colors.white,
              ),
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: widget.accentColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(
                  Icons.camera_alt,
                  size: 14,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompactRow({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
    bool highlightEmpty = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.blueGrey.shade700),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: highlightEmpty
                          ? Colors.orange.shade800
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}