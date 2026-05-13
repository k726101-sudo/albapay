import 'package:cloud_firestore/cloud_firestore.dart';

Future<void> forceEnableGpsForAllStores() async {
  final stores = await FirebaseFirestore.instance.collection('stores').get();
  for (var doc in stores.docs) {
    if (doc.data().containsKey('gpsAttendanceEnabled') && doc.data()['gpsAttendanceEnabled'] == true) {
      continue;
    }
    await doc.reference.update({
      'gpsAttendanceEnabled': true,
      'gpsRadius': 50,
      'latitude': 35.1586,
      'longitude': 129.1603,
    });
  }
}
