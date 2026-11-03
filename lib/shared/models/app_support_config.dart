import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_colors.dart';

class AppSupportConfig {
  const AppSupportConfig({
    required this.whatsappNumber,
    required this.supportPhone,
    required this.supportEmail,
    required this.businessHours,
    required this.helpDeskTitle,
  });

  final String whatsappNumber;
  final String supportPhone;
  final String supportEmail;
  final String businessHours;
  final String helpDeskTitle;

  static const AppSupportConfig defaults = AppSupportConfig(
    whatsappNumber: '918787630683',
    supportPhone: '+91 8787630683',
    supportEmail: 'care@freshmarket.in',
    businessHours: '6:00 AM - 10:00 PM (Daily)',
    helpDeskTitle: 'FreshMarket Butchery Care',
  );

  factory AppSupportConfig.fromJson(Map<String, dynamic> json) {
    return AppSupportConfig(
      whatsappNumber:
          (json['whatsapp_number'] as String?)?.trim() ??
          defaults.whatsappNumber,
      supportPhone:
          (json['support_phone'] as String?)?.trim() ?? defaults.supportPhone,
      supportEmail:
          (json['support_email'] as String?)?.trim() ?? defaults.supportEmail,
      businessHours:
          (json['business_hours'] as String?)?.trim() ?? defaults.businessHours,
      helpDeskTitle:
          (json['help_desk_title'] as String?)?.trim() ??
          defaults.helpDeskTitle,
    );
  }

  Map<String, dynamic> toJson() => {
    'whatsapp_number': whatsappNumber,
    'support_phone': supportPhone,
    'support_email': supportEmail,
    'business_hours': businessHours,
    'help_desk_title': helpDeskTitle,
  };

  /// Constructs official wa.me Click-to-Chat URL with URL-encoded prefilled text.
  Uri buildWhatsAppUri([String? prefilledMessage]) {
    final cleanDigits = whatsappNumber.replaceAll(RegExp(r'\D'), '');
    final textParam =
        prefilledMessage != null && prefilledMessage.trim().isNotEmpty
        ? '?text=${Uri.encodeComponent(prefilledMessage.trim())}'
        : '';
    return Uri.parse('https://wa.me/$cleanDigits$textParam');
  }

  /// Launches official WhatsApp Click-to-Chat with graceful fallbacks.
  Future<bool> launchWhatsApp(
    BuildContext context, [
    String? prefilledMessage,
  ]) async {
    final uri = buildWhatsAppUri(prefilledMessage);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        // Fallback to in-app or browser
        final fallback = await launchUrl(uri, mode: LaunchMode.platformDefault);
        if (!fallback && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Could not open WhatsApp. Chat link: https://wa.me/${whatsappNumber.replaceAll(RegExp(r"\D"), "")}',
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return fallback;
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open WhatsApp: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return false;
    }
  }

  Uri get phoneUri {
    final cleanPhone = supportPhone.replaceAll(RegExp(r'[\s-]'), '');
    return Uri.parse('tel:$cleanPhone');
  }

  Uri buildEmailUri([String? subject]) {
    final subjParam = subject != null
        ? '?subject=${Uri.encodeComponent(subject)}'
        : '';
    return Uri.parse('mailto:$supportEmail$subjParam');
  }

  Uri get emailUri => buildEmailUri();

  /// Launches dialer for customer care helpline.
  Future<bool> launchPhone(BuildContext context) async {
    final uri = phoneUri;
    try {
      return await launchUrl(uri);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Helpline number: $supportPhone'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
      return false;
    }
  }

  /// Launches email composer for customer care inquiries.
  Future<bool> launchEmail(BuildContext context, [String? subject]) async {
    final uri = buildEmailUri(subject);
    try {
      return await launchUrl(uri);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Care email: $supportEmail'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
      return false;
    }
  }
}
