import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/promotion_data.dart';

class FirestorePromoService {
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  Future<void> savePromotions(List<PromotionData> promotions) async {
    final batch = _db.batch();
    for (var promo in promotions) {
      final docRef = _db.collection('pb_promotions').doc(promo.promotionId);
      batch.set(docRef, promo.toJson(), SetOptions(merge: true));
    }
    await batch.commit();
  }

  Stream<List<PromotionData>> watchPromotions() {
    return _db.collection('pb_promotions').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => PromotionData.fromJson(doc.data())).toList();
    });
  }

  Future<void> deletePromotion(String promotionId) async {
    await _db.collection('pb_promotions').doc(promotionId).delete();
  }

  Future<void> saveNotice(String title, String content) async {
    final docRef = _db.collection('pb_notices').doc();
    await docRef.set({
      'NoticeID': docRef.id,
      'Title': title,
      'Content': content,
      'CreatedAt': FieldValue.serverTimestamp(),
      'Source': 'NotebookLM',
    });
  }
}
