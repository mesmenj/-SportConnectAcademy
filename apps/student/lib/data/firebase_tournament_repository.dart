import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class TournamentRecord {
  const TournamentRecord({
    required this.id,
    required this.name,
    required this.venue,
    required this.category,
    required this.description,
    required this.startsAt,
    required this.capacity,
    required this.registeredCount,
    required this.imageUrl,
  });
  final String id, name, venue, category, description;
  final DateTime startsAt;
  final int capacity, registeredCount;
  final String? imageUrl;

  factory TournamentRecord.fromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data()!;
    return TournamentRecord(
      id: document.id,
      name: (data['name'] ?? 'Tournoi').toString(),
      venue: (data['venue'] ?? '—').toString(),
      category: (data['category'] ?? '—').toString(),
      description: (data['description'] ?? '').toString(),
      startsAt: (data['startsAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      capacity: (data['capacity'] as num?)?.toInt() ?? 0,
      registeredCount: (data['registeredCount'] as num?)?.toInt() ?? 0,
      imageUrl: data['imageUrl']?.toString(),
    );
  }
}

class FirebaseTournamentRepository {
  FirebaseTournamentRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  Stream<List<TournamentRecord>> watchTournaments() => _firestore
      .collection('tournaments')
      .where('status', isEqualTo: 'open')
      .orderBy('startsAt')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs
            .where((document) => document.data()['isDelete'] != true)
            .map(TournamentRecord.fromDocument)
            .toList(),
      );

  Future<void> createTournament({
    required String name,
    required String venue,
    required String category,
    required String description,
    required DateTime startsAt,
    required int capacity,
    Uint8List? imageBytes,
    String? imageMimeType,
  }) async {
    String? imageDataUrl;
    if (imageBytes != null && imageMimeType != null) {
      imageDataUrl = 'data:$imageMimeType;base64,${base64Encode(imageBytes)}';
    }
    await _functions.httpsCallable('createTournament').call(<String, Object?>{
      'name': name,
      'venue': venue,
      'category': category,
      'description': description,
      'startsAt': startsAt.toUtc().toIso8601String(),
      'capacity': capacity,
      'academyId': null,
      'imageDataUrl': imageDataUrl,
    });
  }
}
