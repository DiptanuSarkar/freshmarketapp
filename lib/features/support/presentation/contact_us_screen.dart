import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/widgets/buttons/app_button.dart';
import '../../../core/widgets/inputs/app_text_field.dart';

class ContactUsScreen extends StatefulWidget {
  const ContactUsScreen({super.key});

  @override
  State<ContactUsScreen> createState() => _ContactUsScreenState();
}

class _ContactUsScreenState extends State<ContactUsScreen> {
  final _nameController = TextEditingController();
  final _orderIdController = TextEditingController();
  final _messageController = TextEditingController();
  bool _isSubmitted = false;

  @override
  void dispose() {
    _nameController.dispose();
    _orderIdController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    if (_nameController.text.isNotEmpty && _messageController.text.isNotEmpty) {
      setState(() => _isSubmitted = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Customer Care & Support')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimensions.lg),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // WhatsApp Support Direct Banner
            Container(
              padding: const EdgeInsets.all(AppDimensions.lg),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: AppDimensions.roundedMd,
                border: Border.all(color: const Color(0xFFC8E6C9)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      color: Color(0xFF25D366), // WhatsApp Green
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.chat_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: AppDimensions.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'WhatsApp Butchery Support',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1B5E20),
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Click to chat with our butchery care team for instant order status or cut customization.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF2E7D32),
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'WhatsApp click-to-chat ready with support number +91 98765 00000',
                                ),
                                backgroundColor: Color(0xFF2E7D32),
                              ),
                            );
                          },
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Open WhatsApp Chat',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1B5E20),
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 14,
                                color: Color(0xFF1B5E20),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.lg),

            // Quick Contact Numbers
            Container(
              padding: const EdgeInsets.all(AppDimensions.md),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppDimensions.roundedMd,
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: const Column(
                children: [
                  _ContactRow(
                    icon: Icons.phone_outlined,
                    title: 'Customer Hotline',
                    value: '+91 80 4712 9900 (Toll Free)',
                    subtitle: '6:00 AM - 10:00 PM (All 7 Days)',
                  ),
                  Divider(height: 16),
                  _ContactRow(
                    icon: Icons.email_outlined,
                    title: 'Care Email',
                    value: 'care@freshmarket.app',
                    subtitle: 'Guaranteed response within 4 hours',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.xl),

            // Feedback / Inquiry Form
            const Text(
              'Send us a Message',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppDimensions.xs),
            const Text(
              'Have custom cut requests, packaging feedback, or questions? Write to us below.',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppDimensions.md),

            if (_isSubmitted)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppDimensions.lg),
                decoration: BoxDecoration(
                  color: AppColors.successContainer,
                  borderRadius: AppDimensions.roundedMd,
                ),
                child: const Column(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.success,
                      size: 36,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Thank You!',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.success,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Your message has been logged with our customer success team.',
                      style: TextStyle(fontSize: 12, color: AppColors.success),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(AppDimensions.md),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppDimensions.roundedMd,
                  border: Border.all(color: AppColors.surfaceBorder),
                ),
                child: Column(
                  children: [
                    AppTextField(
                      controller: _nameController,
                      label: 'Your Name',
                      hint: 'Enter your name',
                    ),
                    const SizedBox(height: AppDimensions.sm),
                    AppTextField(
                      controller: _orderIdController,
                      label: 'Order ID (Optional)',
                      hint: 'e.g. FM-2026-9041',
                    ),
                    const SizedBox(height: AppDimensions.sm),
                    AppTextField(
                      controller: _messageController,
                      label: 'Message / Grievance',
                      hint: 'Describe your request or feedback in detail...',
                      maxLines: 4,
                    ),
                    const SizedBox(height: AppDimensions.md),
                    AppButton(
                      label: 'Submit Message',
                      width: double.infinity,
                      onPressed: _handleSubmit,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppDimensions.xxxl),
          ],
        ),
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            color: AppColors.surfaceSubtle,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: AppColors.primary, size: 20),
        ),
        const SizedBox(width: AppDimensions.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
