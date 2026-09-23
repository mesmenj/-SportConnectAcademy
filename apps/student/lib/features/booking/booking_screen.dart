import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/localization/app_language.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../data/firebase_booking_repository.dart';
import '../auth/auth_sheet.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  static const contactNumber = '+971589081892';
  final repository = FirebaseBookingRepository();
  final rejecting = <String>{};
  User? user;
  StreamSubscription<User?>? authSubscription;

  @override
  void initState() {
    super.initState();
    user = FirebaseAuth.instance.currentUser;
    authSubscription = FirebaseAuth.instance.userChanges().listen((next) {
      if (mounted) setState(() => user = next);
    });
  }

  @override
  void dispose() {
    authSubscription?.cancel();
    super.dispose();
  }

  Future<void> launchContact(Uri uri) async {
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('URL_NOT_OPENED');
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LText('Impossible d’ouvrir cette application.'),
          ),
        );
      }
    }
  }

  Future<void> openWhatsApp(String sport) {
    final message = AppLanguageController.isEnglish
        ? 'Hello, I would like to book a $sport lesson. What time can you schedule it for me?'
        : 'Bonjour, je souhaite réserver un cours de $sport. À quelle heure pouvez-vous me programmer ?';
    return launchContact(
      Uri.https('wa.me', '/971589081892', {'text': message}),
    );
  }

  Future<void> requestAuthentication() async {
    await showAuthSheet(context, audience: 'parent', allowRegistration: true);
  }

  Future<void> reject(BookingHistoryItem booking) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LText('Refuser cette réservation ?'),
        content: LText(
          '${booking.playerName} · ${DateFormat('d MMM · HH:mm', AppLanguageController.isEnglish ? 'en_GB' : 'fr_FR').format(booking.startsAt)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LText('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const LText('Refuser'),
          ),
        ],
      ),
    );
    if (accepted != true || rejecting.contains(booking.id)) return;
    setState(() => rejecting.add(booking.id));
    try {
      await repository.rejectScheduledBooking(booking.id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: LText('Réservation refusée.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: LText('Impossible de refuser cette réservation.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => rejecting.remove(booking.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 120),
        children: [
          LText(
            'Réserver un cours',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 6),
          const LText(
            'Contactez l’académie pour programmer votre cours.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 24),
          _SportCards(
            onCall: () =>
                launchContact(Uri(scheme: 'tel', path: contactNumber)),
            onWhatsApp: openWhatsApp,
          ),
          const SizedBox(height: 30),
          if (user == null)
            PremiumCard(
              child: Column(
                children: [
                  const Icon(Icons.lock_person_outlined, size: 46),
                  const SizedBox(height: 12),
                  const LText(
                    'Connectez-vous pour consulter les réservations programmées par l’académie.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  AppButton(
                    'Me connecter',
                    icon: Icons.login_rounded,
                    onPressed: requestAuthentication,
                  ),
                ],
              ),
            )
          else ...[
            const SectionTitle('Réservations programmées'),
            StreamBuilder<List<BookingHistoryItem>>(
              stream: repository.watchBookingHistory(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const PremiumCard(
                    child: LText('Impossible de charger les réservations.'),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final bookings = snapshot.data!
                    .where(
                      (item) =>
                          item.status == 'confirmed' && item.clientCanReject,
                    )
                    .toList();
                if (bookings.isEmpty) {
                  return const PremiumCard(
                    child: LText('Aucune réservation programmée à refuser.'),
                  );
                }
                return Column(
                  children: bookings
                      .map(
                        (booking) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ScheduledBookingCard(
                            booking: booking,
                            loading: rejecting.contains(booking.id),
                            onReject: () => reject(booking),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
          ],
        ],
      ),
    ),
  );
}

class _SportCards extends StatelessWidget {
  const _SportCards({required this.onCall, required this.onWhatsApp});
  final Future<void> Function() onCall;
  final Future<void> Function(String sport) onWhatsApp;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final cards = [
        _SportCard(
          sport: 'Tennis',
          messageSport: 'tennis',
          image: 'assets/images/booking-tennis.jpg',
          onCall: onCall,
          onWhatsApp: onWhatsApp,
        ),
        _SportCard(
          sport: 'Paddle',
          messageSport: 'paddle',
          image: 'assets/images/booking-padel.jpg',
          onCall: onCall,
          onWhatsApp: onWhatsApp,
        ),
      ];
      return constraints.maxWidth < 680
          ? Column(
              children: [cards.first, const SizedBox(height: 16), cards.last],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: cards.first),
                const SizedBox(width: 18),
                Expanded(child: cards.last),
              ],
            );
    },
  );
}

class _SportCard extends StatelessWidget {
  const _SportCard({
    required this.sport,
    required this.messageSport,
    required this.image,
    required this.onCall,
    required this.onWhatsApp,
  });
  final String sport, messageSport, image;
  final Future<void> Function() onCall;
  final Future<void> Function(String sport) onWhatsApp;

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFFE7ECF2)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x12091D36),
          blurRadius: 24,
          offset: Offset(0, 10),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Stack(
          alignment: Alignment.bottomLeft,
          children: [
            AspectRatio(
              aspectRatio: 1.55,
              child: Image.asset(image, fit: BoxFit.cover),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: .72),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: LText(
                sport,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCall,
                  icon: const Icon(Icons.call_outlined),
                  label: const LText('Appeler'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => onWhatsApp(messageSport),
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  label: const LText('WhatsApp'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF20A85A),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ScheduledBookingCard extends StatelessWidget {
  const _ScheduledBookingCard({
    required this.booking,
    required this.loading,
    required this.onReject,
  });
  final BookingHistoryItem booking;
  final bool loading;
  final Future<void> Function() onReject;

  @override
  Widget build(BuildContext context) {
    final locale = AppLanguageController.isEnglish ? 'en_GB' : 'fr_FR';
    return PremiumCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  booking.title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const Chip(label: LText('Confirmée')),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${booking.playerName} · ${DateFormat('EEE d MMM · HH:mm', locale).format(booking.startsAt)}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${booking.coachName} · ${booking.courtName}',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: loading ? null : onReject,
              icon: loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.close_rounded),
              label: const LText('Refuser la réservation'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
