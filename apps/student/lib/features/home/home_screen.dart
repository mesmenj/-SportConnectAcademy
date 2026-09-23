import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import '../../core/localization/app_language.dart';
import '../../core/widgets/ui.dart';
import '../../data/firebase_booking_repository.dart';
import '../../data/firebase_profile_repository.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: FirebaseAuth.instance.userChanges(),
    initialData: FirebaseAuth.instance.currentUser,
    builder: (context, authSnapshot) => Scaffold(
      key: ValueKey(
        'home-${authSnapshot.data?.uid ?? 'guest'}-${authSnapshot.data?.displayName ?? ''}',
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
              sliver: SliverList.list(
                children: [
                  FadeIn(
                    child: StreamBuilder<User?>(
                      stream: FirebaseAuth.instance.userChanges(),
                      initialData: FirebaseAuth.instance.currentUser,
                      builder: (context, snapshot) {
                        final user = snapshot.data;
                        final firstName = _firstName(user?.displayName);
                        return Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _todayLabel(context),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      letterSpacing: 1.2,
                                      color: AppColors.muted,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  LText(
                                    user == null || firstName.isEmpty
                                        ? 'Bonjour'
                                        : 'Bonjour $firstName 👋',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineSmall,
                                  ),
                                ],
                              ),
                            ),
                            Pressable(
                              onTap: () => _notifications(context),
                              child: Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: AppColors.cloud,
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: const Icon(
                                  Icons.notifications_none_rounded,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Pressable(
                              onTap: () => context.go('/profile'),
                              child: user == null
                                  ? Container(
                                      width: 46,
                                      height: 46,
                                      decoration: BoxDecoration(
                                        color: AppColors.cloud,
                                        borderRadius: BorderRadius.circular(15),
                                      ),
                                      child: const Icon(
                                        Icons.person_outline_rounded,
                                      ),
                                    )
                                  : PersonAvatar(
                                      initials: _initials(
                                        user.displayName ?? user.email ?? 'U',
                                      ),
                                      color: AppColors.lilac,
                                    ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 26),
                  FadeIn(
                    delay: const Duration(milliseconds: 80),
                    child: _NextSessionCard(
                      onTap: () => context.go('/calendar'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _RealHomeSections(),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  void _notifications(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SizedBox(
        height: 430,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LText(
                'Notifications',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              const Expanded(
                child: Center(
                  child: LText(
                    'Aucune notification pour le moment.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _firstName(String? displayName) =>
    (displayName ?? '').trim().split(RegExp(r'\s+')).firstOrNull ?? '';
String _initials(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .where((part) => part.isNotEmpty)
    .take(2)
    .map((part) => part[0].toUpperCase())
    .join();

String _todayLabel(BuildContext context) {
  final language = Localizations.localeOf(context).languageCode;
  final locale = language == 'en' ? 'en_US' : 'fr_FR';
  final pattern = language == 'en' ? 'EEEE, MMMM d' : 'EEEE d MMMM';
  return DateFormat(pattern, locale).format(DateTime.now()).toUpperCase();
}

class _NextSessionCard extends StatelessWidget {
  const _NextSessionCard({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => StreamBuilder<UpcomingBooking?>(
    stream: FirebaseBookingRepository().watchNextConfirmedSession(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const SizedBox(
          height: 205,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return _HeroSession(
        session: snapshot.data,
        onTap: snapshot.data == null ? () => context.go('/booking') : onTap,
      );
    },
  );
}

class _HeroSession extends StatelessWidget {
  const _HeroSession({required this.session, required this.onTap});
  final UpcomingBooking? session;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final item = session;
    final locale = Localizations.localeOf(context).languageCode == 'en'
        ? 'en_US'
        : 'fr_FR';
    final duration = item == null
        ? Duration.zero
        : item.endsAt.difference(item.startsAt);
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 205,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF111111), Color(0xFF24364B)],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x30111111),
              blurRadius: 28,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const LText(
                  'PROCHAINE SÉANCE',
                  style: TextStyle(
                    color: AppColors.sky,
                    letterSpacing: 1.2,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: LText(
                    item == null
                        ? 'AUCUNE SÉANCE'
                        : _relativeDate(item.startsAt, locale),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            LText(
              item == null
                  ? '—'
                  : DateFormat('HH:mm', locale).format(item.startsAt),
              style: TextStyle(
                fontSize: 43,
                fontWeight: FontWeight.w900,
                letterSpacing: -2,
                color: Colors.white,
              ),
            ),
            LText(
              item == null
                  ? 'Réservez une séance pour commencer.'
                  : '${item.title} · ${_durationLabel(duration)} · ${item.playerName}',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                PersonAvatar(
                  initials: item == null ? '?' : _initials(item.coachName),
                  size: 34,
                  color: AppColors.blue,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: LText(
                    item == null
                        ? 'Voir les séances disponibles'
                        : '${item.coachName} · ${item.courtName}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded, color: Colors.white),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _durationLabel(Duration value) => value.inMinutes % 60 == 0
    ? '${value.inHours}h'
    : '${value.inHours}h${(value.inMinutes % 60).toString().padLeft(2, '0')}';
String _relativeDate(DateTime value, String locale) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(value.year, value.month, value.day);
  if (day == today) return locale.startsWith('en') ? 'TODAY' : 'AUJOURD’HUI';
  if (day == today.add(const Duration(days: 1))) {
    return locale.startsWith('en') ? 'TOMORROW' : 'DEMAIN';
  }
  return DateFormat('EEE d MMM', locale).format(value).toUpperCase();
}

class _RealHomeSections extends StatefulWidget {
  const _RealHomeSections();

  @override
  State<_RealHomeSections> createState() => _RealHomeSectionsState();
}

class _RealHomeSectionsState extends State<_RealHomeSections> {
  String? selectedPlayerId;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<ChildProfile>>(
    stream: FirebaseProfileRepository().watchChildren(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      final children = snapshot.data ?? const <ChildProfile>[];
      if (FirebaseAuth.instance.currentUser == null) {
        return _HomeEmptyState(
          icon: Icons.person_outline,
          message: 'Connectez-vous pour afficher vos joueurs et leur suivi.',
          action: 'Ouvrir mon profil',
          onTap: () => context.go('/profile'),
        );
      }
      if (children.isEmpty) {
        return _HomeEmptyState(
          icon: Icons.person_add_alt_1,
          message: 'Ajoutez un joueur pour afficher son suivi réel.',
          action: 'Ajouter un joueur',
          onTap: () => context.go('/profile'),
        );
      }
      final selected = children.firstWhere(
        (child) => child.id == selectedPlayerId,
        orElse: () => children.first,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (children.length > 1) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: children
                    .map(
                      (child) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(child.firstName),
                          selected: child.id == selected.id,
                          onSelected: (_) =>
                              setState(() => selectedPlayerId = child.id),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 18),
          ],
          SectionTitle(
            '${selected.firstName} ${tr('en ce moment')}',
            action: tr('Voir le profil'),
            onTap: () => context.go('/profile'),
          ),
          _ChildCard(child: selected, onTap: () => context.go('/profile')),
          const SizedBox(height: 24),
          const SectionTitle('Actions rapides'),
          Row(
            children: [
              Expanded(
                child: _Quick(
                  Icons.add_rounded,
                  'Réserver',
                  AppColors.sky,
                  () => context.go('/booking'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Quick(
                  Icons.emoji_events_outlined,
                  'Tournois',
                  AppColors.orange,
                  () => context.go('/tournaments'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _PlayerActivity(playerId: selected.id),
        ],
      );
    },
  );
}

class _PlayerActivity extends StatelessWidget {
  const _PlayerActivity({required this.playerId});
  final String playerId;

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection('bookings')
        .where('playerId', isEqualTo: playerId)
        .snapshots(),
    builder: (context, bookingSnapshot) {
      final bookings = bookingSnapshot.data?.docs ?? const [];
      final now = DateTime.now();
      final weekStart = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(Duration(days: now.weekday - 1));
      final weekEnd = weekStart.add(const Duration(days: 7));
      final weekly = bookings.where((document) {
        final data = document.data();
        if (data['isDelete'] == true) return false;
        final start = data['startsAt'];
        return start is Timestamp &&
            !start.toDate().isBefore(weekStart) &&
            start.toDate().isBefore(weekEnd) &&
            ['confirmed', 'completed'].contains(data['status']);
      }).toList();
      final minutes = weekly.fold<int>(0, (total, document) {
        final data = document.data();
        final start = data['startsAt'] as Timestamp?;
        final end = data['endsAt'] as Timestamp?;
        return total +
            (start == null || end == null
                ? 0
                : end.toDate().difference(start.toDate()).inMinutes);
      });
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('Cette semaine'),
          PremiumCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _Metric(
                  '${weekly.length}',
                  'séances',
                  Icons.sports_tennis,
                  AppColors.sky,
                ),
                _Metric(
                  _minutesLabel(minutes),
                  'sur le court',
                  Icons.timer_outlined,
                  AppColors.green,
                ),
                _Metric(
                  '${bookings.where((item) => item.data()['status'] == 'completed').length}',
                  'terminées',
                  Icons.check_circle_outline,
                  AppColors.orange,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionTitle('Dernière évaluation du coach'),
          _LatestEvaluation(playerId: playerId),
        ],
      );
    },
  );
}

class _LatestEvaluation extends StatelessWidget {
  const _LatestEvaluation({required this.playerId});
  final String playerId;

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: FirebaseFirestore.instance
        .collection('playerEvaluations')
        .where('playerId', isEqualTo: playerId)
        .snapshots(),
    builder: (context, snapshot) {
      final evaluations = snapshot.data?.docs.toList() ?? [];
      evaluations.sort((a, b) {
        final left = a.data()['evaluatedAt'] as Timestamp?;
        final right = b.data()['evaluatedAt'] as Timestamp?;
        return (right?.millisecondsSinceEpoch ?? 0).compareTo(
          left?.millisecondsSinceEpoch ?? 0,
        );
      });
      if (evaluations.isEmpty) {
        return const PremiumCard(
          child: LText(
            'Aucune évaluation enregistrée pour ce joueur.',
            style: TextStyle(color: AppColors.muted),
          ),
        );
      }
      final data = evaluations.first.data();
      final ratings = Map<String, dynamic>.from(data['ratings'] as Map? ?? {});
      final average = (data['average'] as num?)?.toDouble() ?? 0;
      return PremiumCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.star_rounded, color: AppColors.orange),
                const SizedBox(width: 6),
                Text(
                  '${average.toStringAsFixed(1)}/5',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  {
                        'Technique': ratings['technical'],
                        'Tactique': ratings['tactical'],
                        'Physique': ratings['physical'],
                        'Comportement': ratings['behavior'],
                      }.entries
                      .map(
                        (item) => Chip(
                          label: Text('${tr(item.key)} ${item.value ?? 0}/5'),
                        ),
                      )
                      .toList(),
            ),
            if ((data['comment'] ?? '').toString().trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(data['comment'].toString()),
            ],
          ],
        ),
      );
    },
  );
}

class _HomeEmptyState extends StatelessWidget {
  const _HomeEmptyState({
    required this.icon,
    required this.message,
    required this.action,
    required this.onTap,
  });
  final IconData icon;
  final String message, action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PremiumCard(
    child: Column(
      children: [
        Icon(icon, size: 42, color: AppColors.sky),
        const SizedBox(height: 12),
        LText(message, textAlign: TextAlign.center),
        const SizedBox(height: 14),
        TextButton(onPressed: onTap, child: LText(action)),
      ],
    ),
  );
}

String _minutesLabel(int minutes) {
  if (minutes < 60) return '${minutes}min';
  final remainder = minutes % 60;
  return remainder == 0
      ? '${minutes ~/ 60}h'
      : '${minutes ~/ 60}h${remainder.toString().padLeft(2, '0')}';
}

class _ChildCard extends StatelessWidget {
  const _ChildCard({required this.child, required this.onTap});
  final ChildProfile child;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    child: PremiumCard(
      child: Row(
        children: [
          PersonAvatar(
            initials: _initials(child.displayName),
            size: 64,
            color: AppColors.sky,
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  child.displayName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '${child.age} ${tr('ans')}${child.academyName.isEmpty ? '' : ' · ${child.academyName}'}',
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(9),
                        child: LinearProgressIndicator(
                          value: child.progress / 100,
                          minHeight: 8,
                          backgroundColor: AppColors.cloud,
                          color: AppColors.green,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      '${child.progress}%',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.cloud,
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
          ),
        ],
      ),
    ),
  );
}

class _Quick extends StatelessWidget {
  const _Quick(this.icon, this.label, this.color, this.onTap);
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    child: Container(
      height: 94,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.ink, size: 28),
          const SizedBox(height: 8),
          LText(
            label,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric(this.value, this.label, this.icon, this.color);
  final String value, label;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(icon, color: color),
      const SizedBox(height: 7),
      LText(
        value,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
      ),
      LText(
        label,
        style: const TextStyle(fontSize: 11, color: AppColors.muted),
      ),
    ],
  );
}
