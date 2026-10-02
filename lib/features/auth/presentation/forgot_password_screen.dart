import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/widgets/buttons/app_button.dart';
import '../../../core/widgets/inputs/app_text_field.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailPhoneController = TextEditingController();
  bool _isSent = false;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailPhoneController.dispose();
    super.dispose();
  }

  void _handleReset() {
    setState(() => _isLoading = true);
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isSent = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Reset Password')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_isSent) ...[
                Text(
                  'Forgot your password?',
                  style: Theme.of(context).textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AppDimensions.sm),
                Text(
                  'Enter your registered email address or phone number. We\'ll send you a password recovery link or OTP.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppDimensions.xxl),

                AppTextField(
                  controller: _emailPhoneController,
                  label: 'Registered Email or Phone',
                  hint: 'e.g. name@example.com',
                  prefixIcon: const Icon(
                    Icons.mail_outline_rounded,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: AppDimensions.xl),

                AppButton(
                  label: 'Send Recovery Link',
                  onPressed: _handleReset,
                  isLoading: _isLoading,
                  width: double.infinity,
                ),
              ] else ...[
                Center(
                  child: Column(
                    children: [
                      const SizedBox(height: AppDimensions.xxxl),
                      Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          color: AppColors.successContainer,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check_rounded,
                          color: AppColors.success,
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: AppDimensions.lg),
                      Text(
                        'Recovery link sent!',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: AppDimensions.sm),
                      Text(
                        'We have dispatched instructions to your contact. Follow the link to reset your account password.',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppDimensions.xxl),
                      AppButton(
                        label: 'Back to Sign In',
                        onPressed: () => Navigator.pop(context),
                        width: 200,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
