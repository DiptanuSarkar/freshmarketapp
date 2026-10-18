import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/widgets/buttons/app_button.dart';
import '../../../core/widgets/feedback/app_empty_state.dart';
import '../../../core/widgets/feedback/app_loading_indicator.dart';
import '../../../shared/providers/address_provider.dart';
import '../../../shared/providers/cart_provider.dart';
import '../../orders/data/orders_repository.dart';
import '../../payment/presentation/providers/razorpay_controller.dart';
import '../data/checkout_quote_model.dart';
import '../data/checkout_repository.dart';
import '../data/delivery_repository.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  String? _selectedSlotId;
  String _selectedPaymentMethod = 'cod';
  bool _useWallet = false;
  final _couponController = TextEditingController();
  final _notesController = TextEditingController();
  String? _appliedCouponCode;
  String? _currentCheckoutRequestId;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _couponController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _applyCoupon() {
    final code = _couponController.text.trim().toUpperCase();
    if (code.isEmpty) return;
    setState(() {
      _appliedCouponCode = code;
    });
  }

  void _removeCoupon() {
    setState(() {
      _appliedCouponCode = null;
      _couponController.clear();
    });
  }

  Future<void> _handlePlaceOrder({
    required String addressId,
    required String slotId,
  }) async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      // Retain existing idempotency UUID if retrying, or generate a fresh one
      _currentCheckoutRequestId ??= generateUuidV4();
    });

    try {
      final order = await ref
          .read(checkoutRepositoryProvider)
          .createCodOrder(
            checkoutRequestId: _currentCheckoutRequestId!,
            addressId: addressId,
            deliverySlotId: slotId,
            couponCode: _appliedCouponCode,
            customerNotes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );

      if (!mounted) return;

      // Order created successfully: reset idempotency key, clear local cart state, refresh orders
      _currentCheckoutRequestId = null;
      ref.read(cartProvider.notifier).clearCart();
      ref.invalidate(customerOrdersProvider);

      context.go('${AppRoutes.orderSuccessPrefix}/${order.id}');
    } on CheckoutException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);

      // If cart empty or out of stock, refresh cart from server
      if (e.code == 'OUT_OF_STOCK' || e.code == 'EMPTY_CART') {
        ref.invalidate(cartProvider);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Order submission failed. Please check your network and retry.',
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handlePayWallet({
    required String addressId,
    required String slotId,
  }) async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _currentCheckoutRequestId ??= generateUuidV4();
    });

    try {
      final order = await ref
          .read(checkoutRepositoryProvider)
          .createWalletPaymentOrder(
            checkoutRequestId: _currentCheckoutRequestId!,
            addressId: addressId,
            deliverySlotId: slotId,
            couponCode: _appliedCouponCode,
            customerNotes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );

      if (!mounted) return;

      _currentCheckoutRequestId = null;
      ref.read(cartProvider.notifier).clearCart();
      ref.invalidate(customerOrdersProvider);

      context.go('${AppRoutes.orderSuccessPrefix}/${order.id}');
    } on CheckoutException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);

      if (e.code == 'OUT_OF_STOCK' || e.code == 'EMPTY_CART') {
        ref.invalidate(cartProvider);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Wallet payment failed: $err'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handlePayOnline({
    required String addressId,
    required String slotId,
    bool useWallet = false,
  }) async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _currentCheckoutRequestId ??= generateUuidV4();
    });

    try {
      await ref
          .read(razorpayControllerProvider.notifier)
          .startCheckout(
            checkoutRequestId: _currentCheckoutRequestId!,
            addressId: addressId,
            deliverySlotId: slotId,
            couponCode: _appliedCouponCode,
            customerNotes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
            useWallet: useWallet,
          );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppColors.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cartState = ref.watch(cartProvider);
    final selectedAddress = ref.watch(selectedAddressProvider);
    final slotsAsync = ref.watch(deliverySlotsProvider);

    if (cartState.isEmpty) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('Checkout')),
        body: AppEmptyState(
          title: 'Your cart is empty',
          message:
              'Add freshly cut meats from our butcher counter before checkout.',
          icon: Icons.shopping_bag_outlined,
          actionLabel: 'Browse Meats',
          onAction: () => context.go(AppRoutes.home),
        ),
      );
    }

    final serviceAreaAsync = selectedAddress != null
        ? ref.watch(serviceAreaByPincodeProvider(selectedAddress.pincode))
        : null;

    final isServiceable = serviceAreaAsync?.value != null;
    final isCheckingServiceability = serviceAreaAsync?.isLoading ?? false;

    // Server Authoritative Quote
    final quoteAsync = ref.watch(
      checkoutQuoteProvider(
        CheckoutQuoteParams(
          addressId: selectedAddress?.id,
          deliverySlotId: _selectedSlotId,
          couponCode: _appliedCouponCode,
          useWallet: _useWallet,
        ),
      ),
    );

    // Listen to Razorpay gateway events and server verification
    ref.listen<RazorpayCheckoutState>(razorpayControllerProvider, (
      previous,
      next,
    ) {
      if (next is RazorpayStateVerifying) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
                SizedBox(width: 12),
                Text('Verifying payment with butchery...'),
              ],
            ),
            backgroundColor: AppColors.primary,
            duration: Duration(seconds: 30),
          ),
        );
      } else if (next is RazorpayStateSuccess) {
        _currentCheckoutRequestId = null;
        ref.read(cartProvider.notifier).clearCart();
        ref.invalidate(customerOrdersProvider);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        context.go(
          '${AppRoutes.orderSuccessPrefix}/${next.result.internalOrderId}',
        );
      } else if (next is RazorpayStateFailed) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.message),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            action: next.orderId != null
                ? SnackBarAction(
                    label: 'Check Status',
                    textColor: Colors.white,
                    onPressed: () async {
                      final router = GoRouter.of(context);
                      final res = await ref
                          .read(razorpayControllerProvider.notifier)
                          .checkStatus(orderId: next.orderId!);
                      if (res.isOrderConfirmed && mounted) {
                        router.go(
                          '${AppRoutes.orderSuccessPrefix}/${next.orderId}',
                        );
                      }
                    },
                  )
                : null,
          ),
        );
      } else if (next is RazorpayStateCancelled) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment cancelled. Your items remain in cart.'),
            backgroundColor: AppColors.textSecondary,
            duration: Duration(seconds: 3),
          ),
        );
      }
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Checkout')),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppDimensions.lg),
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Step 1: Delivery Address
                      _buildSectionCard(
                        title: '1. Delivery Address',
                        actionLabel: selectedAddress != null ? 'Change' : 'Add',
                        onAction: () => context.push(AppRoutes.addresses),
                        content: selectedAddress == null
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'No delivery address selected.',
                                    style: TextStyle(
                                      color: AppColors.error,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  AppButton(
                                    label: 'Select or Add Address',
                                    variant: AppButtonVariant.outline,
                                    height: 36,
                                    onPressed: () =>
                                        context.push(AppRoutes.addresses),
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: const BoxDecoration(
                                          color: AppColors.primaryContainer,
                                          borderRadius:
                                              AppDimensions.roundedPill,
                                        ),
                                        child: Text(
                                          selectedAddress.tag.toUpperCase(),
                                          style: const TextStyle(
                                            color: AppColors.primaryDark,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: AppDimensions.sm),
                                      Text(
                                        selectedAddress.recipientName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        ' • ${selectedAddress.phone}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (selectedAddress.isMapVerified)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.success.withValues(
                                              alpha: 0.12,
                                            ),
                                            borderRadius:
                                                AppDimensions.roundedPill,
                                            border: Border.all(
                                              color: AppColors.success
                                                  .withValues(alpha: 0.3),
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: const [
                                              Icon(
                                                Icons.check_circle_rounded,
                                                size: 10,
                                                color: AppColors.success,
                                              ),
                                              SizedBox(width: 3),
                                              Text(
                                                'VERIFIED ON MAP',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w800,
                                                  color: AppColors.success,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    selectedAddress.formattedAddress,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary,
                                      height: 1.3,
                                    ),
                                  ),
                                  if (!selectedAddress.isMapVerified) ...[
                                    const SizedBox(height: 6),
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppColors.warning.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: AppDimensions.roundedSm,
                                        border: Border.all(
                                          color: AppColors.warning.withValues(
                                            alpha: 0.35,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.location_off_rounded,
                                            size: 16,
                                            color: AppColors.warning,
                                          ),
                                          const SizedBox(width: 8),
                                          const Expanded(
                                            child: Text(
                                              'Pin not verified on map. Pinpoint doorstep for delivery.',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.textPrimary,
                                              ),
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () => context.push(
                                              '${AppRoutes.editAddressPrefix}/${selectedAddress.id}/edit',
                                            ),
                                            style: TextButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                  ),
                                              minimumSize: Size.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                            ),
                                            child: const Text(
                                              'Verify on Map',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 8),

                                  // Serviceability Status Banner
                                  if (isCheckingServiceability)
                                    const Row(
                                      children: [
                                        SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Checking PIN code serviceability...',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    )
                                  else if (!isServiceable)
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppColors.errorContainer,
                                        borderRadius: AppDimensions.roundedSm,
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.error_outline_rounded,
                                            color: AppColors.error,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'FreshMarket does not deliver to PIN code ${selectedAddress.pincode} yet.',
                                              style: const TextStyle(
                                                color: AppColors.error,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.successContainer,
                                        borderRadius: AppDimensions.roundedSm,
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.check_circle_outline_rounded,
                                            color: AppColors.success,
                                            size: 14,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'Serviceable (${serviceAreaAsync?.value?.areaName ?? 'Bengaluru'}) • Free delivery on orders over ₹${serviceAreaAsync?.value?.minOrderForFreeDelivery.toInt() ?? 499}',
                                              style: const TextStyle(
                                                color: AppColors.success,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                      ),
                      const SizedBox(height: AppDimensions.md),

                      // Step 2: Delivery Slot Picker (Supabase delivery_slots)
                      _buildSectionCard(
                        title: '2. Select Delivery Slot',
                        content: slotsAsync.when(
                          loading: () => const Center(
                            child: AppLoadingIndicator(
                              message: 'Loading delivery slots...',
                            ),
                          ),
                          error: (_, _) => const Text(
                            'Standard Next Slot (60-90 mins)',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          data: (slots) {
                            if (slots.isEmpty) {
                              return const Text(
                                'Standard Butchery Delivery (within 120 mins)',
                                style: TextStyle(fontSize: 12),
                              );
                            }

                            _selectedSlotId ??= slots.first.id;

                            return Column(
                              children: slots.map((slot) {
                                final isSelected = slot.id == _selectedSlotId;
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  leading: Icon(
                                    isSelected
                                        ? Icons.radio_button_checked_rounded
                                        : Icons.radio_button_off_rounded,
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.textTertiary,
                                    size: 20,
                                  ),
                                  title: Text(
                                    '${slot.name} (${slot.startTime} - ${slot.endTime})',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.w500,
                                      color: isSelected
                                          ? AppColors.textPrimary
                                          : AppColors.textSecondary,
                                    ),
                                  ),
                                  onTap: () {
                                    setState(() => _selectedSlotId = slot.id);
                                  },
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: AppDimensions.md),

                      // Step 3: Payment Method
                      _buildSectionCard(
                        title: '3. Payment Method',
                        content: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Wallet Toggle
                            _buildWalletOption(quoteAsync),
                            const SizedBox(height: AppDimensions.sm),

                            if (_useWallet &&
                                quoteAsync.value?.isWalletOnly == true)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(AppDimensions.md),
                                decoration: BoxDecoration(
                                  color: AppColors.successContainer,
                                  borderRadius: AppDimensions.roundedSm,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: AppColors.success,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '100% of this order is covered by your wallet balance (${AppStrings.currencySymbol}${quoteAsync.value?.grandTotal.toStringAsFixed(0) ?? ''}). No gateway payment required!',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.success,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else ...[
                              RadioGroup<String>(
                                groupValue: _selectedPaymentMethod,
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(
                                      () => _selectedPaymentMethod = val,
                                    );
                                  }
                                },
                                child: Column(
                                  children: [
                                    // Cash on Delivery
                                    Opacity(
                                      opacity: _useWallet ? 0.4 : 1.0,
                                      child: ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        dense: true,
                                        leading: const Radio<String>(
                                          value: 'cod',
                                          activeColor: AppColors.primary,
                                        ),
                                        title: const Row(
                                          children: [
                                            Icon(
                                              Icons.payments_outlined,
                                              size: 18,
                                              color: AppColors.textSecondary,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              'Cash on Delivery (COD)',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                        subtitle: Text(
                                          _useWallet
                                              ? 'Mixed payments require online payment'
                                              : 'Pay with cash or UPI QR code at your doorstep',
                                          style: const TextStyle(fontSize: 11),
                                        ),
                                        onTap: _useWallet
                                            ? null
                                            : () => setState(
                                                () => _selectedPaymentMethod =
                                                    'cod',
                                              ),
                                      ),
                                    ),
                                    const Divider(height: 1),

                                    // Online Payment (Razorpay)
                                    ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      dense: true,
                                      leading: const Radio<String>(
                                        value: 'razorpay',
                                        activeColor: AppColors.primary,
                                      ),
                                      title: Wrap(
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const Icon(
                                                Icons.payment_rounded,
                                                size: 18,
                                                color: AppColors.primary,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                _useWallet
                                                    ? 'Online Payment (Mixed Razorpay)'
                                                    : 'Online Payment (Razorpay)',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 13,
                                                  color: AppColors.textPrimary,
                                                ),
                                              ),
                                            ],
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 1,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.primaryContainer,
                                              borderRadius:
                                                  AppDimensions.roundedPill,
                                            ),
                                            child: const Text(
                                              'UPI / Card / Netbanking',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.primaryDark,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      subtitle: Text(
                                        _useWallet
                                            ? 'Pay remaining balance of ₹${quoteAsync.value?.gatewayPayable.toStringAsFixed(0) ?? '0'} securely online'
                                            : 'Pay securely with UPI, Credit/Debit Cards, or Netbanking',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      onTap: () => setState(
                                        () =>
                                            _selectedPaymentMethod = 'razorpay',
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: AppDimensions.md),

                      // Step 4: Promo & Coupons
                      _buildSectionCard(
                        title: '4. Apply Coupon',
                        content: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_appliedCouponCode == null)
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _couponController,
                                      textCapitalization:
                                          TextCapitalization.characters,
                                      decoration: const InputDecoration(
                                        hintText: 'Enter coupon code (e.g. WELCOME100)',
                                        isDense: true,
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 80,
                                    height: 40,
                                    child: ElevatedButton(
                                      onPressed: _applyCoupon,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                        ),
                                      ),
                                      child: const Text(
                                        'Apply',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.successContainer,
                                  borderRadius: AppDimensions.roundedSm,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.local_offer_outlined,
                                          color: AppColors.success,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          _appliedCouponCode!,
                                          style: const TextStyle(
                                            color: AppColors.success,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                    InkWell(
                                      onTap: _removeCoupon,
                                      child: const Text(
                                        'REMOVE',
                                        style: TextStyle(
                                          color: AppColors.error,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            // Coupon status message from quote
                            quoteAsync.when(
                              data: (quote) {
                                if (quote.couponMessage != null &&
                                    quote.couponMessage!.isNotEmpty) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      quote.couponMessage!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: quote.couponApplied
                                            ? AppColors.success
                                            : AppColors.error,
                                      ),
                                    ),
                                  );
                                }
                                return const SizedBox.shrink();
                              },
                              loading: () => const SizedBox.shrink(),
                              error: (_, _) => const SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppDimensions.md),

                      // Optional Customer Notes
                      _buildSectionCard(
                        title: 'Butchery Notes (Optional)',
                        content: TextField(
                          controller: _notesController,
                          maxLines: 2,
                          decoration: const InputDecoration(
                            hintText: 'Special cutting instructions, packing preferences, or delivery notes...',
                            hintStyle: TextStyle(fontSize: 12),
                            isDense: true,
                            contentPadding: EdgeInsets.all(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppDimensions.md),

                      // Bill Summary (Server Authoritative)
                      _buildBillSummaryCard(quoteAsync, cartState),
                      const SizedBox(height: AppDimensions.xxxl),
                    ],
                  ),
                ),
              ),

              // Bottom Place Order Bar
              _buildBottomPlaceOrderBar(
                quoteAsync: quoteAsync,
                cartState: cartState,
                selectedAddress: selectedAddress,
                isServiceable: isServiceable,
                slotId: _selectedSlotId,
              ),
            ],
          ),

          // Submitting Overlay
          if (_isSubmitting)
            Container(
              color: Colors.black45,
              child: const Center(
                child: AppLoadingIndicator(
                  message: 'Placing your order securely...',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBillSummaryCard(
    AsyncValue<CheckoutQuote> quoteAsync,
    CartState cartState,
  ) {
    return Container(
      padding: const EdgeInsets.all(AppDimensions.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppDimensions.roundedMd,
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: quoteAsync.when(
        loading: () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text(
                  'Computing server pricing & discounts...',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildPriceRow(
              'Item Total (Estimated)',
              '${AppStrings.currencySymbol}${cartState.subtotal.toStringAsFixed(0)}',
            ),
            _buildPriceRow(
              'Grand Total (Estimated)',
              '${AppStrings.currencySymbol}${cartState.totalPayable.toStringAsFixed(0)}',
              isBold: true,
            ),
          ],
        ),
        error: (err, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pricing update issue: $err',
              style: const TextStyle(fontSize: 11, color: AppColors.error),
            ),
            const SizedBox(height: 8),
            _buildPriceRow(
              'Local Cart Subtotal',
              '${AppStrings.currencySymbol}${cartState.subtotal.toStringAsFixed(0)}',
            ),
          ],
        ),
        data: (quote) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Authoritative Bill Summary',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppDimensions.sm),

            // Stock warning if any variant has insufficient stock
            if (!quote.stockValid)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.errorContainer,
                  borderRadius: AppDimensions.roundedSm,
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      color: AppColors.error,
                      size: 16,
                    ),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'One or more cuts in your cart just had a stock change. Please adjust your cart.',
                        style: TextStyle(
                          color: AppColors.error,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            _buildPriceRow(
              'Item Subtotal',
              '${AppStrings.currencySymbol}${quote.subtotal.toStringAsFixed(0)}',
            ),
            if (quote.itemDiscount > 0)
              _buildPriceRow(
                'Product Savings',
                '-${AppStrings.currencySymbol}${quote.itemDiscount.toStringAsFixed(0)}',
                color: AppColors.success,
              ),
            if (quote.couponDiscount > 0)
              _buildPriceRow(
                'Coupon Discount (${quote.couponCode ?? ''})',
                '-${AppStrings.currencySymbol}${quote.couponDiscount.toStringAsFixed(0)}',
                color: AppColors.success,
              ),
            _buildPriceRow(
              'Delivery Charge',
              quote.deliveryFee == 0
                  ? 'FREE'
                  : '${AppStrings.currencySymbol}${quote.deliveryFee.toStringAsFixed(0)}',
              color: quote.deliveryFee == 0 ? AppColors.success : null,
            ),
            if (_useWallet && quote.walletAmountApplied > 0)
              _buildPriceRow(
                'FreshMarket Wallet Applied',
                '-${AppStrings.currencySymbol}${quote.walletAmountApplied.toStringAsFixed(0)}',
                color: AppColors.primary,
              ),
            const Divider(height: 16),
            _buildPriceRow(
              _useWallet && quote.isWalletOnly
                  ? 'Amount Payable (Wallet Only)'
                  : (_useWallet
                        ? 'Net Online Payable'
                        : (_selectedPaymentMethod == 'cod'
                              ? 'Grand Total (Payable COD)'
                              : 'Grand Total (Online)')),
              '${AppStrings.currencySymbol}${(_useWallet ? quote.gatewayPayable : quote.grandTotal).toStringAsFixed(0)}',
              isBold: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWalletOption(AsyncValue<CheckoutQuote> quoteAsync) {
    final quote = quoteAsync.value;
    final walletBal = quote?.walletBalance ?? 0.0;
    final hasBalance = walletBal > 0;

    return Container(
      padding: const EdgeInsets.all(AppDimensions.md),
      decoration: BoxDecoration(
        color: _useWallet
            ? AppColors.primaryContainer.withValues(alpha: 0.35)
            : AppColors.surface,
        borderRadius: AppDimensions.roundedSm,
        border: Border.all(
          color: _useWallet ? AppColors.primary : AppColors.surfaceBorder,
          width: _useWallet ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.account_balance_wallet_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'FreshMarket Wallet',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '(${AppStrings.currencySymbol}${walletBal.toStringAsFixed(0)})',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  !hasBalance
                      ? 'No wallet balance available'
                      : (_useWallet
                            ? (quote?.isWalletOnly == true
                                  ? 'Covers entire bill amount'
                                  : '₹${quote?.walletAmountApplied.toStringAsFixed(0)} will be deducted')
                            : 'Use wallet balance for this order'),
                  style: TextStyle(
                    fontSize: 11,
                    color: _useWallet
                        ? AppColors.primaryDark
                        : AppColors.textSecondary,
                    fontWeight: _useWallet
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            value: _useWallet,
            activeTrackColor: AppColors.primary,
            onChanged: hasBalance
                ? (val) {
                    setState(() {
                      _useWallet = val;
                      if (val && quote?.isWalletOnly != true) {
                        _selectedPaymentMethod = 'razorpay';
                      }
                    });
                  }
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPlaceOrderBar({
    required AsyncValue<CheckoutQuote> quoteAsync,
    required CartState cartState,
    required dynamic selectedAddress,
    required bool isServiceable,
    required String? slotId,
  }) {
    final quote = quoteAsync.value;
    final grandTotalDisplay = quote?.grandTotal ?? cartState.totalPayable;
    final isStockValid = quote?.stockValid ?? true;
    final isAddressVerified =
        selectedAddress != null && selectedAddress.isMapVerified;
    final canPlaceOrder =
        cartState.items.isNotEmpty &&
        selectedAddress != null &&
        isAddressVerified &&
        isServiceable &&
        slotId != null &&
        isStockValid &&
        !_isSubmitting;

    final isWalletOnly = _useWallet && (quote?.isWalletOnly ?? false);
    final isMixed = _useWallet && !isWalletOnly;
    final isOnline = _selectedPaymentMethod == 'razorpay' || isMixed;

    String subtitle;
    String displayAmount;
    String buttonLabel;
    IconData buttonIcon;
    VoidCallback? buttonAction;

    if (_isSubmitting) {
      subtitle = 'Processing...';
      displayAmount =
          '${AppStrings.currencySymbol}${grandTotalDisplay.toStringAsFixed(0)}';
      buttonLabel = isWalletOnly
          ? 'Debiting Wallet...'
          : (isOnline ? 'Connecting Gateway...' : 'Placing Order...');
      buttonIcon = Icons.sync;
      buttonAction = null;
    } else if (selectedAddress != null && !isAddressVerified) {
      subtitle = 'Verification Required';
      displayAmount =
          '${AppStrings.currencySymbol}${grandTotalDisplay.toStringAsFixed(0)}';
      buttonLabel = 'Verify Address on Map';
      buttonIcon = Icons.pin_drop_rounded;
      buttonAction = () => context.push(
        '${AppRoutes.editAddressPrefix}/${selectedAddress.id}/edit',
      );
    } else if (isWalletOnly) {
      subtitle = 'Covered by Wallet';
      displayAmount =
          '${AppStrings.currencySymbol}${grandTotalDisplay.toStringAsFixed(0)}';
      buttonLabel = 'Pay from Wallet';
      buttonIcon = Icons.account_balance_wallet_rounded;
      buttonAction = () =>
          _handlePayWallet(addressId: selectedAddress.id, slotId: slotId!);
    } else if (isMixed) {
      final gatewayAmt = quote?.gatewayPayable ?? grandTotalDisplay;
      subtitle =
          '₹${quote?.walletAmountApplied.toStringAsFixed(0) ?? '0'} from Wallet';
      displayAmount =
          '${AppStrings.currencySymbol}${gatewayAmt.toStringAsFixed(0)}';
      buttonLabel = 'Pay ₹${gatewayAmt.toStringAsFixed(0)} Online';
      buttonIcon = Icons.payment_rounded;
      buttonAction = () => _handlePayOnline(
        addressId: selectedAddress.id,
        slotId: slotId!,
        useWallet: true,
      );
    } else if (isOnline) {
      subtitle = 'Online Amount';
      displayAmount =
          '${AppStrings.currencySymbol}${grandTotalDisplay.toStringAsFixed(0)}';
      buttonLabel =
          'Pay ${AppStrings.currencySymbol}${grandTotalDisplay.toStringAsFixed(0)}';
      buttonIcon = Icons.payment_rounded;
      buttonAction = () => _handlePayOnline(
        addressId: selectedAddress.id,
        slotId: slotId!,
        useWallet: false,
      );
    } else {
      subtitle = 'Payable on Delivery';
      displayAmount =
          '${AppStrings.currencySymbol}${grandTotalDisplay.toStringAsFixed(0)}';
      buttonLabel = 'Place COD Order';
      buttonIcon = Icons.check_circle_outline_rounded;
      buttonAction = () =>
          _handlePlaceOrder(addressId: selectedAddress.id, slotId: slotId!);
    }

    return Container(
      padding: const EdgeInsets.all(AppDimensions.lg),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          top: BorderSide(color: AppColors.surfaceBorder, width: 1),
        ),
        boxShadow: AppDimensions.cardShadow,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  displayAmount,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(width: AppDimensions.xl),
            Expanded(
              child: AppButton(
                label: buttonLabel,
                icon: buttonIcon,
                isLoading: _isSubmitting,
                onPressed: canPlaceOrder ? buttonAction : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceRow(
    String label,
    String value, {
    bool isBold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
              color: isBold ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isBold ? 14 : 12,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w700,
              color: color ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required Widget content,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppDimensions.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppDimensions.roundedMd,
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (actionLabel != null && onAction != null)
                  InkWell(
                    onTap: onAction,
                    child: Text(
                      actionLabel,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppDimensions.sm),
            content,
          ],
        ),
      ),
    );
  }
}
