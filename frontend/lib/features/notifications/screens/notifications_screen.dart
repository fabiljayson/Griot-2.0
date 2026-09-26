import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_spacing.dart';
import '../../stories/screens/story_detail_screen.dart';
import '../models/notification_model.dart';
import '../providers/notification_provider.dart';

/// The reader's inbox.
///
/// Reads newest first from the API with no offline fallback: a message is only
/// worth showing if the server actually sent it.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          // Only offered when there is something to clear, so the bar does not
          // carry a dead control.
          if (inbox.value?.unreadCount != null &&
              inbox.value!.unreadCount > 0)
            TextButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await ref
                      .read(notificationsProvider.notifier)
                      .markAllRead();
                } catch (_) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Could not clear your notifications.'),
                    ),
                  );
                }
              },
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(notificationsProvider.notifier).refresh(),
        child: switch (inbox) {
          AsyncValue(:final error?) => _ErrorView(
            message: '$error',
            onRetry: () => ref.invalidate(notificationsProvider),
          ),
          AsyncValue(hasValue: false, :final isLoading) when isLoading =>
            const Center(child: CircularProgressIndicator()),
          AsyncValue(value: final inbox?) when inbox.notifications.isEmpty =>
            const _EmptyView(),
          AsyncValue(value: final inbox?) => _InboxList(
            notifications: inbox.notifications,
            onOpen: (message) => _open(context, ref, message),
          ),
          _ => const _EmptyView(),
        },
      ),
    );
  }

  /// Mark the message read, then follow its story link.
  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    NotificationModel message,
  ) async {
    final notifier = ref.read(notificationsProvider.notifier);
    try {
      await notifier.markRead(message.id);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not mark that as read.')),
      );
      return;
    }

    if (!context.mounted) return;
    final slug = message.storySlug;
    if (slug.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StoryDetailScreen(slug: slug)),
    );
  }
}

class _InboxList extends StatelessWidget {
  const _InboxList({required this.notifications, required this.onOpen});

  final List<NotificationModel> notifications;
  final ValueChanged<NotificationModel> onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      // AlwaysScrollable so pull-to-refresh works even on a short inbox.
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: notifications.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final message = notifications[index];
        return _NotificationTile(
          message: message,
          showDayHeader: _startsNewDay(message, notifications, index),
          onTap: () => onOpen(message),
        );
      },
    );
  }

  /// True when this message belongs to a later day than the one above it.
  static bool _startsNewDay(
    NotificationModel message,
    List<NotificationModel> all,
    int index,
  ) {
    if (index == 0) return false;
    final previous = all[index - 1].createdAt;
    final today = message.createdAt;
    return previous.year != today.year ||
        previous.month != today.month ||
        previous.day != today.day;
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.message,
    required this.onTap,
    this.showDayHeader = false,
  });

  final NotificationModel message;
  final VoidCallback onTap;
  final bool showDayHeader;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDayHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Text(
              _dayLabel(message.createdAt),
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.muted,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ListTile(
          onTap: onTap,
          leading: _KindIcon(kind: message.kind, isRead: message.isRead),
          title: Text(
            message.title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: message.isRead ? FontWeight.w400 : FontWeight.w700,
            ),
          ),
          subtitle: message.body.isEmpty
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    message.body,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ),
          trailing: message.isRead
              ? null
              : Semantics(
                  label: 'Unread',
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.earth,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  /// "Today", "Yesterday", or a date, so the reader can place a message.
  static String _dayLabel(DateTime when) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(when.year, when.month, when.day);
    final difference = today.difference(day).inDays;
    if (difference == 0) return 'TODAY';
    if (difference == 1) return 'YESTERDAY';
    return '${day.day.toString().padLeft(2, '0')}'
        '/${day.month.toString().padLeft(2, '0')}/${day.year}';
  }
}

/// Leading glyph for the message kind.
///
/// The icon carries the meaning as well as the colour, so the row is still
/// readable without colour.
class _KindIcon extends StatelessWidget {
  const _KindIcon({required this.kind, required this.isRead});

  final String kind;
  final bool isRead;

  @override
  Widget build(BuildContext context) {
    final (icon, tint) = switch (kind) {
      NotificationKind.newStory => (AppIcons.auto_stories, AppColors.earth),
      NotificationKind.trending => (AppIcons.trending_up, AppColors.bronze),
      NotificationKind.streak => (AppIcons.fire, AppColors.bronzeDark),
      NotificationKind.badge => (AppIcons.emoji_events_outlined, AppColors.bronze),
      NotificationKind.announcement => (AppIcons.campaign, AppColors.indigo),
      _ => (AppIcons.info_outline, AppColors.muted),
    };

    return Container(
      width: AppSizes.navActionSize - AppSpacing.md,
      height: AppSizes.navActionSize - AppSpacing.md,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: isRead ? 0.08 : 0.16),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Icon(icon, size: 20, color: isRead ? AppColors.muted : tint),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: AppSpacing.sectionLarge),
        Icon(
          AppIcons.notifications_none,
          size: 48,
          color: AppColors.muted,
        ),
        SizedBox(height: AppSpacing.lg),
        Center(
          child: Text(
            'Nothing new yet',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        SizedBox(height: AppSpacing.sm),
        Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.section),
            child: Text(
              'New stories and this week\'s most-read tales will show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: AppSpacing.sectionLarge),
        const Icon(AppIcons.wifi_off, size: 40, color: AppColors.muted),
        const SizedBox(height: AppSpacing.lg),
        Center(
          child: Text(
            'Could not load your notifications',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Center(child: OutlinedButton(onPressed: onRetry, child: const Text('Retry'))),
      ],
    );
  }
}
