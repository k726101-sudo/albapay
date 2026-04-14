import 'package:cloud_firestore/cloud_firestore.dart';

class ConsentService {
  ConsentService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  // Bump these when you update the documents.
  static const String termsVersion = '2026-03-18';
  static const String privacyVersion = '2026-03-18';

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  Future<void> ensureConsentRecorded({
    required String uid,
    required String platform,
    String? appVersion,
    String? locale,
  }) async {
    final ref = _userDoc(uid);

    await ref.set(
      {
        'termsVersion': termsVersion,
        'privacyVersion': privacyVersion,
        'termsAcceptedAt': FieldValue.serverTimestamp(),
        'privacyAcceptedAt': FieldValue.serverTimestamp(),
        'scrollConfirmed': true,
        'acceptedPlatform': platform,
        'acceptedAppVersion': ?appVersion,
        'acceptedLocale': ?locale,
      },
      SetOptions(merge: true),
    );
  }
}

