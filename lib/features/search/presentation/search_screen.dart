import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/widgets/feedback/app_empty_state.dart';
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

  static const List<String> trendingSearches = [
    'Chicken Curry Cut',
    'Goat Mutton',
    'Seer Fish',
    'Farm Eggs',
    'Pork Chops',
    'Meat Masala',
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onChipSelected(String keyword) {
    _searchController.text = keyword;
    ref.read(searchQueryProvider.notifier).setQuery(keyword);
  }

  @override
  Widget build(BuildContext context) {
    final searchResults = ref.watch(searchResultsProvider);
    final currentQuery = ref.watch(searchQueryProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: AppDimensions.lg),
          child: AppSearchField(
            controller: _searchController,
            autofocus: true,
            onChanged: (val) {
              ref.read(searchQueryProvider.notifier).setQuery(val);
            },
            onClear: () {
              ref.read(searchQueryProvider.notifier).setQuery('');
            },
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

          // Results Grid
          Expanded(
            child: searchResults.isEmpty
                ? AppEmptyState(
                    title: 'No matching cuts found',
                    message: 'Try searching with general terms like "chicken", "fish", or "mutton".',
                    icon: Icons.search_off_rounded,
                    actionLabel: 'Clear Search',
                    onAction: () {
                      _searchController.clear();
                      ref.read(searchQueryProvider.notifier).setQuery('');
                    },
                  )
                : LayoutBuilder(
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
                        itemCount: searchResults.length,
                        itemBuilder: (context, index) {
                          final product = searchResults[index];
                          return ProductCard(
                            product: product,
                            width: double.infinity,
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
