import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/widgets/buttons/app_button.dart';
import '../../../core/widgets/inputs/app_text_field.dart';
import '../../profile/data/profile_repository.dart';
import '../data/support_repository.dart';

class ContactUsScreen extends ConsumerStatefulWidget {
  const ContactUsScreen({super.key});

  @override
  ConsumerState<ContactUsScreen> createState() => _ContactUsScreenState();
}

class _ContactUsScreenState extends ConsumerState<ContactUsScreen> {
  final _nameController = TextEditingController();
  final _orderIdController = TextEditingController();
  final _phoneController = TextEditingController();
  final _messageController = TextEditingController();
  bool _isSubmitted = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final profile = ref.read(userProfileProvider).value;
      if (profile != null && mounted) {
        if (_nameController.text.isEmpty && profile.fullName.isNotEmpty) {
          _nameController.text = profile.fullName;
        }
        if (_phoneController.text.isEmpty && profile.phone != null) {
          _phoneController.text = profile.phone!;
        }
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _orderIdController.dispose();
    _phoneController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final name = _nameController.text.trim();
    final message = _messageController.text.trim();
    final orderId = _orderIdController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter your name.')));
      return;
    }
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your support message.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final repo = ref.read(supportRepositoryProvider);
      await repo.submitContactMessage(
        name: name,
        phone: phone.isNotEmpty ? phone : null,
        subject: orderId.isNotEmpty
            ? 'Order Inquiry: $orderId'
            : 'General Butchery Inquiry',
        message: message,
      );
      if (mounted) {
        setState(() {
          _isSubmitted = true;
          _isSubmitting = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit message: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
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
                      color: Color(0xFF25D366),
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
                            children: [
                              Text(
                                'Chat Now',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1B5E20),
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 12,
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
              padding: const EdgeInsets.all(AppDimensions.lg),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: AppDimensions.roundedMd,
                border: Border.all(color: AppColors.surfaceBorder),
              ),
              child: const Column(
                children: [
                  _ContactRow(
                    icon: Icons.phone_in_talk_rounded,
                    title: 'Helpline Number',
                    subtitle: '1800-419-MEAT (Toll Free, 6 AM - 10 PM)',
                  ),
                  Divider(height: AppDimensions.lg),
                  _ContactRow(
                    icon: Icons.email_outlined,
                    title: 'Email Inquiries',
                    subtitle: 'care@freshmarket.in (24hr response)',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.xl),

            // Grievance / In-App Message Form
            const Text(
              'Submit a Support Grievance',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppDimensions.xs),
            const Text(
              'Have an issue with meat freshness, packaging, or butchery precision? Fill in the details below.',
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
                      'Your message has been logged in our support registry. Our butchery team will get back to you shortly.',
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
                      controller: _phoneController,
                      label: 'Phone Number (Optional)',
                      hint: '+91 98765 43210',
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
                      label: _isSubmitting ? 'Submitting...' : 'Submit Message',
                      width: double.infinity,
                      isLoading: _isSubmitting,
                      onPressed: _isSubmitting ? null : _handleSubmit,
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
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: AppDimensions.roundedSm,
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
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
