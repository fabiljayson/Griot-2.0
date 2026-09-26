import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../providers/notification_provider.dart';
import '../screens/notifications_screen.dart';

/// Bell that opens the inbox, with a badge for unread messages.
///
/// The badge is hidden at zero and capped at "99+" so a wide count cannot stretch
/// the pill. The bell itself switches to its filled icon when something is
/// unread, so the state survives a greyscale or colour-blind reading of the
/// badge alone.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key, this.color = AppColors.ivory});

  /// Defaults to the ivory used on the dark home header. Pass
  /// [Theme.of(context).colorScheme.onSurface] elsewhere.
  final Color color;

  static const double size = 24;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);
    final hasUnread = unread > 0;

    return Semantics(
      button: true,
      label: hasUnread
          ? 'Notifications, $unread unread'
          : 'Notifications, none unread',
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
        ),
        // 48dp is the minimum comfortable touch target; the glyph is 24.
        child: SizedBox(
          width: AppSizes.buttonHeight,
          height: AppSizes.buttonHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Icon(
                  hasUnread ? AppIcons.notifications : AppIcons.notifications_none,
                  size: size,
                  color: color,
                ),
              ),
              if (hasUnread)
                Positioned(
                  top: AppSpacing.sm,
                  right: AppSpacing.sm,
                  child: _UnreadBadge(count: unread),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.earth,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: AppColors.black, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          height: 1,
        ),
      ),
    );
  }
}
