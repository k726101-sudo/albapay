class PromotionData {
  final String promotionId;
  final String promotionName;
  final String eventType;
  final String startDate;
  final String endDate;
  final String targetProducts;
  final String keyBenefit;
  final String notes;

  PromotionData({
    required this.promotionId,
    required this.promotionName,
    required this.eventType,
    required this.startDate,
    required this.endDate,
    required this.targetProducts,
    required this.keyBenefit,
    required this.notes,
  });

  factory PromotionData.fromJson(Map<String, dynamic> json) {
    return PromotionData(
      promotionId: json['PromotionID']?.toString() ?? '',
      promotionName: json['PromotionName']?.toString() ?? '',
      eventType: json['EventType']?.toString() ?? '',
      startDate: json['StartDate']?.toString() ?? '',
      endDate: json['EndDate']?.toString() ?? '',
      targetProducts: json['TargetProducts']?.toString() ?? '',
      keyBenefit: json['KeyBenefit']?.toString() ?? '',
      notes: json['Notes']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'PromotionID': promotionId,
      'PromotionName': promotionName,
      'EventType': eventType,
      'StartDate': startDate,
      'EndDate': endDate,
      'TargetProducts': targetProducts,
      'KeyBenefit': keyBenefit,
      'Notes': notes,
    };
  }
}
