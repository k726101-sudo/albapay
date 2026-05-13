enum EducationType {
  sexualHarassment, // 성희롱예방교육
  hygiene, // 위생교육
  workplaceHarassment, // 직장 내 괴롭힘 방지
  privacy, // 개인정보보호
  safety, // 안전보건교육
}

class EducationContent {
  final String id;
  final EducationType type;
  final String title;
  final String videoUrl;
  final String? description;
  final List<QuizQuestion> quizzes;

  EducationContent({
    required this.id,
    required this.type,
    required this.title,
    required this.videoUrl,
    this.description,
    this.quizzes = const [],
  });
}

class QuizQuestion {
  final String question;
  final List<String> options;
  final int correctIndex;

  QuizQuestion({
    required this.question,
    required this.options,
    required this.correctIndex,
  });
}

class EducationRecord {
  final String id;
  final String storeId;
  final String staffId;
  final String educationContentId;
  final DateTime completedAt;
  final int score;

  EducationRecord({
    required this.id,
    required this.storeId,
    required this.staffId,
    required this.educationContentId,
    required this.completedAt,
    required this.score,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'storeId': storeId,
    'staffId': staffId,
    'educationContentId': educationContentId,
    'completedAt': completedAt.toIso8601String(),
    'score': score,
  };

  factory EducationRecord.fromJson(Map<String, dynamic> json) =>
      EducationRecord(
        id: json['id'],
        storeId: json['storeId'],
        staffId: json['staffId'],
        educationContentId: json['educationContentId'],
        completedAt: DateTime.parse(json['completedAt']),
        score: json['score'],
      );
}
