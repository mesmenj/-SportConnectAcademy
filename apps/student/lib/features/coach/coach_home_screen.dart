import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/localization/app_language.dart';
import '../../core/navigation/app_access_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../data/firebase_tournament_repository.dart';

class CoachHomeScreen extends StatelessWidget {
  const CoachHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const LText('Espace coach'),
          actions: [
            IconButton(
              tooltip: tr('Déconnexion'),
              onPressed: () async {
                AppAccessController.revokeGuestAccess();
                await FirebaseAuth.instance.signOut();
                if (context.mounted) context.go('/welcome');
              },
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    user.displayName ?? tr('Coach'),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
              ),
              const TabBar(
                tabs: [
                  Tab(child: LText('À venir')),
                  Tab(child: LText('Cours passés')),
                  Tab(child: LText('Mes notes')),
                  Tab(child: LText('Tournois')),
                ],
              ),
              const Expanded(
                child: TabBarView(
                  children: [
                    _UpcomingSessions(),
                    _CourseHistory(),
                    _CoachNotes(),
                    _CoachTournaments(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpcomingSessions extends StatelessWidget {
  const _UpcomingSessions();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('sessions')
          .where('coachId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(
            child: LText('Impossible de charger vos séances.'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final sessions =
            snapshot.data!.docs.where((doc) {
              final start = doc.data()['startsAt'];
              return start is Timestamp &&
                  start.toDate().isAfter(DateTime.now());
            }).toList()..sort(
              (a, b) => (a.data()['startsAt'] as Timestamp).compareTo(
                b.data()['startsAt'] as Timestamp,
              ),
            );
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('bookings')
              .where('coachId', isEqualTo: uid)
              .snapshots(),
          builder: (context, bookingSnapshot) {
            final coachBookings =
                bookingSnapshot.data?.docs
                    .where(
                      (booking) =>
                          booking.data()['isDelete'] != true &&
                          [
                            'confirmed',
                            'completed',
                          ].contains(booking.data()['status']),
                    )
                    .toList() ??
                <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const LText(
                  'Voici vos prochaines séances planifiées.',
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 16),
                if (sessions.isEmpty)
                  const _CoachEmpty('Aucune séance à venir.'),
                ...sessions.map((doc) {
                  final data = doc.data();
                  final start = (data['startsAt'] as Timestamp).toDate();
                  final participants = coachBookings
                      .where((booking) => booking.data()['sessionId'] == doc.id)
                      .toList();
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const CircleAvatar(
                              child: Icon(Icons.sports_tennis),
                            ),
                            title: Text(
                              (data['title'] ?? tr('Séance')).toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(
                              '${DateFormat('EEE d MMM · HH:mm', AppLanguageController.isEnglish ? 'en_GB' : 'fr_FR').format(start)}\n${data['courtName'] ?? tr('Lieu à définir')} · ${data['bookedCount'] ?? 0}/${data['capacity'] ?? 0}',
                            ),
                            isThreeLine: true,
                          ),
                          const Divider(),
                          LText(
                            participants.isEmpty
                                ? 'Aucun participant confirmé.'
                                : 'Participants confirmés',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          ...participants.map(
                            (booking) => Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                '${booking.data()['playerName'] ?? tr('Joueur')} · ${booking.data()['communityName'] ?? tr('Aucune communauté')}',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            );
          },
        );
      },
    );
  }
}

class _CourseHistory extends StatelessWidget {
  const _CourseHistory();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('bookings')
          .where('coachId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final bookings =
            snapshot.data!.docs.where((document) {
              final start = document.data()['startsAt'];
              return [
                    'confirmed',
                    'completed',
                  ].contains(document.data()['status']) &&
                  document.data()['isDelete'] != true &&
                  start is Timestamp &&
                  !start.toDate().isAfter(DateTime.now());
            }).toList()..sort((a, b) {
              final left = a.data()['startsAt'] as Timestamp?;
              final right = b.data()['startsAt'] as Timestamp?;
              return (right?.millisecondsSinceEpoch ?? 0).compareTo(
                left?.millisecondsSinceEpoch ?? 0,
              );
            });
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              tr('Historique des cours'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            if (bookings.isEmpty)
              const _CoachEmpty('Aucun cours passé pour le moment.'),
            ...bookings.map((booking) {
              final data = booking.data();
              final startsAt = data['startsAt'] as Timestamp?;
              final canEvaluate =
                  startsAt != null &&
                  !startsAt.toDate().isAfter(DateTime.now());
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(child: Icon(Icons.person)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (data['playerName'] ?? tr('Joueur'))
                                      .toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  startsAt == null
                                      ? tr('Date à définir')
                                      : DateFormat(
                                          'EEE d MMM · HH:mm',
                                          AppLanguageController.isEnglish
                                              ? 'en_GB'
                                              : 'fr_FR',
                                        ).format(startsAt.toDate()),
                                ),
                                Text(
                                  '${tr('Communauté')} : ${data['communityName'] ?? tr('Aucune communauté')}',
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (data['attendanceStatus'] != null)
                            Chip(
                              label: LText(
                                data['attendanceStatus'] == 'present'
                                    ? 'Présent'
                                    : 'Absent',
                              ),
                              backgroundColor:
                                  data['attendanceStatus'] == 'present'
                                  ? const Color(0xFFEAF8EF)
                                  : const Color(0xFFFFECEC),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: canEvaluate
                                ? () => showDialog<void>(
                                    context: context,
                                    builder: (_) => _AttendanceDialog(
                                      bookingId: booking.id,
                                      playerName:
                                          (data['playerName'] ?? tr('Joueur'))
                                              .toString(),
                                    ),
                                  )
                                : null,
                            icon: const Icon(Icons.how_to_reg_outlined),
                            label: LText(
                              data['attendanceStatus'] == null
                                  ? 'Présence'
                                  : 'Modifier la présence',
                            ),
                          ),
                          FilledButton.tonal(
                            onPressed: canEvaluate
                                ? () => showDialog<void>(
                                    context: context,
                                    builder: (_) => _EvaluationDialog(
                                      bookingId: booking.id,
                                      playerName:
                                          (data['playerName'] ?? tr('Joueur'))
                                              .toString(),
                                    ),
                                  )
                                : null,
                            child: LText(canEvaluate ? 'Noter' : 'À venir'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _CoachNotes extends StatelessWidget {
  const _CoachNotes();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('playerEvaluations')
          .where('coachId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: LText('Impossible de charger vos notes.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final notes = snapshot.data!.docs.toList()
          ..sort((a, b) {
            final left = a.data()['evaluatedAt'] as Timestamp?;
            final right = b.data()['evaluatedAt'] as Timestamp?;
            return (right?.millisecondsSinceEpoch ?? 0).compareTo(
              left?.millisecondsSinceEpoch ?? 0,
            );
          });
        return _CoachNotesList(notes: notes);
      },
    );
  }
}

class _CoachNotesList extends StatelessWidget {
  const _CoachNotesList({required this.notes});

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> notes;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('bookings')
          .where('coachId', isEqualTo: uid)
          .snapshots(),
      builder: (context, bookingSnapshot) {
        if (bookingSnapshot.hasError) {
          return const Center(child: LText('Impossible de charger vos notes.'));
        }
        if (!bookingSnapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final bookingsById = {
          for (final booking in bookingSnapshot.data!.docs)
            if (booking.data()['isDelete'] != true) booking.id: booking.data(),
        };
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              tr('Historique des notes'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            if (notes.isEmpty)
              const _CoachEmpty('Aucune note enregistrée pour le moment.'),
            ...notes.map((document) {
              final data = document.data();
              final booking = bookingsById[document.id];
              final ratings = Map<String, dynamic>.from(
                data['ratings'] as Map? ?? {},
              );
              final average = (data['average'] as num?)?.toDouble() ?? 0;
              final date = data['startsAt'] as Timestamp?;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const CircleAvatar(child: Icon(Icons.person)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (data['playerName'] ??
                                          booking?['playerName'] ??
                                          tr('Joueur'))
                                      .toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                Text(
                                  '${data['sessionTitle'] ?? booking?['title'] ?? tr('Séance')}${date == null ? '' : ' · ${DateFormat('d MMM yyyy', AppLanguageController.isEnglish ? 'en_GB' : 'fr_FR').format(date.toDate())}'}',
                                  style: const TextStyle(
                                    color: AppColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.star_rounded,
                            color: AppColors.orange,
                          ),
                          Text(
                            '${average.toStringAsFixed(1)}/5',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children:
                            {
                                  'Technique': ratings['technical'],
                                  'Tactique': ratings['tactical'],
                                  'Physique': ratings['physical'],
                                  'Comportement': ratings['behavior'],
                                }.entries
                                .map(
                                  (entry) => Chip(
                                    label: Text(
                                      '${tr(entry.key)} ${entry.value ?? 0}/5',
                                    ),
                                  ),
                                )
                                .toList(),
                      ),
                      if ((data['comment'] ?? '')
                          .toString()
                          .trim()
                          .isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(data['comment'].toString()),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}

class _CoachTournaments extends StatelessWidget {
  const _CoachTournaments();

  @override
  Widget build(BuildContext context) => StreamBuilder<List<TournamentRecord>>(
    stream: FirebaseTournamentRepository().watchTournaments(),
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return const Center(
          child: LText('Impossible de charger les tournois.'),
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final tournaments = snapshot.data!;
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (tournaments.isEmpty) const _CoachEmpty('Aucun tournoi publié.'),
          ...tournaments.map(
            (tournament) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (tournament.imageUrl != null)
                    Image.network(
                      tournament.imageUrl!,
                      width: double.infinity,
                      height: 130,
                      fit: BoxFit.cover,
                    ),
                  ListTile(
                    leading: tournament.imageUrl == null
                        ? const CircleAvatar(child: Icon(Icons.emoji_events))
                        : null,
                    title: Text(
                      tournament.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '${DateFormat('EEE d MMM · HH:mm', AppLanguageController.isEnglish ? 'en_GB' : 'fr_FR').format(tournament.startsAt)}\n${tournament.venue} · ${tournament.category}\n${tournament.registeredCount}/${tournament.capacity} ${tr('joueurs')}',
                    ),
                    isThreeLine: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _CoachEmpty extends StatelessWidget {
  const _CoachEmpty(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Center(child: LText(message, textAlign: TextAlign.center)),
    ),
  );
}

class _AttendanceDialog extends StatefulWidget {
  const _AttendanceDialog({required this.bookingId, required this.playerName});
  final String bookingId, playerName;
  @override
  State<_AttendanceDialog> createState() => _AttendanceDialogState();
}

class _AttendanceDialogState extends State<_AttendanceDialog> {
  bool? attended;
  bool loading = false;
  String? error;

  Future<void> submit() async {
    if (attended == null) {
      setState(() => error = 'Confirmez la présence ou l’absence du joueur.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await FirebaseFunctions.instanceFor(
        region: 'europe-west1',
      ).httpsCallable('recordPlayerAttendance').call(<String, Object?>{
        'bookingId': widget.bookingId,
        'attended': attended,
      });
      if (mounted) Navigator.pop(context);
    } on FirebaseFunctionsException catch (exception) {
      if (mounted) {
        setState(
          () => error = exception.message ?? 'Enregistrement impossible.',
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(tr('Présence de ${widget.playerName}')),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (error != null) ...[
          LText(error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 8),
        ],
        RadioGroup<bool>(
          groupValue: attended,
          onChanged: (value) => setState(() => attended = value),
          child: const Column(
            children: [
              RadioListTile<bool>(
                value: true,
                title: LText('Le joueur a assisté à la séance'),
              ),
              RadioListTile<bool>(
                value: false,
                title: LText('Le joueur était absent'),
              ),
            ],
          ),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: loading ? null : () => Navigator.pop(context),
        child: const LText('Annuler'),
      ),
      FilledButton(
        onPressed: loading ? null : submit,
        child: LText(loading ? 'Enregistrement...' : 'Confirmer'),
      ),
    ],
  );
}

class _EvaluationDialog extends StatefulWidget {
  const _EvaluationDialog({required this.bookingId, required this.playerName});
  final String bookingId;
  final String playerName;

  @override
  State<_EvaluationDialog> createState() => _EvaluationDialogState();
}

class _EvaluationDialogState extends State<_EvaluationDialog> {
  final comment = TextEditingController();
  final ratings = <String, int>{
    'technical': 3,
    'tactical': 3,
    'physical': 3,
    'behavior': 3,
  };
  bool loading = false;
  String? error;

  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await FirebaseFunctions.instanceFor(
        region: 'europe-west1',
      ).httpsCallable('submitCoachEvaluation').call(<String, Object>{
        'bookingId': widget.bookingId,
        'ratings': ratings,
        'comment': comment.text.trim(),
      });
      if (mounted) Navigator.pop(context);
    } on FirebaseFunctionsException catch (exception) {
      setState(() => error = exception.message ?? tr('Évaluation impossible.'));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${tr('Évaluer')} ${widget.playerName}'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (error != null) ...[
            LText(error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 10),
          ],
          ...<String, String>{
            'technical': 'Technique',
            'tactical': 'Tactique',
            'physical': 'Physique',
            'behavior': 'Comportement',
          }.entries.map(
            (criterion) => Row(
              children: [
                Expanded(child: LText(criterion.value)),
                DropdownButton<int>(
                  value: ratings[criterion.key],
                  items: List.generate(
                    5,
                    (index) => DropdownMenuItem(
                      value: index + 1,
                      child: Text('${index + 1}/5'),
                    ),
                  ),
                  onChanged: (value) =>
                      setState(() => ratings[criterion.key] = value ?? 3),
                ),
              ],
            ),
          ),
          TextField(
            controller: comment,
            maxLength: 1000,
            maxLines: 4,
            decoration: InputDecoration(labelText: tr('Commentaire du coach')),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: loading ? null : () => Navigator.pop(context),
        child: const LText('Annuler'),
      ),
      FilledButton(
        onPressed: loading ? null : submit,
        child: loading
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const LText('Enregistrer'),
      ),
    ],
  );
}
