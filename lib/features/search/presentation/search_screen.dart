import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/widgets/feedback/app_empty_state.dart';
import '../../../core/widgets/feedback/app_error_widget.dart';
import '../../../core/widgets/feedback/app_loading_indicator.dart';
import '../../../core/widgets/inputs/app_search_field.dart';
import '../../../shared/providers/products_provider.dart';
import '../../product/presentation/widgets/product_card.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  static const List<String> trendingSearches = [
    'Chicken Curry Cut',
    'Goat Mutton',
    'Seer Fish',
    'Farm Eggs',
    'Pork Chops',
    'Masala',
  ];

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String val) {
    ref.read(searchQueryProvider.notifier).setQuery(val);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) {
        ref.read(debouncedSearchQueryProvider.notifier).setQuery(val);
      }
    });
  }

  void _onChipSelected(String keyword) {
    _searchController.text = keyword;
    _onQueryChanged(keyword);
  }

  void _clearSearch() {
    _searchController.clear();
    _debounce?.cancel();
    ref.read(searchQueryProvider.notifier).setQuery('');
    ref.read(debouncedSearchQueryProvider.notifier).setQuery('');
  }

  @override
  Widget build(BuildContext context) {
    final currentQuery = ref.watch(searchQueryProvider);
    final searchAsync = ref.watch(searchResultsFutureProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: AppDimensions.lg),
          child: AppSearchField(
            controller: _searchController,
            autofocus: true,
            onChanged: _onQueryChanged,
            onClear: _clearSearch,
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Trending / Suggestions Chips
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.symmetric(
              horizontal: AppDimensions.lg,
              vertical: AppDimensions.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Popular Searches',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppDimensions.xs),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: trendingSearches.map((term) {
                    final isCurrent =
                        currentQuery.toLowerCase() == term.toLowerCase();
                    return ActionChip(
                      label: Text(term),
                      backgroundColor: isCurrent
                          ? AppColors.primaryContainer
                          : AppColors.surfaceSubtle,
                      labelStyle: TextStyle(
                        fontSize: 11,
                        color: isCurrent
                            ? AppColors.primaryDark
                            : AppColors.textSecondary,
                        fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.w500,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      side: BorderSide(
                        color: isCurrent
                            ? AppColors.primary
                            : Colors.transparent,
                        width: 1,
                      ),
                      onPressed: () => _onChipSelected(term),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Results Grid with Loading / Error / Empty States
          Expanded(
            child: searchAsync.when(
              loading: () => const Center(
                child: AppLoadingIndicator(message: 'Searching fresh cuts...'),
              ),
              error: (err, stack) => AppErrorWidget(
                title: "Couldn't load search results",
                message: 'Please check your connection and try again.',
                onRetry: () => ref.refresh(searchResultsFutureProvider),
              ),
              data: (products) {
                if (products.isEmpty) {
                  return AppEmptyState(
                    title: 'No matching cuts found',
                    message: 'Try searching with general terms like "chicken", "fish", or "mutton".',
                    icon: Icons.search_off_rounded,
                    actionLabel: 'Clear Search',
                    onAction: _clearSearch,
                  );
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
                    return GridView.builder(
                      padding: const EdgeInsets.all(AppDimensions.lg),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        childAspectRatio: 0.62,
                        crossAxisSpacing: AppDimensions.md,
                        mainAxisSpacing: AppDimensions.md,
                      ),
                      itemCount: products.length,
                      itemBuilder: (context, index) {
                        final product = products[index];
                        return ProductCard(
                          product: product,
                          width: double.infinity,
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
