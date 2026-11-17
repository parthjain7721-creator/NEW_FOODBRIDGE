import '../models/ngo_need_model.dart';
import 'route_service.dart';


class MatchPriorityResult {
  final int urgencyScore;
  final int ngoNeedScore;
  final int pickupFeasibilityScore;
  final int travelTimeDeduction;
  final int totalScore;
  final bool isFeasible;
  final String explanation;
  final int estimatedMinutes;
  final double routeDistanceKilometres;


  const MatchPriorityResult({
    required this.urgencyScore,
    required this.ngoNeedScore,
    required this.pickupFeasibilityScore,
    required this.travelTimeDeduction,
    required this.totalScore,
    required this.isFeasible,
    required this.explanation,
    required this.estimatedMinutes,
    required this.routeDistanceKilometres,
  });
}


class MatchingService {
  static const int _urgentThresholdMinutes = 15;
  static const int _highUrgencyThresholdMinutes = 30;
  static const int _mediumUrgencyThresholdMinutes = 60;
  static const int _lowUrgencyThresholdMinutes = 120;


  static const int _maxUrgencyScore = 35;
  static const int _highUrgencyScore = 28;
  static const int _mediumUrgencyScore = 21;
  static const int _lowUrgencyScore = 12;
  static const int _baseUrgencyScore = 5;


  static const int _preferredCategoryScore = 20;
  static const int _fullQuantityScore = 10;
  static const int _partialQuantityScore = 5;


  static const int _feasibleScore = 20;


  static const int _shortTravelThresholdMinutes = 15;
  static const int _mediumTravelThresholdMinutes = 30;
  static const int _longTravelThresholdMinutes = 45;
  static const int _veryLongTravelThresholdMinutes = 60;


  static const int _noTravelDeduction = 0;
  static const int _shortTravelDeduction = 5;
  static const int _mediumTravelDeduction = 10;
  static const int _longTravelDeduction = 15;
  static const int _veryLongTravelDeduction = 25;


  static const int _pickupBufferMinutes = 10;


  static int calculateUrgencyScore({
    required DateTime pickupDeadline,
    required DateTime now,
  }) {
    final Duration remaining = pickupDeadline.difference(now);


    if (remaining <= Duration.zero) {
      return 0;
    }


    final int remainingMinutes = remaining.inMinutes;


    if (remainingMinutes <= _urgentThresholdMinutes) {
      return _maxUrgencyScore;
    }


    if (remainingMinutes <= _highUrgencyThresholdMinutes) {
      return _highUrgencyScore;
    }


    if (remainingMinutes <= _mediumUrgencyThresholdMinutes) {
      return _mediumUrgencyScore;
    }


    if (remainingMinutes <= _lowUrgencyThresholdMinutes) {
      return _lowUrgencyScore;
    }


    return _baseUrgencyScore;
  }


  static int calculateNgoNeedScore({
    required String foodCategory,
    required num quantity,
    required NgoNeedModel ngoNeed,
  }) {
    int score = 0;


    if (ngoNeed.preferredFoodCategories
        .contains(foodCategory)) {
      score += _preferredCategoryScore;
    }


    if (ngoNeed.requiredQuantity <= 0 || quantity <= 0) {
      return score;
    }


    final double requiredQuantity =
        ngoNeed.requiredQuantity.toDouble();


    final double donationQuantity = quantity.toDouble();


    if (donationQuantity >= requiredQuantity) {
      score += _fullQuantityScore;
    } else if (
      donationQuantity >= requiredQuantity * 0.5
    ) {
      score += _partialQuantityScore;
    }


    return score;
  }


  static int calculateTravelTimeDeduction({
    required int estimatedMinutes,
  }) {
    if (estimatedMinutes <= _shortTravelThresholdMinutes) {
      return _noTravelDeduction;
    }


    if (estimatedMinutes <= _mediumTravelThresholdMinutes) {
      return _shortTravelDeduction;
    }


    if (estimatedMinutes <= _longTravelThresholdMinutes) {
      return _mediumTravelDeduction;
    }


    if (estimatedMinutes <= _veryLongTravelThresholdMinutes) {
      return _longTravelDeduction;
    }


    return _veryLongTravelDeduction;
  }


  static MatchPriorityResult evaluate({
    required String foodCategory,
    required num quantity,
    required DateTime pickupDeadline,
    required DateTime now,
    required NgoNeedModel ngoNeed,
    FoodBridgeRoute? route,
  }) {
    final int urgencyScore = calculateUrgencyScore(
      pickupDeadline: pickupDeadline,
      now: now,
    );


    final int ngoNeedScore = calculateNgoNeedScore(
      foodCategory: foodCategory,
      quantity: quantity,
      ngoNeed: ngoNeed,
    );


    if (route == null) {
      return MatchPriorityResult(
        urgencyScore: urgencyScore,
        ngoNeedScore: ngoNeedScore,
        pickupFeasibilityScore: 0,
        travelTimeDeduction: 0,
        totalScore: urgencyScore + ngoNeedScore,
        isFeasible: false,
        explanation:
            'Road-route feasibility has not been calculated yet.',
        estimatedMinutes: 0,
        routeDistanceKilometres: 0,
      );
    }


    final int estimatedMinutes = route.estimatedMinutes;


    final DateTime estimatedArrival =
        now.add(
      Duration(minutes: estimatedMinutes),
    );


    final DateTime feasibilityDeadline = pickupDeadline.subtract(
      const Duration(minutes: _pickupBufferMinutes),
    );


    final bool isFeasible =
        estimatedArrival.isBefore(feasibilityDeadline) ||
            estimatedArrival.isAtSameMomentAs(
              feasibilityDeadline,
            );


    final int travelTimeDeduction =
        calculateTravelTimeDeduction(
      estimatedMinutes: estimatedMinutes,
    );


    final int pickupFeasibilityScore =
        isFeasible ? _feasibleScore : 0;


    final int totalScore = urgencyScore +
        ngoNeedScore +
        pickupFeasibilityScore -
        travelTimeDeduction;


    final String explanation;


    if (!isFeasible) {
      explanation =
          'The NGO round trip cannot reasonably complete before '
          'the pickup deadline, including a '
          '$_pickupBufferMinutes-minute handover buffer.';
    } else {
      explanation =
          'The NGO round trip is feasible within the pickup '
          'deadline, including a '
          '$_pickupBufferMinutes-minute handover buffer.';
    }


    return MatchPriorityResult(
      urgencyScore: urgencyScore,
      ngoNeedScore: ngoNeedScore,
      pickupFeasibilityScore: pickupFeasibilityScore,
      travelTimeDeduction: travelTimeDeduction,
      totalScore: totalScore,
      isFeasible: isFeasible,
      explanation: explanation,
      estimatedMinutes: estimatedMinutes,
      routeDistanceKilometres: route.distanceKilometres,
    );
  }
}