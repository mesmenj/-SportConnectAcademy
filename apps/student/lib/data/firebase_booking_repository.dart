import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PlayerOption {
  const PlayerOption({
    required this.id,
    required this.name,
    required this.academyId,
    required this.age,
    required this.sessionConfigurationId,
    required this.sessionCount,
    required this.remainingSessions,
  });
  final String id, name, academyId;
  final String? sessionConfigurationId;
  final int? age;
  final int sessionCount, remainingSessions;
}

class SessionOption {
  const SessionOption({
    required this.id,
    required this.academyId,
    required this.title,
    required this.coachName,
    required this.courtName,
    required this.startsAt,
    required this.price,
    required this.currency,
    required this.remainingPlaces,
  });
  final String id, academyId, title, coachName, courtName;
  final String currency;
  final DateTime startsAt;
  final int price, remainingPlaces;
}

class UpcomingBooking {
  const UpcomingBooking({
    required this.id,
    required this.playerName,
    required this.title,
    required this.coachName,
    required this.courtName,
    required this.startsAt,
    required this.endsAt,
  });
  final String id, playerName, title, coachName, courtName;
  final DateTime startsAt, endsAt;
}

class BookingHistoryItem {
  const BookingHistoryItem({
    required this.id,
    required this.playerId,
    required this.playerName,
    required this.title,
    required this.coachName,
    required this.courtName,
    required this.status,
    required this.startsAt,
    required this.endsAt,
    required this.amount,
    required this.currency,
    required this.clientCanReject,
  });
  final String id, playerId, playerName, title, coachName, courtName, status;
  final DateTime startsAt, endsAt;
  final num amount;
  final String currency;
  final bool clientCanReject;
}

class FirebaseBookingRepository {
  FirebaseBookingRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1'),
       _auth = auth ?? FirebaseAuth.instance;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  Future<List<PlayerOption>> loadMyPlayers() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('AUTH_REQUIRED');
    final links = await _firestore
        .collection('users')
        .doc(user.uid)
        .collection('players')
        .get();
    final players = await Future.wait(
      links.docs.map(
        (link) => _firestore.collection('players').doc(link.id).get(),
      ),
    );
    return players
        .where(
          (item) =>
              item.exists &&
              item.data()?['status'] == 'active' &&
              item.data()?['isDelete'] != true,
        )
        .map((item) {
          final data = item.data()!;
          return PlayerOption(
            id: item.id,
            name: (data['displayName'] ?? data['name'] ?? 'Joueur').toString(),
            academyId: (data['academyId'] ?? '').toString(),
            age: (data['age'] as num?)?.toInt(),
            sessionConfigurationId: data['sessionConfigurationId']?.toString(),
            sessionCount: (data['sessionCount'] as num?)?.toInt() ?? 0,
            remainingSessions:
                (data['remainingSessions'] as num?)?.toInt() ?? 0,
          );
        })
        .toList();
  }

  Future<List<SessionOption>> loadSessions(
    String academyId, {
    int? playerAge,
    String? sessionConfigurationId,
  }) async {
    final results = await Future.wait([
      _firestore
          .collection('sessions')
          .where('startsAt', isGreaterThan: Timestamp.now())
          .orderBy('startsAt')
          .limit(50)
          .get(),
      _firestore.collection('sessionConfigurations').get(),
    ]);
    final result = results[0];
    final configurations = results[1].docs
        .map((doc) => <String, dynamic>{...doc.data(), 'id': doc.id})
        .where((data) => data['active'] == true)
        .toList();
    String normalizeType(Object? value) {
      final normalized = (value ?? '')
          .toString()
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[ -]+'), '_');
      if (normalized.startsWith('semi_private')) return 'semi_private';
      if (normalized.startsWith('private')) return 'private';
      if (normalized.startsWith('group')) return 'group';
      return '';
    }

    return result.docs
        .where((item) => item.data()['status'] == 'open')
        .map((item) {
          final data = item.data();
          final type = normalizeType(data['configurationType'] ?? data['type']);
          if (playerAge == null) return null;
          if (sessionConfigurationId != null &&
              data['configurationId'] != sessionConfigurationId) {
            return null;
          }
          final matches = configurations
              .where(
                (candidate) =>
                    (sessionConfigurationId == null ||
                        candidate['id'] == sessionConfigurationId) &&
                    candidate['academyId'] == data['academyId'] &&
                    candidate['type'] == type &&
                    playerAge >=
                        ((candidate['minAge'] as num?)?.toInt() ?? 101) &&
                    playerAge <= ((candidate['maxAge'] as num?)?.toInt() ?? -1),
              )
              .toList();
          if (matches.length != 1) return null;
          final config = matches.single;
          final minAge = (config['minAge'] as num?)?.toInt();
          final maxAge = (config['maxAge'] as num?)?.toInt();
          if (minAge == null ||
              maxAge == null ||
              playerAge < minAge ||
              playerAge > maxAge) {
            return null;
          }
          final capacity = (data['capacity'] as num?)?.toInt() ?? 0;
          final booked = (data['bookedCount'] as num?)?.toInt() ?? 0;
          return SessionOption(
            id: item.id,
            academyId: (data['academyId'] ?? '').toString(),
            title: (data['title'] ?? data['type'] ?? 'Cours de tennis')
                .toString(),
            coachName: (data['coachName'] ?? 'Coach').toString(),
            courtName: (data['courtName'] ?? data['courtId'] ?? 'Terrain')
                .toString(),
            startsAt: (data['startsAt'] as Timestamp).toDate(),
            price: (config['price'] as num?)?.toInt() ?? 0,
            currency: (config['currency'] ?? 'AED').toString(),
            remainingPlaces: (capacity - booked).clamp(0, capacity),
          );
        })
        .whereType<SessionOption>()
        .where((item) => item.remainingPlaces > 0)
        .toList();
  }

  Future<void> createBooking({
    required String playerId,
    required String sessionId,
    String? note,
  }) async {
    await _functions.httpsCallable('createBooking').call(<String, Object?>{
      'playerId': playerId,
      'sessionId': sessionId,
      'note': note,
    });
  }

  Stream<List<BookingHistoryItem>> watchBookingHistory() => _auth
      .userChanges()
      .distinct((previous, next) => previous?.uid == next?.uid)
      .asyncExpand(
        (user) => user == null
            ? Stream<List<BookingHistoryItem>>.value(const [])
            : _watchBookingHistory(user),
      );

  Stream<List<BookingHistoryItem>> _watchBookingHistory(User user) {
    final controller = StreamController<List<BookingHistoryItem>>();
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? linksSubscription;
    final bookingSubscriptions =
        <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
    final results = <String, List<BookingHistoryItem>>{};
    void emit() {
      final items = results.values.expand((entries) => entries).toList()
        ..sort((a, b) => b.startsAt.compareTo(a.startsAt));
      if (!controller.isClosed) controller.add(items);
    }

    linksSubscription = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('players')
        .snapshots()
        .listen((links) async {
          for (final subscription in bookingSubscriptions) {
            await subscription.cancel();
          }
          bookingSubscriptions.clear();
          results.clear();
          if (links.docs.isEmpty) {
            emit();
            return;
          }
          for (final link in links.docs) {
            bookingSubscriptions.add(
              _firestore
                  .collection('bookings')
                  .where('playerId', isEqualTo: link.id)
                  .snapshots()
                  .listen((snapshot) {
                    results[link.id] = snapshot.docs
                        .where(
                          (document) =>
                              document.data()['isDelete'] != true &&
                              document.data()['startsAt'] is Timestamp,
                        )
                        .map((document) {
                          final data = document.data();
                          final startsAt = (data['startsAt'] as Timestamp)
                              .toDate();
                          return BookingHistoryItem(
                            id: document.id,
                            playerId: link.id,
                            playerName: (data['playerName'] ?? 'Joueur')
                                .toString(),
                            title:
                                (data['title'] ??
                                        _sessionTitle(data['sessionType']))
                                    .toString(),
                            coachName: (data['coachName'] ?? 'Coach à définir')
                                .toString(),
                            courtName: (data['courtName'] ?? 'Lieu à définir')
                                .toString(),
                            status: (data['status'] ?? 'pending').toString(),
                            startsAt: startsAt,
                            endsAt:
                                (data['endsAt'] as Timestamp?)?.toDate() ??
                                startsAt.add(const Duration(hours: 1)),
                            amount: (data['amount'] as num?) ?? 0,
                            currency: (data['currency'] ?? 'AED').toString(),
                            clientCanReject: data['clientCanReject'] == true,
                          );
                        })
                        .toList();
                    emit();
                  }, onError: controller.addError),
            );
          }
        }, onError: controller.addError);
    controller.onCancel = () async {
      await linksSubscription?.cancel();
      for (final subscription in bookingSubscriptions) {
        await subscription.cancel();
      }
    };
    return controller.stream;
  }

  Future<void> rejectScheduledBooking(String bookingId) async {
    await _functions.httpsCallable('rejectScheduledBooking').call({
      'bookingId': bookingId,
    });
  }

  Stream<UpcomingBooking?> watchNextConfirmedSession() => _auth
      .userChanges()
      .distinct((previous, next) => previous?.uid == next?.uid)
      .asyncExpand(
        (user) => user == null
            ? Stream<UpcomingBooking?>.value(null)
            : _watchNextConfirmedSession(user),
      );

  Stream<UpcomingBooking?> _watchNextConfirmedSession(User user) {
    final controller = StreamController<UpcomingBooking?>();
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? linksSubscription;
    final bookingSubscriptions =
        <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
    final results = <String, List<UpcomingBooking>>{};
    void emit() {
      final upcoming =
          results.values
              .expand((items) => items)
              .where((item) => item.startsAt.isAfter(DateTime.now()))
              .toList()
            ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
      if (!controller.isClosed) controller.add(upcoming.firstOrNull);
    }

    linksSubscription = _firestore
        .collection('users')
        .doc(user.uid)
        .collection('players')
        .snapshots()
        .listen((links) async {
          for (final subscription in bookingSubscriptions) {
            await subscription.cancel();
          }
          bookingSubscriptions.clear();
          results.clear();
          if (links.docs.isEmpty) {
            emit();
            return;
          }
          for (final link in links.docs) {
            final subscription = _firestore
                .collection('bookings')
                .where('playerId', isEqualTo: link.id)
                .snapshots()
                .listen((snapshot) {
                  results[link.id] = snapshot.docs
                      .where(
                        (doc) =>
                            doc.data()['isDelete'] != true &&
                            doc.data()['status'] == 'confirmed' &&
                            doc.data()['startsAt'] is Timestamp,
                      )
                      .map((doc) {
                        final data = doc.data();
                        final startsAt = (data['startsAt'] as Timestamp)
                            .toDate();
                        return UpcomingBooking(
                          id: doc.id,
                          playerName: (data['playerName'] ?? 'Joueur')
                              .toString(),
                          title:
                              (data['title'] ??
                                      _sessionTitle(data['sessionType']))
                                  .toString(),
                          coachName: (data['coachName'] ?? 'Coach à définir')
                              .toString(),
                          courtName: (data['courtName'] ?? 'Lieu à définir')
                              .toString(),
                          startsAt: startsAt,
                          endsAt:
                              (data['endsAt'] as Timestamp?)?.toDate() ??
                              startsAt.add(const Duration(hours: 1)),
                        );
                      })
                      .toList();
                  emit();
                }, onError: controller.addError);
            bookingSubscriptions.add(subscription);
          }
        }, onError: controller.addError);
    controller.onCancel = () async {
      await linksSubscription?.cancel();
      for (final subscription in bookingSubscriptions) {
        await subscription.cancel();
      }
    };
    return controller.stream;
  }
}

String _sessionTitle(Object? type) => type == 'private'
    ? 'Séance privée'
    : type == 'semi_private'
    ? 'Séance semi-privée'
    : type == 'group'
    ? 'Séance de groupe'
    : 'Cours de tennis';
