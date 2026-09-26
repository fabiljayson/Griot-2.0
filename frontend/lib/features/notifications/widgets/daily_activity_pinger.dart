import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/device_timezone.dart';
import '../../gamification/providers/gamification_provider.dart';
import '../../auth/providers/auth_provider.dart';

/// Logs the reader in as active for today, on launch and on every resume.
///
/// Any activity keeps a streak alive, so simply opening the app has to count:
/// a reader who browses but reads nothing is still present, and the streak is
/// the reward for turning up. The server dedupes by the reader's local calendar
/// day, so pinging on every resume costs one small request and cannot inflate a
/// streak.
///
/// Sits above the navigator so a resume is caught even when no screen is being
/// built. Renders nothing.
class DailyActivityPinger extends ConsumerStatefulWidget {
  const DailyActivityPinger({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<DailyActivityPinger> createState() =>
      _DailyActivityPingerState();
}

class _DailyActivityPingerState extends ConsumerState<DailyActivityPinger>
    with WidgetsBindingObserver {
  /// Resumes can arrive in bursts (unlock, app switch, notification tap), and
  /// the call is idempotent, but there is no reason to spend a request on each
  /// one.
  static const _minGap = Duration(minutes: 30);

  DateTime? _lastPing;
  bool _inFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_ping());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Covers sign-in and cold start: the first frame after the reader becomes
    // authenticated is the moment to count the day.
    final authenticated = ref.read(authProvider).value?.isAuthenticated ?? false;
    if (authenticated) unawaited(_ping());
  }

  Future<void> _ping() async {
    if (_inFlight) return;
    if (!(ref.read(authProvider).value?.isAuthenticated ?? false)) return;

    final now = DateTime.now();
    final last = _lastPing;
    if (last != null && now.difference(last) < _minGap) return;
    _lastPing = now;
    _inFlight = true;

    try {
      final service = ref.read(gamificationApiServiceProvider);
      await service.recordActivity(timezone: await DeviceTimezone.current());

      // The ping is what makes today count, so anything already on screen is
      // now showing a stale streak and an out-of-date unread badge.
      ref.invalidate(gamificationProfileProvider);
    } catch (_) {
      // Streaks and badges are decoration on the way past. A failed ping must
      // never interrupt reading, and the next resume tries again.
      _lastPing = null;
    } finally {
      _inFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
