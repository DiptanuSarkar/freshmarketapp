class Category {
  const Category({
    required this.id,
    required this.slug,
    required this.name,
    required this.imageUrl,
    this.itemCount = 0,
    this.badge,
    this.description,
  });

  final String id;
  final String slug;
  final String name;
  final String imageUrl;
  final int itemCount;
  final String? badge;
  final String? description;
}
