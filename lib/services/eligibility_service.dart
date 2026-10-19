class EligibilityResult {
  final String status;
  final int remainingMinutes;
  final String explanation;

  const EligibilityResult({
    required this.status,
    required this.remainingMinutes,
    required this.explanation,
  });
}

class EligibilityService {
  static EligibilityResult calculate({
    required DateTime preparedAt,
    required DateTime now,
    required String foodCategory,
    required String storageMethod,
    required String packagingState,
  }) {
    final ageMinutes = now.difference(preparedAt).inMinutes;

    if (preparedAt.isAfter(now)) {
      return const EligibilityResult(
        status: 'manual_review',
        remainingMinutes: 0,
        explanation: 'Preparation time cannot be in the future.',
      );
    }

    if (packagingState == 'damaged' || packagingState == 'leaking') {
      return const EligibilityResult(
        status: 'not_eligible',
        remainingMinutes: 0,
        explanation: 'Packaging condition requires rejection.',
      );
    }

    final limitMinutes = _getWindowLimit(
      foodCategory: foodCategory,
      storageMethod: storageMethod,
    );

    final remainingMinutes = limitMinutes - ageMinutes;

    if (remainingMinutes <= 0) {
      return const EligibilityResult(
        status: 'not_eligible',
        remainingMinutes: 0,
        explanation: 'The declared redistribution window has closed.',
      );
    }

    if (remainingMinutes <= 60) {
      return EligibilityResult(
        status: 'urgent',
        remainingMinutes: remainingMinutes,
        explanation: 'Collect this donation urgently.',
      );
    }

    if (storageMethod == 'unknown') {
      return EligibilityResult(
        status: 'manual_review',
        remainingMinutes: remainingMinutes,
        explanation: 'NGO manual review is required for storage details.',
      );
    }

    return EligibilityResult(
      status: 'eligible',
      remainingMinutes: remainingMinutes,
      explanation: 'Eligible for pickup within the rescue window.',
    );
  }

  static int _getWindowLimit({
    required String foodCategory,
    required String storageMethod,
  }) {
    if (storageMethod == 'refrigerated') {
      return 24 * 60;
    }

    if (storageMethod == 'frozen') {
      return 48 * 60;
    }

    switch (foodCategory) {
      case 'Cooked meal':
        return 4 * 60;
      case 'Bakery':
        return 24 * 60;
      case 'Fruits and vegetables':
        return 24 * 60;
      case 'Packaged food':
        return 72 * 60;
      default:
        return 6 * 60;
    }
  }
}