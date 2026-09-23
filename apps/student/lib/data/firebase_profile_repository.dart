import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/localization/app_language.dart';

class ChildProfile {
  const ChildProfile({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.age,
    required this.gender,
    required this.academyName,
    required this.academyId,
    required this.progress,
    required this.sessionCount,
    required this.playMinutes,
    required this.badgeCount,
    required this.totalSessions,
    required this.remainingSessions,
    required this.status,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.createdAt,
  });
  final String id, firstName, lastName, gender, academyName, academyId;
  final int age;
  final int progress, sessionCount, playMinutes, badgeCount;
  final int totalSessions, remainingSessions;
  final String status, paymentMethod, paymentStatus;
  final DateTime createdAt;
  String get displayName => '$firstName $lastName'.trim();
}

class FirebaseProfileRepository {
  FirebaseProfileRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _firestore = firestore ?? FirebaseFirestore.instance,
       _functions =
           functions ?? FirebaseFunctions.instanceFor(region: 'europe-west1');
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  Future<List<PlayerSessionConfiguration>> loadPlayerConfigurations() async {
    final result = await _functions
        .httpsCallable('getPlayerCreationOptions')
        .call();
    final data = Map<String, dynamic>.from(result.data as Map);
    return (data['configurations'] as List? ?? const [])
        .map(
          (item) => PlayerSessionConfiguration.fromMap(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  Stream<List<ChildProfile>> watchChildren() => _auth
      .userChanges()
      .distinct((previous, next) => previous?.uid == next?.uid)
      .asyncExpand(
        (user) => user == null
            ? Stream<List<ChildProfile>>.value(const [])
            : _watchChildren(user),
      );

  Stream<List<ChildProfile>> _watchChildren(User user) {
    late final StreamController<List<ChildProfile>> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? linksSubscription;
    StreamSubscription<List<ChildProfile>>? playersSubscription;

    controller = StreamController<List<ChildProfile>>(
      onListen: () {
        linksSubscription = _firestore
            .collection('users')
            .doc(user.uid)
            .collection('players')
            .snapshots()
            .listen((links) async {
              await playersSubscription?.cancel();
              if (controller.isClosed) return;
              playersSubscription = _combinePlayers(
                links.docs.map((document) => document.id),
              ).listen(controller.add, onError: controller.addError);
            }, onError: controller.addError);
      },
      onCancel: () async {
        await linksSubscription?.cancel();
        await playersSubscription?.cancel();
      },
    );
    return controller.stream;
  }

  Stream<List<ChildProfile>> _combinePlayers(Iterable<String> playerIds) {
    final streams = playerIds.map(_watchPlayer).toList();
    if (streams.isEmpty) return Stream.value(const []);

    late final StreamController<List<ChildProfile>> controller;
    final values = List<ChildProfile?>.filled(streams.length, null);
    final ready = List<bool>.filled(streams.length, false);
    final subscriptions = <StreamSubscription<ChildProfile?>>[];

    controller = StreamController<List<ChildProfile>>(
      onListen: () {
        for (var index = 0; index < streams.length; index++) {
          subscriptions.add(
            streams[index].listen((player) {
              values[index] = player;
              ready[index] = true;
              if (ready.every((value) => value) && !controller.isClosed) {
                final players = values.whereType<ChildProfile>().toList()
                  ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
                controller.add(players);
              }
            }, onError: controller.addError),
          );
        }
      },
      onCancel: () async {
        await Future.wait(
          subscriptions.map((subscription) => subscription.cancel()),
        );
      },
    );
    return controller.stream;
  }

  Stream<ChildProfile?> _watchPlayer(
    String playerId,
  ) => _firestore.collection('players').doc(playerId).snapshots().asyncExpand((
    doc,
  ) {
    if (!doc.exists || doc.data()?['isDelete'] == true) {
      return Stream<ChildProfile?>.value(null);
    }
    return _firestore
        .collection('bookings')
        .where('playerId', isEqualTo: playerId)
        .snapshots()
        .asyncExpand(
          (bookings) => _firestore
              .collection('playerEvaluations')
              .where('playerId', isEqualTo: playerId)
              .snapshots()
              .map((evaluations) {
                final data = doc.data()!;
                final activeBookings = bookings.docs.where((booking) {
                  if (booking.data()['isDelete'] == true) return false;
                  final status = booking.data()['status'];
                  return status == 'pending' ||
                      status == 'confirmed' ||
                      status == 'completed';
                }).toList();
                final playMinutes = bookings.docs
                    .where((booking) => booking.data()['status'] == 'completed')
                    .fold<int>(0, (total, booking) {
                      final startsAt = booking.data()['startsAt'];
                      final endsAt = booking.data()['endsAt'];
                      if (startsAt is! Timestamp || endsAt is! Timestamp) {
                        return total;
                      }
                      return total +
                          endsAt
                              .toDate()
                              .difference(startsAt.toDate())
                              .inMinutes;
                    });
                final averages = evaluations.docs
                    .map((evaluation) => evaluation.data()['average'])
                    .whereType<num>()
                    .map((value) => value.toDouble())
                    .toList();
                final progress = averages.isEmpty
                    ? 0
                    : ((averages.reduce((total, value) => total + value) /
                                  averages.length) *
                              20)
                          .round()
                          .clamp(0, 100);
                final displayName = (data['displayName'] ?? data['name'] ?? '')
                    .toString()
                    .trim()
                    .split(RegExp(r'\s+'));
                return ChildProfile(
                  id: doc.id,
                  firstName:
                      (data['firstName'] ??
                              (displayName.isNotEmpty ? displayName.first : ''))
                          .toString(),
                  lastName:
                      (data['lastName'] ??
                              (displayName.length > 1
                                  ? displayName.skip(1).join(' ')
                                  : ''))
                          .toString(),
                  age: (data['age'] as num?)?.toInt() ?? 0,
                  gender: (data['gender'] ?? 'other').toString(),
                  academyName: (data['academyName'] ?? '').toString(),
                  academyId: (data['academyId'] ?? '').toString(),
                  progress: progress,
                  sessionCount: activeBookings.length,
                  playMinutes: playMinutes,
                  badgeCount: (data['badgeCount'] as num?)?.toInt() ?? 0,
                  totalSessions: (data['sessionCount'] as num?)?.toInt() ?? 0,
                  remainingSessions:
                      (data['remainingSessions'] as num?)?.toInt() ?? 0,
                  status: (data['status'] ?? 'active').toString(),
                  paymentMethod: (data['paymentMethod'] ?? '').toString(),
                  paymentStatus: (data['paymentStatus'] ?? '').toString(),
                  createdAt: data['createdAt'] is Timestamp
                      ? (data['createdAt'] as Timestamp).toDate()
                      : DateTime.fromMillisecondsSinceEpoch(0),
                );
              }),
        );
  });

  Future<void> addChild({
    required String firstName,
    required String lastName,
    required int age,
    required String gender,
    required String sessionConfigurationId,
    required String paymentMethod,
  }) async {
    await _functions.httpsCallable('createPlayerProfile').call(<String, Object>{
      'firstName': firstName,
      'lastName': lastName,
      'age': age,
      'gender': gender,
      'sessionConfigurationId': sessionConfigurationId,
      'paymentMethod': paymentMethod,
    });
  }

  Future<void> updateChild({
    required String playerId,
    required String firstName,
    required String lastName,
    required int age,
    required String gender,
  }) async {
    await _functions.httpsCallable('updatePlayerProfile').call(<String, Object>{
      'playerId': playerId,
      'firstName': firstName,
      'lastName': lastName,
      'age': age,
      'gender': gender,
    });
  }

  Future<void> updateMyProfile({
    required String displayName,
    required String phone,
  }) async {
    await _functions.httpsCallable('updateMyProfile').call(<String, Object>{
      'displayName': displayName,
      'phone': phone,
      'preferredLanguage': AppLanguageController.isEnglish ? 'en' : 'fr',
    });
    await _auth.currentUser?.reload();
  }

  Future<void> updatePreferredLanguage() async {
    if (_auth.currentUser == null) return;
    await _functions.httpsCallable('updateMyProfile').call(<String, Object>{
      'preferredLanguage': AppLanguageController.isEnglish ? 'en' : 'fr',
    });
  }
}

class PlayerSessionConfiguration {
  const PlayerSessionConfiguration({
    required this.id,
    required this.activityType,
    required this.type,
    required this.minAge,
    required this.maximumAge,
    required this.price,
    required this.currency,
    required this.sessionCount,
    this.dayOfWeek,
    this.startTime,
    this.durationMinutes,
  });
  final String id, activityType, type, currency;
  final int minAge;
  final int sessionCount;
  final int? maximumAge;
  final num price;
  final int? dayOfWeek;
  final String? startTime;
  final int? durationMinutes;

  factory PlayerSessionConfiguration.fromMap(Map<String, dynamic> data) =>
      PlayerSessionConfiguration(
        id: data['id'].toString(),
        activityType: (data['activityType'] ?? 'tennis').toString(),
        type: data['type'].toString(),
        minAge: (data['minAge'] as num).toInt(),
        maximumAge: (data['maximumAge'] as num?)?.toInt(),
        price: (data['price'] as num?) ?? 0,
        currency: (data['currency'] ?? 'AED').toString(),
        sessionCount: (data['sessionCount'] as num?)?.toInt() ?? 1,
        dayOfWeek: (data['dayOfWeek'] as num?)?.toInt(),
        startTime: data['startTime']?.toString(),
        durationMinutes: (data['durationMinutes'] as num?)?.toInt(),
      );

  bool accepts(int age) => age >= minAge && age <= (maximumAge ?? minAge);

  String get _formattedPrice => price == price.roundToDouble()
      ? price.toInt().toString()
      : price.toString();

  String get _activityInitials => activityType == 'padel' ? 'PS' : 'TS';

  String get _shortSessionType => type == 'private'
      ? 'Privée'
      : type == 'semi_private'
      ? 'Semi-privée'
      : 'Groupe';

  /// Short label shown after a configuration has been selected.
  String get compactLabel => activityType == 'padel'
      ? 'Paddle · ${durationMinutes ?? 90} minutes · $_formattedPrice $currency'
      : '$_activityInitials · $_shortSessionType · $_formattedPrice $currency';

  String get label {
    if (activityType == 'padel') {
      return 'Paddle · ${durationMinutes ?? 90} minutes · $_formattedPrice $currency';
    }
    final activity = activityType == 'padel'
        ? 'Paddle session'
        : 'Tennis session';
    final session = type == 'private'
        ? 'Séance privée'
        : type == 'semi_private'
        ? 'Séance semi-privée'
        : 'Séance de groupe';
    final ages = maximumAge == null ? '$minAge ans' : '$minAge–$maximumAge ans';
    return '$activity · $session · $ages · $_formattedPrice $currency';
  }
}
