import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/localization/app_language.dart';
import '../../core/navigation/app_access_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../data/firebase_profile_repository.dart';
import '../auth/auth_sheet.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? selectedPlayerId;
  User? _user;
  StreamSubscription<User?>? _authSubscription;
  late final Stream<List<ChildProfile>> _childrenStream;

  @override
  void initState() {
    super.initState();
    _childrenStream = FirebaseProfileRepository().watchChildren();
    _user = FirebaseAuth.instance.currentUser;
    _authSubscription = FirebaseAuth.instance.userChanges().listen((user) {
      if (mounted) setState(() => _user = user);
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 120),
          children: [
            Row(
              children: [
                LText(
                  'Mon profil',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const Spacer(),
                PopupMenuButton<AppLanguage>(
                  tooltip: 'Language / Langue',
                  initialValue: AppLanguageController.language.value,
                  onSelected: (value) async {
                    await AppLanguageController.setLanguage(value);
                    await FirebaseProfileRepository().updatePreferredLanguage();
                    if (mounted) setState(() {});
                  },
                  icon: const Icon(Icons.language_rounded),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: AppLanguage.french,
                      child: Text('🇫🇷  Français'),
                    ),
                    PopupMenuItem(
                      value: AppLanguage.english,
                      child: Text('🇬🇧  English'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (user == null)
              _SignedOutCard()
            else ...[
              PremiumCard(
                child: Row(
                  children: [
                    PersonAvatar(
                      initials: _initials(
                        user.displayName ?? user.email ?? 'U',
                      ),
                      size: 62,
                      color: AppColors.sky,
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LText(
                            user.displayName?.trim().isNotEmpty == true
                                ? user.displayName!
                                : 'Utilisateur',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            user.email ?? '',
                            style: const TextStyle(color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: tr('Modifier mon profil'),
                      onPressed: () async {
                        final changed = await showUserProfileSheet(context);
                        if (changed == true && mounted) setState(() {});
                      },
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  const Expanded(child: SectionTitle('Mes joueurs')),
                  FilledButton.icon(
                    onPressed: () => showChildProfileSheet(context),
                    icon: const Icon(Icons.add),
                    label: const LText('Ajouter'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              StreamBuilder<List<ChildProfile>>(
                stream: _childrenStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const PremiumCard(
                      child: LText(
                        'Impossible de charger les profils joueurs.',
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final children = snapshot.data!;
                  if (children.isEmpty) {
                    return PremiumCard(
                      child: Column(
                        children: [
                          const Icon(
                            Icons.person_add_alt_1_rounded,
                            size: 42,
                            color: AppColors.sky,
                          ),
                          const SizedBox(height: 10),
                          const LText(
                            'Aucun joueur ajouté.',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          const LText(
                            'Ajoutez un joueur pour pouvoir ensuite le rattacher à une académie et réserver ses séances.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.muted),
                          ),
                          const SizedBox(height: 14),
                          AppButton(
                            'Ajouter un joueur',
                            icon: Icons.person_add_alt_1,
                            onPressed: () => showChildProfileSheet(context),
                          ),
                        ],
                      ),
                    );
                  }
                  final selected = children.length == 1
                      ? children.first
                      : children
                            .where((child) => child.id == selectedPlayerId)
                            .firstOrNull;
                  return Column(
                    children: [
                      ...children.map(
                        (child) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: () =>
                                setState(() => selectedPlayerId = child.id),
                            child: PremiumCard(
                              color: selected?.id == child.id
                                  ? const Color(0xFFEAF8FD)
                                  : Colors.white,
                              child: Row(
                                children: [
                                  PersonAvatar(
                                    initials: _initials(child.displayName),
                                    color: child.gender == 'female'
                                        ? AppColors.lilac
                                        : AppColors.sky,
                                  ),
                                  const SizedBox(width: 13),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        LText(
                                          child.displayName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        LText(
                                          '${child.age} ans · ${_genderLabel(child.gender)}',
                                          style: const TextStyle(
                                            color: AppColors.muted,
                                          ),
                                        ),
                                        if (child.academyName.isNotEmpty) ...[
                                          const SizedBox(height: 3),
                                          LText(
                                            child.academyName,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.muted,
                                            ),
                                          ),
                                        ],
                                        if (child.status ==
                                            'pending_cash_confirmation') ...[
                                          const SizedBox(height: 7),
                                          const LText(
                                            'Paiement cash en attente de confirmation par un administrateur. Le profil sera activé après validation.',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.orange,
                                            ),
                                          ),
                                        ],
                                        if (child.totalSessions > 0) ...[
                                          const SizedBox(height: 5),
                                          LText(
                                            playerPackageSummaryText(
                                              total: child.totalSessions,
                                              remaining:
                                                  child.remainingSessions,
                                              activationPending:
                                                  child.status ==
                                                  'pending_cash_confirmation',
                                            ),
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color:
                                                  child.remainingSessions <= 3
                                                  ? AppColors.orange
                                                  : AppColors.green,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: tr('Modifier ce joueur'),
                                    onPressed: () => showChildProfileSheet(
                                      context,
                                      child: child,
                                    ),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (children.length > 1 && selected == null)
                        const PremiumCard(
                          child: LText(
                            'Sélectionnez un joueur pour afficher ses statistiques.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (selected != null) _PlayerStatistics(player: selected),
                    ],
                  );
                },
              ),
              const SizedBox(height: 28),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Color(0xFFFFCDD2)),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                onPressed: () => _signOut(context),
                icon: const Icon(Icons.logout_rounded),
                label: const LText('Se déconnecter'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const LText('Se déconnecter ?'),
        content: const LText(
          'Vous pourrez continuer à découvrir l’application sans être connecté.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LText('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const LText('Se déconnecter'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    AppAccessController.revokeGuestAccess();
    await FirebaseAuth.instance.signOut();
    if (context.mounted) context.go('/welcome');
  }
}

class _SignedOutCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => PremiumCard(
    child: Column(
      children: [
        const Icon(
          Icons.account_circle_outlined,
          size: 56,
          color: AppColors.sky,
        ),
        const SizedBox(height: 12),
        const LText(
          'Connectez-vous pour gérer votre profil et vos joueurs.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        AppButton(
          'Créer mon profil ou me connecter',
          icon: Icons.login,
          onPressed: () => showAuthSheet(
            context,
            audience: 'parent',
            allowRegistration: true,
          ),
        ),
      ],
    ),
  );
}

Future<bool?> showChildProfileSheet(
  BuildContext context, {
  ChildProfile? child,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _ChildProfileSheet(child: child),
);

class _ChildProfileSheet extends StatefulWidget {
  const _ChildProfileSheet({this.child});
  final ChildProfile? child;
  @override
  State<_ChildProfileSheet> createState() => _ChildProfileSheetState();
}

class _ChildProfileSheetState extends State<_ChildProfileSheet> {
  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final age = TextEditingController();
  String gender = 'female';
  List<PlayerSessionConfiguration> configurations = const [];
  String? sessionConfigurationId;
  String? paymentMethod;
  bool loadingConfigurations = false;
  bool loading = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final child = widget.child;
    if (child != null) {
      firstName.text = child.firstName;
      lastName.text = child.lastName;
      age.text = child.age.toString();
      gender = child.gender;
    } else {
      age.addListener(_ageChanged);
      _loadConfigurations();
    }
  }

  Future<void> _loadConfigurations() async {
    setState(() => loadingConfigurations = true);
    try {
      final result = await FirebaseProfileRepository()
          .loadPlayerConfigurations();
      if (mounted) setState(() => configurations = result);
    } finally {
      if (mounted) setState(() => loadingConfigurations = false);
    }
  }

  void _ageChanged() {
    final parsedAge = int.tryParse(age.text.trim());
    if (sessionConfigurationId != null &&
        (parsedAge == null ||
            !configurations.any(
              (item) =>
                  item.id == sessionConfigurationId && item.accepts(parsedAge),
            ))) {
      sessionConfigurationId = null;
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    age.removeListener(_ageChanged);
    firstName.dispose();
    lastName.dispose();
    age.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final parsedAge = int.tryParse(age.text.trim());
    if (firstName.text.trim().isEmpty ||
        lastName.text.trim().isEmpty ||
        parsedAge == null ||
        parsedAge < 3 ||
        parsedAge > 80) {
      setState(
        () => error =
            'Renseignez le nom, le prénom et un âge compris entre 3 et 80 ans.',
      );
      return;
    }
    if (widget.child == null &&
        (sessionConfigurationId == null || paymentMethod == null)) {
      setState(
        () => error =
            'Choisissez une configuration de séance et un mode de paiement.',
      );
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (widget.child == null) {
        await FirebaseProfileRepository().addChild(
          firstName: firstName.text.trim(),
          lastName: lastName.text.trim(),
          age: parsedAge,
          gender: gender,
          sessionConfigurationId: sessionConfigurationId!,
          paymentMethod: paymentMethod!,
        );
        firstName.clear();
        lastName.clear();
        age.clear();
        gender = 'female';
        sessionConfigurationId = null;
        paymentMethod = null;
      } else {
        await FirebaseProfileRepository().updateChild(
          playerId: widget.child!.id,
          firstName: firstName.text.trim(),
          lastName: lastName.text.trim(),
          age: parsedAge,
          gender: gender,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Impossible d’ajouter ce joueur. Réessayez.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: Container(
      padding: EdgeInsets.fromLTRB(
        24,
        18,
        24,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.line,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
            const SizedBox(height: 20),
            LText(
              widget.child == null ? 'Ajouter un joueur' : 'Modifier le joueur',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            const LText(
              'L’académie pourra être rattachée plus tard.',
              style: TextStyle(color: AppColors.muted),
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              LText(error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 18),
            TextField(
              controller: firstName,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: tr('Prénom du joueur'),
                prefixIcon: const Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: lastName,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: tr('Nom du joueur'),
                prefixIcon: const Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: age,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: tr('Âge'),
                prefixIcon: const Icon(Icons.cake_outlined),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: gender,
              decoration: InputDecoration(
                labelText: tr('Sexe'),
                prefixIcon: const Icon(Icons.wc_rounded),
              ),
              items: const [
                DropdownMenuItem(value: 'female', child: LText('Fille')),
                DropdownMenuItem(value: 'male', child: LText('Garçon')),
                DropdownMenuItem(value: 'woman', child: LText('Femme')),
                DropdownMenuItem(value: 'man', child: LText('Homme')),
                DropdownMenuItem(value: 'other', child: LText('Autre')),
              ],
              onChanged: (value) => setState(() => gender = value ?? gender),
            ),
            if (widget.child == null) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'session-configuration-${sessionConfigurationId ?? 'none'}',
                ),
                isExpanded: true,
                itemHeight: null,
                initialValue: sessionConfigurationId,
                decoration: InputDecoration(
                  labelText: loadingConfigurations
                      ? tr('Chargement des séances...')
                      : tr('Type de séance'),
                  prefixIcon: const Icon(Icons.sports_tennis),
                ),
                items:
                    (int.tryParse(age.text.trim()) == null
                            ? const <PlayerSessionConfiguration>[]
                            : configurations.where(
                                (item) =>
                                    item.accepts(int.parse(age.text.trim())),
                              ))
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.id,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                tr(item.label),
                                maxLines: 2,
                                softWrap: true,
                                overflow: TextOverflow.visible,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                selectedItemBuilder: (context) => configurations
                    .where(
                      (item) =>
                          int.tryParse(age.text.trim()) != null &&
                          item.accepts(int.parse(age.text.trim())),
                    )
                    .map(
                      (item) => Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          tr(item.compactLabel),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: loadingConfigurations
                    ? null
                    : (value) => setState(() => sessionConfigurationId = value),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('payment-method-${paymentMethod ?? 'none'}'),
                initialValue: paymentMethod,
                decoration: InputDecoration(
                  labelText: tr('Mode de paiement'),
                  prefixIcon: const Icon(Icons.payments_outlined),
                ),
                items: const [
                  DropdownMenuItem(value: 'cash', child: LText('Cash')),
                  DropdownMenuItem(
                    value: 'card',
                    child: LText('Carte bancaire'),
                  ),
                  DropdownMenuItem(
                    value: 'payment_link',
                    child: LText('Lien de paiement'),
                  ),
                  DropdownMenuItem(
                    value: 'bank_transfer',
                    child: LText('Virement bancaire'),
                  ),
                ],
                onChanged: (value) => setState(() => paymentMethod = value),
              ),
            ],
            const SizedBox(height: 18),
            AppButton(
              loading
                  ? 'Veuillez patienter...'
                  : widget.child == null
                  ? 'Ajouter le joueur'
                  : 'Enregistrer',
              icon: Icons.person_add_alt_1,
              onPressed: loading ? null : save,
            ),
          ],
        ),
      ),
    ),
  );
}

class _PlayerStatistics extends StatelessWidget {
  const _PlayerStatistics({required this.player});
  final ChildProfile player;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SectionTitle('Statistiques de ${player.firstName}'),
            ),
            IconButton(
              onPressed: () => showChildProfileSheet(context, child: player),
              icon: const Icon(Icons.edit_outlined),
              tooltip: tr('Modifier ce joueur'),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: _RealStat(
                '${player.progress}%',
                'progression',
                Icons.trending_up,
                AppColors.sky,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _RealStat(
                '${player.sessionCount}',
                'séances',
                Icons.sports_tennis,
                AppColors.green,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _RealStat(
                _duration(player.playMinutes),
                'de jeu',
                Icons.schedule,
                AppColors.orange,
              ),
            ),
          ],
        ),
        if (player.totalSessions > 0) ...[
          const SizedBox(height: 12),
          PremiumCard(
            color: player.remainingSessions <= 3
                ? const Color(0xFFFFF1E6)
                : const Color(0xFFEAF8EF),
            child: Row(
              children: [
                Icon(
                  player.remainingSessions <= 3
                      ? Icons.notification_important_outlined
                      : Icons.confirmation_number_outlined,
                  color: player.remainingSessions <= 3
                      ? AppColors.orange
                      : AppColors.green,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    remainingSessionsText(
                      player.remainingSessions,
                      player.totalSessions,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        PremiumCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: LText(
                      'Progression globale',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    '${player.progress}%',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: LinearProgressIndicator(
                  value: player.progress / 100,
                  minHeight: 10,
                  backgroundColor: AppColors.cloud,
                  color: AppColors.green,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (player.progress == 0 &&
            player.sessionCount == 0 &&
            player.playMinutes == 0 &&
            player.badgeCount == 0)
          const PremiumCard(
            child: LText(
              'Aucune statistique enregistrée pour ce joueur pour le moment.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.muted),
            ),
          ),
      ],
    ),
  );
}

class _RealStat extends StatelessWidget {
  const _RealStat(this.value, this.label, this.icon, this.color);
  final String value, label;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    height: 105,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const Spacer(),
        LText(
          value,
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
        ),
        LText(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.muted),
        ),
      ],
    ),
  );
}

Future<bool?> showUserProfileSheet(BuildContext context) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _UserProfileSheet(),
    );

class _UserProfileSheet extends StatefulWidget {
  const _UserProfileSheet();
  @override
  State<_UserProfileSheet> createState() => _UserProfileSheetState();
}

class _UserProfileSheetState extends State<_UserProfileSheet> {
  final name = TextEditingController(
    text: FirebaseAuth.instance.currentUser?.displayName ?? '',
  );
  final phone = TextEditingController();
  bool loading = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty) {
      setState(() => error = 'Le nom complet est requis.');
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await FirebaseProfileRepository().updateMyProfile(
        displayName: name.text.trim(),
        phone: phone.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Impossible de modifier votre profil.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: Container(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LText(
              'Modifier mon profil',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (error != null) ...[
              const SizedBox(height: 10),
              LText(error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 18),
            TextField(
              controller: name,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: tr('Nom complet'),
                prefixIcon: const Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: tr('Numéro de téléphone'),
                prefixIcon: const Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 18),
            AppButton(
              loading ? 'Veuillez patienter...' : 'Enregistrer',
              icon: Icons.save_outlined,
              onPressed: loading ? null : save,
            ),
          ],
        ),
      ),
    ),
  );
}

String _duration(int minutes) => minutes < 60
    ? '${minutes}min'
    : '${minutes ~/ 60}h${minutes % 60 == 0 ? '' : (minutes % 60).toString().padLeft(2, '0')}';

String _initials(String name) => name
    .trim()
    .split(RegExp(r'\s+'))
    .where((part) => part.isNotEmpty)
    .take(2)
    .map((part) => part[0].toUpperCase())
    .join();
String _genderLabel(String value) => value == 'female'
    ? 'Fille'
    : value == 'male'
    ? 'Garçon'
    : value == 'woman'
    ? 'Femme'
    : value == 'man'
    ? 'Homme'
    : 'Autre';
