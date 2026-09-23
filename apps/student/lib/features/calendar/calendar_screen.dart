import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/localization/app_language.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../data/firebase_booking_repository.dart';

enum _Filter { all, upcoming, past }

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final repository = FirebaseBookingRepository();
  late DateTime month, selectedDay;
  _Filter filter = _Filter.all;
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    month = DateTime(now.year, now.month);
    selectedDay = DateTime(now.year, now.month, now.day);
  }

  void moveMonth(int offset) => setState(() {
    month = DateTime(month.year, month.month + offset);
    final now = DateTime.now();
    selectedDay = now.year == month.year && now.month == month.month
        ? DateTime(now.year, now.month, now.day)
        : month;
  });
  bool accepts(BookingHistoryItem item) => switch (filter) {
    _Filter.all => true,
    _Filter.upcoming =>
      item.startsAt.isAfter(DateTime.now()) &&
          !['cancelled', 'rejected'].contains(item.status),
    _Filter.past =>
      !item.startsAt.isAfter(DateTime.now()) ||
          ['cancelled', 'rejected'].contains(item.status),
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: StreamBuilder<List<BookingHistoryItem>>(
        stream: repository.watchBookingHistory(),
        builder: (context, snapshot) {
          final items = (snapshot.data ?? const <BookingHistoryItem>[])
              .where(accepts)
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 120),
            children: [
              LText(
                'Historique des réservations',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 6),
              const LText(
                'Consultez les séances à venir et les réservations passées de vos joueurs.',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 18),
              SegmentedButton<_Filter>(
                segments: const [
                  ButtonSegment(value: _Filter.all, label: LText('Toutes')),
                  ButtonSegment(
                    value: _Filter.upcoming,
                    label: LText('À venir'),
                  ),
                  ButtonSegment(value: _Filter.past, label: LText('Passées')),
                ],
                selected: {filter},
                showSelectedIcon: false,
                onSelectionChanged: (value) =>
                    setState(() => filter = value.first),
              ),
              const SizedBox(height: 18),
              if (snapshot.connectionState == ConnectionState.waiting)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (snapshot.hasError)
                const _Empty(
                  Icons.cloud_off_outlined,
                  'Impossible de charger l’historique.',
                )
              else if (FirebaseAuth.instance.currentUser == null)
                _Empty(
                  Icons.lock_outline,
                  'Connectez-vous pour consulter vos réservations.',
                  action: 'Ouvrir mon profil',
                  onTap: () => context.go('/profile'),
                )
              else ...[
                _Calendar(
                  month: month,
                  selected: selectedDay,
                  bookings: items,
                  previous: () => moveMonth(-1),
                  next: () => moveMonth(1),
                  onSelect: (value) => setState(() => selectedDay = value),
                ),
                const SizedBox(height: 22),
                _Day(day: selectedDay, bookings: items),
                const SizedBox(height: 24),
                SectionTitle(
                  'Historique du mois',
                  action:
                      '${items.where((e) => _sameMonth(e.startsAt, month)).length}',
                ),
                _History(month: month, bookings: items),
              ],
            ],
          );
        },
      ),
    ),
  );
}

class _Calendar extends StatelessWidget {
  const _Calendar({
    required this.month,
    required this.selected,
    required this.bookings,
    required this.previous,
    required this.next,
    required this.onSelect,
  });
  final DateTime month, selected;
  final List<BookingHistoryItem> bookings;
  final VoidCallback previous, next;
  final ValueChanged<DateTime> onSelect;
  @override
  Widget build(BuildContext context) {
    final locale = AppLanguageController.isEnglish ? 'en_US' : 'fr_FR';
    final offset = month.weekday - 1;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final count = ((offset + days + 6) ~/ 7) * 7;
    final labels = AppLanguageController.isEnglish
        ? ['M', 'T', 'W', 'T', 'F', 'S', 'S']
        : ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    return PremiumCard(
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: previous,
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  DateFormat('MMMM yyyy', locale).format(month).toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: .7,
                  ),
                ),
              ),
              IconButton(
                onPressed: next,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: labels
                .map(
                  (e) => SizedBox(
                    width: 34,
                    child: Text(
                      e,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.muted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
            ),
            itemCount: count,
            itemBuilder: (_, index) {
              final number = index - offset + 1;
              if (number < 1 || number > days) return const SizedBox.shrink();
              final day = DateTime(month.year, month.month, number);
              final active = _sameDay(day, selected);
              final events = bookings
                  .where((e) => _sameDay(e.startsAt, day))
                  .toList();
              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onSelect(day),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  margin: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: active ? AppColors.ink : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$number',
                        style: TextStyle(
                          color: active ? Colors.white : AppColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (events.isNotEmpty)
                        Container(
                          margin: const EdgeInsets.only(top: 3),
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: events.any((e) => e.status == 'confirmed')
                                ? AppColors.green
                                : AppColors.orange,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({required this.day, required this.bookings});
  final DateTime day;
  final List<BookingHistoryItem> bookings;
  @override
  Widget build(BuildContext context) {
    final locale = AppLanguageController.isEnglish ? 'en_US' : 'fr_FR';
    final items = bookings.where((e) => _sameDay(e.startsAt, day)).toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                DateFormat('EEEE d MMMM', locale).format(day),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Text(
              '${items.length} ${tr(items.length > 1 ? 'réservations' : 'réservation')}',
              style: const TextStyle(color: AppColors.muted),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (items.isEmpty)
          const _Empty(
            Icons.event_available_outlined,
            'Aucune réservation pour cette date.',
          )
        else
          ...items.map(_BookingCard.new),
      ],
    );
  }
}

class _History extends StatelessWidget {
  const _History({required this.month, required this.bookings});
  final DateTime month;
  final List<BookingHistoryItem> bookings;
  @override
  Widget build(BuildContext context) {
    final items = bookings.where((e) => _sameMonth(e.startsAt, month)).toList()
      ..sort((a, b) => b.startsAt.compareTo(a.startsAt));
    return items.isEmpty
        ? const _Empty(Icons.history, 'Aucune réservation dans cette période.')
        : Column(children: items.map(_BookingCard.new).toList());
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard(this.item);
  final BookingHistoryItem item;
  @override
  Widget build(BuildContext context) {
    final presentation = _status(item.status);
    final locale = AppLanguageController.isEnglish ? 'en_US' : 'fr_FR';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PremiumCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 5,
              height: 76,
              decoration: BoxDecoration(
                color: presentation.$2,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          localizedSessionTitle(item.title),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      Chip(
                        label: LText(presentation.$1),
                        backgroundColor: presentation.$2.withValues(alpha: .14),
                        side: BorderSide.none,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  Text(
                    '${item.playerName} · ${DateFormat('d MMM · HH:mm', locale).format(item.startsAt)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${tr(item.coachName)} · ${tr(item.courtName)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.icon, this.message, {this.action, this.onTap});
  final IconData icon;
  final String message;
  final String? action;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => PremiumCard(
    child: Column(
      children: [
        Icon(icon, size: 38, color: AppColors.sky),
        const SizedBox(height: 10),
        LText(message, textAlign: TextAlign.center),
        if (action != null) ...[
          const SizedBox(height: 8),
          TextButton(onPressed: onTap, child: LText(action!)),
        ],
      ],
    ),
  );
}

(String, Color) _status(String value) => switch (value) {
  'confirmed' => ('Confirmée', AppColors.green),
  'completed' => ('Terminée', AppColors.blue),
  'cancelled' => ('Annulée', AppColors.muted),
  'rejected' => ('Refusée', Colors.red),
  _ => ('En attente', AppColors.orange),
};
bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
bool _sameMonth(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month;
