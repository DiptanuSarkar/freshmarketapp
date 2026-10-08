import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_routes.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/widgets/inputs/app_search_field.dart';
import '../../../shared/providers/products_provider.dart';
import '../../catalog/data/catalog_repository.dart';
import '../data/home_repository.dart';
import 'widgets/banner_carousel.dart';
import 'widgets/category_chips_section.dart';
import 'widgets/home_header.dart';
import 'widgets/horizontal_product_list.dart';
import 'widgets/section_header.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deals = ref.watch(dealsProductsProvider);
    final popular = ref.watch(popularProductsProvider);
    final allProducts = ref.watch(allProductsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(homeBannersProvider);
            ref.invalidate(catalogCategoriesProvider);
            ref.invalidate(catalogProductsProvider);
            await Future.wait([
              ref.read(homeBannersProvider.future),
              ref.read(catalogCategoriesProvider.future),
              ref.read(catalogProductsProvider.future),
            ]);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              // Top App Location & Header
              const SliverToBoxAdapter(child: HomeHeader()),

              // Prominent Search Bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.lg,
                    vertical: AppDimensions.sm,
                  ),
                  child: AppSearchField(
                    readOnly: true,
                    onTap: () => context.push(AppRoutes.search),
                  ),
                ),
              ),

              // Promotional Banner Carousel
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(
                    top: AppDimensions.sm,
                    bottom: AppDimensions.lg,
                  ),
                  child: BannerCarousel(),
                ),
              ),

              // Category Chips (Chicken, Mutton, Fish, Pork, Grocery)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(bottom: AppDimensions.xl),
                  child: CategoryChipsSection(),
                ),
              ),

              // Section 1: Today's Deals
              if (deals.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: SectionHeader(
                    title: "Today's Fresh Deals",
                    subtitle: 'Save extra on butchery cuts today',
                    badgeText: 'FLASH SALE',
                    onAction: () =>
                        context.push('${AppRoutes.productListPrefix}/all'),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: AppDimensions.md),
                ),
                SliverToBoxAdapter(
                  child: HorizontalProductList(products: deals),
                ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: AppDimensions.xl),
                ),
              ],

              // Freshness & Hygiene Banner
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppDimensions.lg,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(AppDimensions.md),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: AppDimensions.roundedMd,
                      border: Border.all(
                        color: AppColors.primaryLight.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.verified_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: AppDimensions.md),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'The FreshMarket Promise',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primaryDark,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                '100% Chilled, Never Frozen • Zero Preservatives • Bio-secure Farm Sourced',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.primaryDark,
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: AppDimensions.xl),
              ),

              // Section 2: Popular Fresh Products
              if (popular.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: SectionHeader(
                    title: 'Popular Right Now',
                    subtitle: 'Most ordered by chefs and homes',
                    onAction: () =>
                        context.push('${AppRoutes.productListPrefix}/all'),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: AppDimensions.md),
                ),
                SliverToBoxAdapter(
                  child: HorizontalProductList(products: popular),
                ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: AppDimensions.xl),
                ),
              ],

              // Section 3: Recommended Cuts
              if (allProducts.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: SectionHeader(
                    title: 'Recommended For You',
                    subtitle: 'Hand-picked cuts tailored for your taste',
                    onAction: () =>
                        context.push('${AppRoutes.productListPrefix}/all'),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: AppDimensions.md),
                ),
                SliverToBoxAdapter(
                  child: HorizontalProductList(products: allProducts),
                ),
              ],
              const SliverToBoxAdapter(
                child: SizedBox(height: AppDimensions.xxxl),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
