import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/constants/app_strings.dart';
import '../core/notifications/notification_bootstrap.dart';
import '../core/theme/app_theme.dart';
import '../features/notifications/data/notifications_repository.dart';
import 'app_router.dart';

class FreshMarketApp extends ConsumerStatefulWidget {
  const FreshMarketApp({super.key});

  @override
  ConsumerState<FreshMarketApp> createState() => _FreshMarketAppState();
}

class _FreshMarketAppState extends ConsumerState<FreshMarketApp> {
  @override
  void initState() {
    super.initState();
    NotificationBootstrap.onForegroundMessageReceived = () {
      ref.invalidate(notificationsListProvider);
      ref.invalidate(unreadNotificationsCountProvider);
    };
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode:
          ThemeMode.light, // Default light as requested for fresh food branding
      routerConfig: AppRouter.router,
    );
  }
}
