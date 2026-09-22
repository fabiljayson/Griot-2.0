import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/navigation/app_router.dart';
import 'core/offline/offline_provider.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/widgets/auth_wrapper.dart';
import 'features/audio/widgets/audio_player_sheet.dart';
import 'core/navigation/main_shell.dart';

/// Root of the Griot AI application.
class GriotAiApp extends ConsumerWidget {
  const GriotAiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OfflineProvider(
      child: MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        // Shared with deep-link handling so an incoming link can route without
        // a BuildContext (see AppRouter).
        navigatorKey: AppRouter.navigatorKey,
        theme: AppTheme.light,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('fr')],
        // Auth-aware home: shows login if unauthenticated, otherwise main shell with bottom nav.
        home: const AuthWrapper(child: MainShell()),
        // Persistent sticky audio player overlays every screen while a
        // narration is generating/playing. It renders a zero-size box when
        // idle, so this stack stays visually transparent otherwise.
        builder: (context, child) =>
            Stack(children: [?child, const AudioPlayerSheet()]),
      ),
    );
  }
}
