import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../core/localization/app_language.dart';
import '../../data/firebase_tournament_repository.dart';

class TournamentsScreen extends StatelessWidget {
  const TournamentsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    // La création et la gestion des tournois sont réservées à l'administration.
    // Le bouton de création mobile est volontairement désactivé.
    floatingActionButton: null,
    body: SafeArea(
      child: StreamBuilder<List<TournamentRecord>>(
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
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 120),
            children: [
              LText(
                'Tournois',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 6),
              const LText(
                'Découvrez les prochains tournois.',
                style: TextStyle(color: AppColors.muted),
              ),
              const SizedBox(height: 24),
              if (tournaments.isEmpty)
                const PremiumCard(child: LText('Aucun tournoi publié.')),
              ...tournaments.map(
                (tournament) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Pressable(
                    onTap: () => _details(context, tournament),
                    child: PremiumCard(
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: tournament.imageUrl == null
                                ? Container(
                                    width: 88,
                                    height: 92,
                                    color: AppColors.orange.withValues(
                                      alpha: .15,
                                    ),
                                    child: const Icon(
                                      Icons.emoji_events,
                                      color: AppColors.orange,
                                      size: 42,
                                    ),
                                  )
                                : Image.network(
                                    tournament.imageUrl!,
                                    width: 88,
                                    height: 92,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 88,
                                      height: 92,
                                      color: AppColors.cloud,
                                      child: const Icon(Icons.emoji_events),
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  DateFormat(
                                    'dd MMM yyyy · HH:mm',
                                  ).format(tournament.startsAt),
                                  style: const TextStyle(
                                    color: AppColors.blue,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  tournament.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${tournament.venue} · ${tournament.registeredCount}/${tournament.capacity} joueurs',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.muted,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  tournament.category,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  void _details(
    BuildContext context,
    TournamentRecord tournament,
  ) => showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tournament.imageUrl != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.network(
                tournament.imageUrl!,
                width: double.infinity,
                height: 180,
                fit: BoxFit.cover,
              ),
            )
          else
            const Icon(Icons.emoji_events, color: AppColors.orange, size: 56),
          const SizedBox(height: 16),
          Text(
            tournament.name,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            '${DateFormat('dd MMM yyyy · HH:mm').format(tournament.startsAt)} · ${tournament.venue}',
            style: const TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 10),
          Text(
            tournament.category,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          if (tournament.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(tournament.description),
          ],
          const SizedBox(height: 20),
          Center(
            child: Text(
              '${tournament.registeredCount}/${tournament.capacity} joueurs inscrits',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CreateTournamentSheet extends StatefulWidget {
  const _CreateTournamentSheet();
  @override
  State<_CreateTournamentSheet> createState() => _CreateTournamentSheetState();
}

class _CreateTournamentSheetState extends State<_CreateTournamentSheet> {
  final name = TextEditingController();
  final venue = TextEditingController();
  final category = TextEditingController();
  final description = TextEditingController();
  final capacity = TextEditingController(text: '16');
  DateTime? startsAt;
  Uint8List? imageBytes;
  String? imageMimeType;
  bool loading = false;
  String? error;

  @override
  void dispose() {
    name.dispose();
    venue.dispose();
    category.dispose();
    description.dispose();
    capacity.dispose();
    super.dispose();
  }

  Future<void> pickImage() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1600,
    );
    if (image == null) return;
    final bytes = await image.readAsBytes();
    final mime =
        image.mimeType ??
        (image.name.toLowerCase().endsWith('.png')
            ? 'image/png'
            : image.name.toLowerCase().endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg');
    if (bytes.length > 2000000 ||
        !['image/png', 'image/jpeg', 'image/webp'].contains(mime)) {
      setState(
        () => error = 'Choisissez une image PNG, JPEG ou WebP de 2 Mo maximum.',
      );
      return;
    }
    setState(() {
      imageBytes = bytes;
      imageMimeType = mime;
      error = null;
    });
  }

  Future<void> pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: DateTime(now.year + 5),
      initialDate: startsAt ?? now.add(const Duration(days: 1)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        startsAt ?? DateTime(now.year, now.month, now.day, 9),
      ),
    );
    if (time == null) return;
    setState(
      () => startsAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> submit() async {
    final parsedCapacity = int.tryParse(capacity.text.trim());
    if (name.text.trim().isEmpty ||
        venue.text.trim().isEmpty ||
        category.text.trim().isEmpty ||
        startsAt == null ||
        parsedCapacity == null ||
        parsedCapacity < 2) {
      setState(() => error = 'Renseignez tous les champs obligatoires.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await FirebaseTournamentRepository().createTournament(
        name: name.text.trim(),
        venue: venue.text.trim(),
        category: category.text.trim(),
        description: description.text.trim(),
        startsAt: startsAt!,
        capacity: parsedCapacity,
        imageBytes: imageBytes,
        imageMimeType: imageMimeType,
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Impossible de créer le tournoi. Réessayez.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      0,
      20,
      20 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LText(
            'Créer un tournoi',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          if (error != null) ...[
            LText(error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: name,
            decoration: InputDecoration(labelText: tr('Nom du tournoi')),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: venue,
            decoration: InputDecoration(labelText: tr('Lieu')),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: category,
            decoration: InputDecoration(labelText: tr('Catégorie')),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: capacity,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: tr('Capacité')),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: loading ? null : pickDate,
            icon: const Icon(Icons.event),
            label: Text(
              startsAt == null
                  ? tr('Choisir la date et l’heure')
                  : DateFormat('dd/MM/yyyy · HH:mm').format(startsAt!),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: description,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: tr('Description facultative'),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: loading ? null : pickImage,
            icon: const Icon(Icons.image_outlined),
            label: LText(
              imageBytes == null ? 'Ajouter une image' : 'Changer l’image',
            ),
          ),
          if (imageBytes != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(imageBytes!, height: 160, fit: BoxFit.cover),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: loading ? null : submit,
            icon: loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.publish),
            label: const LText('Publier'),
          ),
        ],
      ),
    ),
  );
}
