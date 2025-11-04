import 'package:firebase_database/firebase_database.dart';

class FirebaseService {
  final DatabaseReference _dbRef = FirebaseDatabase.instance.ref();

  Future<List<String>> getUsedFingerprintIds() async {
    final snapshot = await _dbRef.child("fingerprints").get();
    if (snapshot.exists) {
      final data = Map<String, dynamic>.from(snapshot.value as Map);
      return data.keys.toList();
    }
    return [];
  }

  Future<String> getLockerStatus() async {
    final snapshot = await _dbRef.child("locker/status").get();
    if (snapshot.exists) {
      return snapshot.value.toString();
    }
    return "Tidak Aktif";
  }

  DatabaseReference get reference => _dbRef;
}
