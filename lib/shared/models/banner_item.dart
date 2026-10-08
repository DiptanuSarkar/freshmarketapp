class BannerItem {
  const BannerItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.badgeText,
    this.targetCategorySlug,
    this.actionLabel = 'Shop Now',
  });

  final String id;
  final String title;
  final String subtitle;
  final String imageUrl;
  final String badgeText;
  final String? targetCategorySlug;
  final String actionLabel;

  factory BannerItem.fromJson(Map<String, dynamic> json) {
    return BannerItem(
      id: json['id'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String? ?? '',
      imageUrl: json['image_url'] as String? ?? '',
      badgeText: json['badge_text'] as String? ?? 'OFFER',
      targetCategorySlug: json['target_category_slug'] as String?,
      actionLabel: json['action_label'] as String? ?? 'Shop Now',
    );
  }
}
