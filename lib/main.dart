import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'core/config/environment.dart';
import 'core/constants/app_colors.dart';
import 'core/constants/app_dimensions.dart';
import 'core/constants/app_strings.dart';

Future<void> _bootstrap() async {
  // Validate build-time credentials
  Environment.validate();

  // Initialize Supabase with publishable key ONLY
  await Supabase.initialize(
    url: Environment.supabaseUrl,
    publishableKey: Environment.supabasePublishableKey,
  );

  // Set system UI overlay style for transparent status bar
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const ProviderScope(child: FreshMarketApp()));
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await _bootstrap();
  } catch (error, stackTrace) {
    if (kDebugMode) {
      developer.log(
        'FreshMarket startup failed during initialization: $error',
        error: error,
        stackTrace: stackTrace,
        name: 'FreshMarketStartup',
      );
    }

    runApp(
      StartupFailureApp(
        onRetry: () async {
          try {
            await _bootstrap();
          } catch (retryError, retryStack) {
            if (kDebugMode) {
              developer.log(
                'FreshMarket retry failed: $retryError',
                error: retryError,
                stackTrace: retryStack,
                name: 'FreshMarketStartup',
              );
            }
          }
        },
      ),
    );
  }
}

class StartupFailureApp extends StatelessWidget {
  const StartupFailureApp({super.key, required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        useMaterial3: true,
      ),
      home: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppDimensions.xl),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.error_outline_rounded,
                      size: 40,
                      color: AppColors.error,
                    ),
                  ),
                  const SizedBox(height: AppDimensions.xl),
                  const Text(
                    "FreshMarket couldn't start.",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppDimensions.sm),
                  const Text(
                    'Please check your connection and configuration, then try again.',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppDimensions.xxl),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimensions.xxl,
                        vertical: AppDimensions.md,
                      ),
                    ),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
