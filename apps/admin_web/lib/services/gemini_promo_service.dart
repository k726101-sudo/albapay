import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:file_picker/file_picker.dart';
import '../models/promotion_data.dart';
import 'package:uuid/uuid.dart';

class GeminiPromoService {
  static const String _promptText = '''
당신은 현직 파리바게뜨 가맹점주를 돕는 아주 엄격하고 정확한 정보 분석가입니다.
제공된 이미지는 파리바게뜨 사내 소식지(예: PB WEEKLY) 또는 공지사항입니다.
문서에는 핵심 정보들과 단순한 인사말, 꾸밈 문구들이 섞여 있습니다.

[엄격한 분석 지침 - 반드시 지킬 것]
1. 단순한 타이틀(예:"PB WEEKLY", "3월 3주차 소식"), 인사말, 단순 사진, 의미 없는 장식 문구는 절대로 항목으로 추출하지 마세요.
2. 이미지에 명시되지 않은 내용을 자의적으로 추측하거나 지어내지 마세요.
3. 가맹점주가 매장 운영을 위해 알아야 하는 "실체가 있는 행사", "신제품 정보", "본사 정책 규정/안내사항"만을 선별하세요.

[정보 추출 요구 사항]
1. PromotionID: 고유 식별자 (자동 생성, 예: PB_20251201_01)
2. PromotionName (행사명): 행사나 공지의 구체적인 본문 제목 (예:'SKT멤버십 우주패스 제휴', '딸기 페어 신제품 출시').
3. EventType (유형): '할인', '증정', '제휴카드', '신제품', '가이드/공지' 중 가장 정확한 1개 택일.
4. StartDate (시작일): 행사 시작 날짜 (YYYY-MM-DD 형식). 명시 안 되어 있으면 '상시' 또는 빈 칸.
5. EndDate (종료일): 행사 종료 날짜 (YYYY-MM-DD 형식, 또는 '소진 시까지').
6. TargetProducts (대상 제품): 적용 대상 (알 수 없으면 빈 칸, 너무 많으면 핵심 품목 요약).
7. KeyBenefit (주요 혜택): 고객 혜택 또는 점포 지원 내용 요약.
8. Notes (특이 사항): (가장 중요) 표나 하단 유의사항에 있는 "POS 조작/적용 방법", "제외 매장/제외 품목", "행사 비용 정산 비율(본부 O%, 가맹점 O%)" 등 실무 필수 조건을 꼼꼼하게 추출하세요.

위 지침에 따라 엉뚱한 정보는 제외하고, 진짜 유의미한 항목들만 선별하여 JSON 형식으로 반환하세요.
''';

  /// React 원본 코드(gemini.ts)의 responseSchema를 Flutter Schema로 1:1 재현.
  /// 이 스키마가 있어야 Gemini가 정확한 JSON 배열을 강제로 반환합니다.
  static final _responseSchema = Schema.array(
    description: 'List of extracted promotions',
    items: Schema.object(
      properties: {
        'PromotionID': Schema.string(
          description: 'Unique identifier, e.g., PB_20251201_01',
        ),
        'PromotionName': Schema.string(
          description: 'Name of the promotion',
        ),
        'EventType': Schema.string(
          description: 'Type of event, e.g., 할인, 증정, 제휴카드',
        ),
        'StartDate': Schema.string(
          description: 'Start date in YYYY-MM-DD',
        ),
        'EndDate': Schema.string(
          description: 'End date in YYYY-MM-DD or specific text',
        ),
        'TargetProducts': Schema.string(
          description: 'Comma separated list of target products',
        ),
        'KeyBenefit': Schema.string(
          description: 'Main benefit like discount rate',
        ),
        'Notes': Schema.string(
          description: 'Important notes or conditions',
        ),
      },
      requiredProperties: ['PromotionName', 'StartDate', 'KeyBenefit'],
    ),
  );

  final GenerativeModel _model;
  final Uuid _uuid = const Uuid();

  GeminiPromoService(String apiKey) 
      : _model = GenerativeModel(
          model: 'gemini-2.5-flash',
          apiKey: apiKey,
          generationConfig: GenerationConfig(
            responseMimeType: 'application/json',
            responseSchema: _responseSchema,
          ),
        );

  Future<List<PromotionData>> analyzeImage(PlatformFile file) async {
    if (file.bytes == null) {
      throw Exception('File bytes are null. Please run on Web and ensure bytes are available.');
    }

    final String mimeType;
    final ext = file.extension?.toLowerCase() ?? '';
    if (ext == 'png') {
      mimeType = 'image/png';
    } else if (ext == 'webp') {
      mimeType = 'image/webp';
    } else {
      mimeType = 'image/jpeg';
    }
    final part = DataPart(mimeType, file.bytes!);

    final response = await _model.generateContent([
      Content.multi([
        TextPart(_promptText),
        part,
      ])
    ]);

    final text = response.text;
    if (text == null || text.isEmpty) {
      throw Exception('No data returned from the analysis.');
    }

    try {
      final parsed = jsonDecode(text);
      List<dynamic> jsonList = [];
      if (parsed is List) {
        jsonList = parsed;
      } else if (parsed is Map && parsed.containsKey('promotions')) {
        jsonList = parsed['promotions'] as List;
      } else {
        jsonList = [parsed];
      }

      final String imageRefId = _uuid.v4().substring(0, 8);
      
      return jsonList.map((e) {
        final Map<String, dynamic> promo = Map<String, dynamic>.from(e);
        final pId = promo['PromotionID'] ?? 'UNKNOWN';
        promo['PromotionID'] = '${imageRefId}_$pId';
        return PromotionData.fromJson(promo);
      }).toList();
    } catch (e) {
      throw Exception('Failed to parse the analysis result JSON: $e');
    }
  }
}

