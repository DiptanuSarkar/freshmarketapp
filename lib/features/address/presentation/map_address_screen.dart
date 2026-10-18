import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/location/geocoding_service.dart';
import '../../../core/location/location_exceptions.dart';
import '../../../core/location/location_service.dart';
import '../../../core/widgets/buttons/app_button.dart';
import '../../../shared/models/address.dart';
import '../../../shared/providers/address_provider.dart';
import '../../checkout/data/delivery_repository.dart';
import '../../profile/data/profile_repository.dart';
import '../data/models/selected_location.dart';

class MapAddressScreen extends ConsumerStatefulWidget {
  const MapAddressScreen({super.key, this.addressId, this.existingAddress});

  final String? addressId;
  final UserAddress? existingAddress;

  @override
  ConsumerState<MapAddressScreen> createState() => _MapAddressScreenState();
}

class _MapAddressScreenState extends ConsumerState<MapAddressScreen> {
  // Default fallback center (Bengaluru service area hub)
  static const LatLng _fallbackHub = LatLng(12.9716, 77.5946);

  GoogleMapController? _mapController;
  LatLng _cameraCenter = _fallbackHub;
  Timer? _debounceTimer;

  bool _isLocatingCurrent = false;
  bool _isResolvingGeocode = false;
  bool _isCheckingServiceability = false;
  bool _isSaving = false;

  SelectedLocation? _selectedLocation;

  // Form Controllers
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _houseController;
  late final TextEditingController _streetController;
  late final TextEditingController _landmarkController;
  late final TextEditingController _cityController;
  late final TextEditingController _stateController;
  late final TextEditingController _pincodeController;
  final _formKey = GlobalKey<FormState>();

  String _tag = 'Home';
  bool _isDefault = false;
  UserAddress? _resolvedExistingAddress;

  @override
  void initState() {
    super.initState();
    _initControllers();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeScreenData();
    });
  }

  void _initControllers() {
    _nameController = TextEditingController();
    _phoneController = TextEditingController();
    _houseController = TextEditingController();
    _streetController = TextEditingController();
    _landmarkController = TextEditingController();
    _cityController = TextEditingController();
    _stateController = TextEditingController();
    _pincodeController = TextEditingController();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _mapController?.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _houseController.dispose();
    _streetController.dispose();
    _landmarkController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _pincodeController.dispose();
    super.dispose();
  }

  void _initializeScreenData() {
    // 1. Resolve existing address if in edit mode
    if (widget.existingAddress != null) {
      _resolvedExistingAddress = widget.existingAddress;
    } else if (widget.addressId != null) {
      final list = ref.read(addressProvider);
      try {
        _resolvedExistingAddress = list.firstWhere(
          (a) => a.id == widget.addressId,
        );
      } catch (_) {
        _resolvedExistingAddress = null;
      }
    }

    // 2. Pre-fill form if editing
    if (_resolvedExistingAddress != null) {
      final addr = _resolvedExistingAddress!;
      _tag = addr.tag;
      _isDefault = addr.isDefault;
      _nameController.text = addr.recipientName;
      _phoneController.text = addr.phone;
      _houseController.text = addr.houseOrFlat;
      _streetController.text = addr.streetOrArea;
      _landmarkController.text = addr.landmark ?? '';
      _cityController.text = addr.city;
      _stateController.text = addr.state;
      _pincodeController.text = addr.pincode;

      if (addr.isMapVerified) {
        _cameraCenter = LatLng(addr.latitude!, addr.longitude!);
        _reverseGeocodeAndCheck(
          _cameraCenter.latitude,
          _cameraCenter.longitude,
        );
        _animateCamera(_cameraCenter);
        return;
      }
    } else {
      // New Address: default name and phone from user profile
      final profile = ref.read(userProfileProvider).value;
      if (profile != null) {
        if (_nameController.text.isEmpty && profile.fullName.isNotEmpty) {
          _nameController.text = profile.fullName;
        }
        final phone = profile.phone;
        if (_phoneController.text.isEmpty &&
            phone != null &&
            phone.isNotEmpty) {
          _phoneController.text = phone;
        }
      }
      _isDefault = ref.read(addressProvider).isEmpty;
    }

    // 3. For new address or unverified edit, fetch current GPS
    _fetchCurrentLocation(animate: true);
  }

  Future<void> _fetchCurrentLocation({bool animate = true}) async {
    if (_isLocatingCurrent) return;
    setState(() => _isLocatingCurrent = true);

    final locationService = ref.read(locationServiceProvider);

    try {
      // Check last known first for quick response
      final lastKnown = await locationService.getLastKnownPosition();
      if (lastKnown != null && mounted) {
        final pos = LatLng(lastKnown.latitude, lastKnown.longitude);
        _cameraCenter = pos;
        if (animate) _animateCamera(pos);
      }

      // Fetch high accuracy fresh position
      final position = await locationService.getCurrentPosition();
      if (!mounted) return;

      final target = LatLng(position.latitude, position.longitude);
      _cameraCenter = target;
      if (animate) _animateCamera(target);

      await _reverseGeocodeAndCheck(target.latitude, target.longitude);
    } on LocationServiceDisabledFailure catch (e) {
      if (!mounted) return;
      _showLocationActionSnackbar(
        message: e.message,
        actionLabel: 'Settings',
        onAction: () => locationService.openLocationSettings(),
      );
    } on LocationPermissionDeniedFailure catch (e) {
      if (!mounted) return;
      _showLocationActionSnackbar(message: e.message);
    } on LocationPermissionDeniedForeverFailure catch (e) {
      if (!mounted) return;
      _showLocationActionSnackbar(
        message: e.message,
        actionLabel: 'App Settings',
        onAction: () => locationService.openAppSettings(),
      );
    } catch (e) {
      if (!mounted) return;
      _showLocationActionSnackbar(message: 'Could not fetch GPS: $e');
    } finally {
      if (mounted) {
        setState(() => _isLocatingCurrent = false);
      }
    }
  }

  void _showLocationActionSnackbar({
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.textPrimary,
        behavior: SnackBarBehavior.floating,
        action: actionLabel != null && onAction != null
            ? SnackBarAction(
                label: actionLabel,
                textColor: AppColors.primaryLight,
                onPressed: onAction,
              )
            : null,
      ),
    );
  }

  void _animateCamera(LatLng target) {
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: 16.5),
      ),
    );
  }

  void _onCameraMove(CameraPosition position) {
    _cameraCenter = position.target;
  }

  void _onCameraIdle() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      _reverseGeocodeAndCheck(_cameraCenter.latitude, _cameraCenter.longitude);
    });
  }

  Future<void> _reverseGeocodeAndCheck(double lat, double lng) async {
    setState(() => _isResolvingGeocode = true);

    final geocodingService = ref.read(geocodingServiceProvider);
    final deliveryRepo = ref.read(deliveryRepositoryProvider);

    try {
      final geo = await geocodingService.reverseGeocode(
        latitude: lat,
        longitude: lng,
      );

      if (!mounted) return;

      // Auto-populate form fields without overwriting user-entered house/flat
      if (_streetController.text.isEmpty ||
          _streetController.text == _selectedLocation?.street ||
          _streetController.text == _selectedLocation?.area) {
        _streetController.text = geo.area.isNotEmpty ? geo.area : geo.street;
      }
      if (geo.city.isNotEmpty) _cityController.text = geo.city;
      if (geo.state.isNotEmpty) _stateController.text = geo.state;
      if (geo.postalCode.isNotEmpty) _pincodeController.text = geo.postalCode;

      // Check serviceability
      setState(() {
        _isResolvingGeocode = false;
        _isCheckingServiceability = true;
      });

      bool isServiceable = false;
      String? areaName;
      double? fee;
      double? minFree;

      if (geo.hasValidPostalCode) {
        final area = await deliveryRepo.checkServiceability(geo.postalCode);
        if (area != null) {
          isServiceable = true;
          areaName = area.name;
          fee = area.deliveryCharge;
          minFree = area.minOrderForFreeDelivery;
        }
      }

      if (!mounted) return;

      setState(() {
        _isCheckingServiceability = false;
        _selectedLocation = geo.copyWith(
          isServiceable: isServiceable,
          serviceAreaName: areaName,
          deliveryFee: fee,
          minOrderForFreeDelivery: minFree,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isResolvingGeocode = false;
        _isCheckingServiceability = false;
        _selectedLocation = SelectedLocation(
          latitude: lat,
          longitude: lng,
          errorMessage: 'Reverse geocode failed: $e',
        );
      });
    }
  }

  Future<void> _handleManualPincodeChange(String pin) async {
    final cleanPin = pin.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(cleanPin)) return;

    setState(() => _isCheckingServiceability = true);
    final deliveryRepo = ref.read(deliveryRepositoryProvider);
    final area = await deliveryRepo.checkServiceability(cleanPin);

    if (!mounted) return;
    setState(() {
      _isCheckingServiceability = false;
      if (_selectedLocation != null) {
        _selectedLocation = _selectedLocation!.copyWith(
          postalCode: cleanPin,
          isServiceable: area != null,
          serviceAreaName: area?.name,
          deliveryFee: area?.deliveryCharge,
          minOrderForFreeDelivery: area?.minOrderForFreeDelivery,
        );
      }
    });
  }

  Future<void> _handleSaveAddress() async {
    if (!_formKey.currentState!.validate()) return;

    final pin = _pincodeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid 6-digit postal PIN code.'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    if (_isCheckingServiceability || _isResolvingGeocode) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please wait while location serviceability is verified.',
          ),
        ),
      );
      return;
    }

    final isServiceable = _selectedLocation?.isServiceable ?? false;
    if (!isServiceable) {
      final shouldProceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Unsupported Delivery Location'),
          content: Text(
            'PIN code $pin is currently outside FreshMarket delivery areas. '
            'You can still save this address, but online checkout will not be available until service expands.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Change Location'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save Anyway'),
            ),
          ],
        ),
      );

      if (shouldProceed != true) return;
    }

    setState(() => _isSaving = true);

    try {
      final lat = _cameraCenter.latitude;
      final lng = _cameraCenter.longitude;

      final addressToSave = UserAddress(
        id: _resolvedExistingAddress?.id ?? '',
        tag: _tag,
        recipientName: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        houseOrFlat: _houseController.text.trim(),
        streetOrArea: _streetController.text.trim(),
        city: _cityController.text.trim().isNotEmpty
            ? _cityController.text.trim()
            : 'Bengaluru',
        state: _stateController.text.trim().isNotEmpty
            ? _stateController.text.trim()
            : 'Karnataka',
        pincode: pin,
        landmark: _landmarkController.text.trim().isEmpty
            ? null
            : _landmarkController.text.trim(),
        latitude: lat,
        longitude: lng,
        isDefault: _isDefault,
      );

      final addressNotifier = ref.read(addressProvider.notifier);

      if (_resolvedExistingAddress != null) {
        await addressNotifier.updateAddress(addressToSave);
      } else {
        await addressNotifier.addAddress(addressToSave);
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _resolvedExistingAddress != null
                ? 'Address updated with map coordinates!'
                : 'Verified address saved successfully!',
          ),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save address: $e'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = _resolvedExistingAddress != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          isEditing ? 'Edit Delivery Address' : 'Select Delivery Location',
        ),
        actions: [
          if (_isLocatingCurrent)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Upper Section: Interactive Google Map
          Expanded(
            flex: 5,
            child: Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: _cameraCenter,
                    zoom: 16.0,
                  ),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  compassEnabled: true,
                  mapToolbarEnabled: false,
                  onMapCreated: (ctrl) {
                    _mapController = ctrl;
                    if (_cameraCenter != _fallbackHub) {
                      _animateCamera(_cameraCenter);
                    }
                  },
                  onCameraMove: _onCameraMove,
                  onCameraIdle: _onCameraIdle,
                ),

                // Center Pin with Drop Shadow and Target Indicator
                Center(
                  child: IgnorePointer(
                    child: Transform.translate(
                      offset: const Offset(0, -22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.4,
                                  ),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.location_on_rounded,
                              size: 28,
                              color: Colors.white,
                            ),
                          ),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: AppColors.primaryDark,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Map Overlay: Guidance Tooltip
                Positioned(
                  top: 12,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.92),
                      borderRadius: AppDimensions.roundedPill,
                      boxShadow: AppDimensions.cardShadow,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(
                          Icons.touch_app_outlined,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Move map to position pin at your exact doorstep',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Floating Action Button: Use Current Location
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: FloatingActionButton.extended(
                    heroTag: 'map_current_loc_fab',
                    onPressed: _isLocatingCurrent
                        ? null
                        : () => _fetchCurrentLocation(animate: true),
                    backgroundColor: AppColors.surface,
                    foregroundColor: AppColors.primary,
                    icon: _isLocatingCurrent
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary,
                            ),
                          )
                        : const Icon(Icons.my_location_rounded),
                    label: Text(
                      _isLocatingCurrent
                          ? 'Locating...'
                          : 'Use Current Location',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Lower Section: Detected Location Summary & Address Form
          Expanded(
            flex: 6,
            child: Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(AppDimensions.radiusLg),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 10,
                    offset: Offset(0, -3),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppDimensions.lg),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Location Summary Card
                      _buildLocationSummaryCard(),
                      const SizedBox(height: AppDimensions.md),

                      // Tag Selector (Home / Work / Other)
                      Row(
                        children: ['Home', 'Work', 'Other'].map((t) {
                          final isSel = t == _tag;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(t.toUpperCase()),
                              selected: isSel,
                              selectedColor: AppColors.primaryContainer,
                              labelStyle: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: isSel
                                    ? AppColors.primaryDark
                                    : AppColors.textSecondary,
                              ),
                              onSelected: (_) => setState(() => _tag = t),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: AppDimensions.md),

                      // Recipient Name
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Recipient Full Name *',
                          hintText: 'e.g. John Doe',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter recipient name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppDimensions.sm),

                      // Phone Number
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Contact Phone Number *',
                          hintText: '10-digit mobile number',
                          prefixIcon: Icon(Icons.phone_outlined),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter contact phone';
                          }
                          final digits = val.replaceAll(RegExp(r'\D'), '');
                          if (digits.length < 10) {
                            return 'Please enter a valid 10-digit mobile number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppDimensions.sm),

                      // House / Flat (Manual Required Entry)
                      TextFormField(
                        controller: _houseController,
                        decoration: const InputDecoration(
                          labelText: 'House / Flat / Floor / Building *',
                          hintText: 'e.g. Flat 402, Block A, Sunshine Apts',
                          prefixIcon: Icon(Icons.apartment_outlined),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter house / flat details';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppDimensions.sm),

                      // Street / Area (Pre-filled from Geocode)
                      TextFormField(
                        controller: _streetController,
                        decoration: const InputDecoration(
                          labelText: 'Street / Colony / Area *',
                          hintText: 'e.g. 12th Main, Indiranagar',
                          prefixIcon: Icon(Icons.signpost_outlined),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter street or area name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppDimensions.sm),

                      // Landmark (Optional)
                      TextFormField(
                        controller: _landmarkController,
                        decoration: const InputDecoration(
                          labelText: 'Landmark (Optional)',
                          hintText: 'e.g. Behind Metro Station',
                          prefixIcon: Icon(Icons.pin_drop_outlined),
                        ),
                      ),
                      const SizedBox(height: AppDimensions.sm),

                      // City & PIN Code Row
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: TextFormField(
                              controller: _cityController,
                              decoration: const InputDecoration(
                                labelText: 'City *',
                                prefixIcon: Icon(Icons.location_city_outlined),
                              ),
                              validator: (val) =>
                                  val == null || val.trim().isEmpty
                                  ? 'Enter city'
                                  : null,
                            ),
                          ),
                          const SizedBox(width: AppDimensions.sm),
                          Expanded(
                            flex: 4,
                            child: TextFormField(
                              controller: _pincodeController,
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              decoration: InputDecoration(
                                labelText: 'PIN Code *',
                                counterText: '',
                                suffixIcon: _isCheckingServiceability
                                    ? const Padding(
                                        padding: EdgeInsets.all(12),
                                        child: SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                              onChanged: _handleManualPincodeChange,
                              validator: (val) {
                                if (val == null || val.trim().isEmpty) {
                                  return 'Enter PIN';
                                }
                                if (!RegExp(r'^\d{6}$').hasMatch(val.trim())) {
                                  return '6 digits';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppDimensions.sm),

                      // Default Address Checkbox
                      CheckboxListTile(
                        value: _isDefault,
                        onChanged: (val) =>
                            setState(() => _isDefault = val ?? false),
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Make this my default delivery address',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      const SizedBox(height: AppDimensions.md),

                      // Save Button
                      AppButton(
                        label: isEditing
                            ? 'Update Address'
                            : 'Save & Confirm Address',
                        icon: Icons.check_circle_outline,
                        width: double.infinity,
                        isLoading: _isSaving,
                        onPressed: _handleSaveAddress,
                      ),
                      const SizedBox(height: AppDimensions.lg),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSummaryCard() {
    if (_isResolvingGeocode) {
      return Container(
        padding: const EdgeInsets.all(AppDimensions.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceBorder.withValues(alpha: 0.3),
          borderRadius: AppDimensions.roundedMd,
        ),
        child: Row(
          children: const [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text(
              'Resolving address from map pin...',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    final loc = _selectedLocation;
    final isServiceable = loc?.isServiceable ?? false;
    final pin = _pincodeController.text.trim();

    return Container(
      padding: const EdgeInsets.all(AppDimensions.md),
      decoration: BoxDecoration(
        color: isServiceable
            ? AppColors.primaryContainer.withValues(alpha: 0.4)
            : AppColors.surfaceBorder.withValues(alpha: 0.3),
        borderRadius: AppDimensions.roundedMd,
        border: Border.all(
          color: isServiceable ? AppColors.primary : AppColors.surfaceBorder,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isServiceable
                    ? Icons.check_circle_rounded
                    : Icons.location_searching_rounded,
                size: 18,
                color: isServiceable ? AppColors.primary : AppColors.warning,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  loc?.formattedAddress.isNotEmpty == true
                      ? loc!.formattedAddress
                      : 'Lat: ${_cameraCenter.latitude.toStringAsFixed(5)}, Lng: ${_cameraCenter.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Serviceability Status
          if (_isCheckingServiceability)
            const Text(
              'Checking delivery coverage for this area...',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            )
          else if (isServiceable)
            Text(
              'SERVICEABLE: Fresh delivery to ${loc?.serviceAreaName ?? 'this area'} • Fee ₹${loc?.deliveryFee?.toInt() ?? 30} (Free over ₹${loc?.minOrderForFreeDelivery?.toInt() ?? 499})',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDark,
              ),
            )
          else
            Text(
              pin.isNotEmpty
                  ? 'PIN $pin: Delivery currently unavailable in this area'
                  : 'Move pin or enter PIN to check delivery coverage',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.error,
              ),
            ),
        ],
      ),
    );
  }
}
