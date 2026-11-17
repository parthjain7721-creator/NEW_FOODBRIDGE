class NgoNeedModel {
  final int requiredQuantity;
  final Set<String> preferredFoodCategories;


  const NgoNeedModel({
    required this.requiredQuantity,
    required this.preferredFoodCategories,
  });


  factory NgoNeedModel.fromMap(Map<String, dynamic> map) {
    final Object? rawQuantity = map['requiredQuantity'];
    final Object? rawCategories =
        map['preferredFoodCategories'];


    final Set<String> categories = <String>{};


    if (rawCategories is List) {
      for (final Object? category in rawCategories) {
        if (category is String && category.trim().isNotEmpty) {
          categories.add(category.trim());
        }
      }
    }


    return NgoNeedModel(
      requiredQuantity:
          rawQuantity is int && rawQuantity > 0 ? rawQuantity : 0,
      preferredFoodCategories: categories,
    );
  }
}