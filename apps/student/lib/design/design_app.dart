import 'package:flutter/material.dart';

const forest = Color(0xFF163E33);
const lime = Color(0xFFD5F279);
const paper = Color(0xFFF5F6F2);
const muted = Color(0xFF7B857A);
const line = Color(0xFFE7EAE3);

ThemeData sportaDesignTheme() => ThemeData(
  useMaterial3: true,
  scaffoldBackgroundColor: paper,
  colorScheme: ColorScheme.fromSeed(
    seedColor: forest,
    primary: forest,
    secondary: lime,
    surface: Colors.white,
  ),
  fontFamily: 'sans-serif',
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w800,
      letterSpacing: -1.4,
      color: forest,
    ),
    headlineMedium: TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.w800,
      letterSpacing: -1,
      color: forest,
    ),
    titleLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w800,
      letterSpacing: -.5,
      color: forest,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: forest,
    ),
    bodyMedium: TextStyle(fontSize: 13, height: 1.5, color: forest),
    bodySmall: TextStyle(fontSize: 11, height: 1.5, color: muted),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: paper,
    foregroundColor: forest,
    elevation: 0,
    scrolledUnderElevation: 0,
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: forest,
      foregroundColor: Colors.white,
      minimumSize: const Size(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: forest,
      minimumSize: const Size(0, 46),
      side: const BorderSide(color: line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: line),
    ),
    contentPadding: const EdgeInsets.all(16),
    labelStyle: const TextStyle(fontSize: 13),
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: Colors.white,
    indicatorColor: const Color(0xFFEDF3DE),
    height: 74,
    labelTextStyle: WidgetStateProperty.resolveWith(
      (states) => TextStyle(
        fontSize: 10,
        fontWeight: states.contains(WidgetState.selected)
            ? FontWeight.w700
            : FontWeight.w500,
        color: states.contains(WidgetState.selected) ? forest : muted,
      ),
    ),
  ),
  dividerTheme: const DividerThemeData(color: line, thickness: 1),
  chipTheme: ChipThemeData(
    side: const BorderSide(color: line),
    selectedColor: const Color(0xFFEDF3DE),
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  ),
);

class SportADesignApp extends StatelessWidget {
  const SportADesignApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SportA · Aperçu',
    debugShowCheckedModeBanner: false,
    theme: sportaDesignTheme(),
    home: const DesignHome(),
  );
}

class PreviewBooking {
  PreviewBooking({
    required this.title,
    required this.date,
    required this.time,
    required this.player,
    required this.coach,
    this.status = 'Confirmée',
    this.sport = 'Tennis',
  });
  final String title, time, player, coach, sport;
  final DateTime date;
  String status;
}

class DesignHome extends StatefulWidget {
  const DesignHome({super.key});
  @override
  State<DesignHome> createState() => _DesignHomeState();
}

class _DesignHomeState extends State<DesignHome> {
  int tab = 0;
  int child = 0;
  bool coachMode = false;
  bool welcome = false;
  bool notifications = true;
  final List<String> players = ['Lucas', 'Emma'];
  late final List<PreviewBooking> bookings = [
    PreviewBooking(
      title: 'Perfectionnement tennis',
      date: DateTime.now(),
      time: '17:30',
      player: 'Lucas',
      coach: 'David Kengne',
    ),
    PreviewBooking(
      title: 'Les petits champions',
      date: DateTime.now().add(const Duration(days: 2)),
      time: '16:00',
      player: 'Emma',
      coach: 'Émilie Mballa',
      status: 'En attente',
    ),
  ];
  final Set<String> registrations = {};
  final Map<String, bool> attendance = {};
  DateTime calendarDay = DateTime.now();
  String calendarFilter = 'À venir';
  void notify(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: forest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
  void go(int target) => setState(() => tab = target);
  void push(Widget screen) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => screen));
  String get selectedPlayer => players[child];
  Future<void> sheet(String title, Widget content) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: paper,
        builder: (context) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            4,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .8,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 20),
                  content,
                ],
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (welcome) {
      return WelcomePreview(onEnter: () => setState(() => welcome = false));
    }
    final wide = MediaQuery.sizeOf(context).width >= 850;
    final destinations = [
      NavigationDestination(
        icon: const Icon(Icons.home_outlined),
        selectedIcon: const Icon(Icons.home_rounded),
        label: coachMode ? 'Mon équipe' : 'Accueil',
      ),
      const NavigationDestination(
        icon: Icon(Icons.add_circle_outline),
        selectedIcon: Icon(Icons.add_circle),
        label: 'Réserver',
      ),
      const NavigationDestination(
        icon: Icon(Icons.calendar_today_outlined),
        selectedIcon: Icon(Icons.calendar_month),
        label: 'Planning',
      ),
      const NavigationDestination(
        icon: Icon(Icons.emoji_events_outlined),
        selectedIcon: Icon(Icons.emoji_events),
        label: 'Tournois',
      ),
      const NavigationDestination(
        icon: Icon(Icons.person_outline),
        selectedIcon: Icon(Icons.person),
        label: 'Profil',
      ),
    ];
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              NavigationRail(
                extended: MediaQuery.sizeOf(context).width > 1100,
                backgroundColor: Colors.white,
                selectedIndex: tab,
                onDestinationSelected: go,
                leading: const Padding(
                  padding: EdgeInsets.all(20),
                  child: SportaMark(),
                ),
                destinations: destinations
                    .map(
                      (d) => NavigationRailDestination(
                        icon: d.icon,
                        selectedIcon: d.selectedIcon,
                        label: Text(d.label),
                      ),
                    )
                    .toList(),
              ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: KeyedSubtree(
                      key: ValueKey('$tab-$coachMode'),
                      child: [
                        coachMode ? coachHome() : home(),
                        bookingPage(),
                        calendar(),
                        tournaments(),
                        profile(),
                      ][tab],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: go,
              destinations: destinations,
            ),
    );
  }

  Widget page({required List<Widget> children}) => ListView(
    padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
    children: children,
  );
  Widget heading(String eyebrow, String title, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow(eyebrow),
              const SizedBox(height: 7),
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    ),
  );
  Widget section(String title, {String? action, VoidCallback? onTap}) =>
      Padding(
        padding: const EdgeInsets.only(top: 25, bottom: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (action != null)
              TextButton(
                onPressed: onTap,
                child: Text(action, style: const TextStyle(fontSize: 11)),
              ),
          ],
        ),
      );

  Widget home() {
    final upcoming =
        bookings
            .where(
              (b) =>
                  b.player == selectedPlayer &&
                  b.status != 'Annulée' &&
                  b.status != 'Terminée',
            )
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    return page(
      children: [
        heading(
          'VOTRE FAMILLE, EN MOUVEMENT',
          'Bonjour, Sophie.',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Notifications',
                onPressed: showNotifications,
                icon: const Badge(
                  smallSize: 6,
                  backgroundColor: Color(0xFF9CAC6B),
                  child: Icon(Icons.notifications_none_rounded),
                ),
              ),
              GestureDetector(
                onTap: () => go(4),
                child: const Avatar('SM', dark: true),
              ),
            ],
          ),
        ),
        Row(
          children: [
            const Icon(Icons.location_on_outlined, size: 16, color: muted),
            const SizedBox(width: 5),
            const Expanded(
              child: Text(
                'Tennis Club Bonanjo',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ),
            const PreviewBadge(),
          ],
        ),
        const SizedBox(height: 23),
        Container(
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(
            color: forest,
            borderRadius: BorderRadius.circular(25),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -30,
                bottom: -38,
                child: Transform.rotate(
                  angle: -.35,
                  child: const CourtDrawing(width: 140, height: 175),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('LE PLAISIR DE PROGRESSER', color: lime),
                  const SizedBox(height: 18),
                  const Text(
                    'De petits pas.\nDe grandes victoires.',
                    style: TextStyle(
                      fontSize: 29,
                      height: 1.18,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1.2,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 13),
                  const Text(
                    'Son prochain beau moment\ncommence sur le terrain.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFB6C8B5),
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: lime,
                      foregroundColor: forest,
                      minimumSize: const Size(0, 42),
                    ),
                    onPressed: () => go(1),
                    label: const Text('Trouver une séance'),
                    icon: const Icon(Icons.arrow_forward, size: 17),
                    iconAlignment: IconAlignment.end,
                  ),
                ],
              ),
            ],
          ),
        ),
        section('Votre petite équipe', action: 'Ajouter', onTap: addPlayer),
        SizedBox(
          height: 94,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: players.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => setState(() => child = i),
              child: Container(
                width: 190,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: i == child ? const Color(0xFFEDF3DE) : Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: i == child ? const Color(0xFFC5D7A7) : line,
                  ),
                ),
                child: Row(
                  children: [
                    Avatar(
                      players[i].substring(0, 1),
                      color: i.isEven
                          ? const Color(0xFFE3ECCF)
                          : const Color(0xFFF3E5D3),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            players[i],
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const Text(
                            'Mon joueur',
                            style: TextStyle(fontSize: 10, color: muted),
                          ),
                        ],
                      ),
                    ),
                    if (i == child)
                      const Icon(Icons.check_circle, color: forest, size: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
        section('Prochain rendez-vous', action: 'Planning', onTap: () => go(2)),
        if (upcoming.isEmpty)
          Panel(
            child: Column(
              children: [
                const Icon(
                  Icons.calendar_today_outlined,
                  color: muted,
                  size: 32,
                ),
                const SizedBox(height: 10),
                Text('Un nouveau défi pour $selectedPlayer ?'),
                TextButton(
                  onPressed: () => go(1),
                  child: const Text('Choisir une séance'),
                ),
              ],
            ),
          )
        else
          bookingCard(upcoming.first),
        section('Chaque effort compte'),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Avatar('↗', color: Color(0xFFEDF3DE)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'La progression de $selectedPlayer',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const Text(
                          'Une belle régularité cette saison',
                          style: TextStyle(fontSize: 11, color: muted),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.auto_awesome_outlined,
                    color: Color(0xFF91A861),
                  ),
                ],
              ),
              const SizedBox(height: 23),
              const Row(
                children: [
                  Expanded(child: Metric('8', 'séances suivies')),
                  Expanded(child: Metric('72 %', 'progression')),
                  Expanded(child: Metric('3', 'objectifs atteints')),
                ],
              ),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: const LinearProgressIndicator(
                  value: .72,
                  color: forest,
                  backgroundColor: Color(0xFFEDF1E5),
                  minHeight: 7,
                ),
              ),
              const SizedBox(height: 13),
              GestureDetector(
                onTap: () => playerDetails(selectedPlayer),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Découvrir ses progrès',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Icon(Icons.arrow_forward, size: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
        section('À vivre ensemble', action: 'Tournois', onTap: () => go(3)),
        InkWell(
          onTap: () => tournamentDetails(0),
          borderRadius: BorderRadius.circular(20),
          child: Panel(
            color: const Color(0xFFF3EDDF),
            child: Row(
              children: [
                const Icon(
                  Icons.emoji_events_outlined,
                  size: 45,
                  color: Color(0xFFAA874D),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Eyebrow('LE PROCHAIN DÉFI'),
                      const SizedBox(height: 6),
                      const Text(
                        'Little Champions Cup',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 5),
                      const Text(
                        '17–18 octobre · Orange U10',
                        style: TextStyle(color: muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward, size: 18),
              ],
            ),
          ),
        ),
        const PreviewFootnote(),
      ],
    );
  }

  Widget bookingCard(PreviewBooking b) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: InkWell(
      onTap: () => bookingDetails(b),
      borderRadius: BorderRadius.circular(19),
      child: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDF3DE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${b.date.day}',
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        monthName(b.date.month),
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${b.time} · 60 min · ${b.player}',
                        style: const TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 19, color: muted),
              ],
            ),
            const SizedBox(height: 17),
            const Divider(height: 1),
            const SizedBox(height: 13),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Avec ${b.coach}',
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
                StatusBadge(b.status),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  void bookingDetails(PreviewBooking b) => sheet(
    'Votre séance',
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatusBadge(b.status),
        const SizedBox(height: 16),
        Text(b.title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 20),
        InfoRow(
          Icons.calendar_month,
          'Date',
          '${b.date.day} ${monthName(b.date.month)} · ${b.time}',
        ),
        InfoRow(Icons.person_outline, 'Joueur', b.player),
        InfoRow(Icons.sports_tennis, 'Coach', b.coach),
        const InfoRow(
          Icons.location_on_outlined,
          'Lieu',
          'Court central · Tennis Club Bonanjo',
        ),
        const SizedBox(height: 20),
        if (b.status != 'Annulée' && b.status != 'Terminée')
          OutlinedButton(
            onPressed: () {
              setState(() => b.status = 'Annulée');
              Navigator.pop(context);
              notify('Séance annulée dans l’aperçu.');
            },
            child: const Text('Annuler la réservation'),
          ),
        const PreviewFootnote(),
      ],
    ),
  );

  Widget bookingPage() => page(
    children: [
      heading('À VOUS DE JOUER', 'Le prochain beau moment.'),
      const Text(
        'Trouvez la séance qui lui donnera envie de revenir.',
        style: TextStyle(color: muted),
      ),
      const SizedBox(height: 25),
      sportCard(
        'Tennis',
        'Le plaisir du premier échange.',
        'assets/images/booking-tennis.jpg',
        Icons.sports_tennis,
      ),
      const SizedBox(height: 20),
      sportCard(
        'Padel',
        'Du jeu, du rythme, du partage.',
        'assets/images/booking-padel.jpg',
        Icons.sports_tennis_outlined,
      ),
      section('Un parcours, à son rythme'),
      const Panel(
        child: Row(
          children: [
            Avatar('01'),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'Choisissez une activité, un créneau et votre joueur. On s’occupe du reste.',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ),
          ],
        ),
      ),
      const PreviewFootnote(),
    ],
  );
  Widget sportCard(
    String sport,
    String subtitle,
    String asset,
    IconData icon,
  ) => InkWell(
    onTap: () => openBooking(sport),
    borderRadius: BorderRadius.circular(22),
    child: Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: Colors.white,
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 175,
            width: double.infinity,
            child: Image.asset(
              asset,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => ColoredBox(
                color: const Color(0xFFDFE9D4),
                child: Icon(icon, size: 80, color: forest),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(21),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sport,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Dès 8 000 FCFA / séance',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: forest,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.arrow_forward, color: lime, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  Future<void> openBooking(String sport) async {
    final result = await Navigator.of(context).push<PreviewBooking>(
      MaterialPageRoute(
        builder: (_) => BookingFlow(
          sport: sport,
          players: players,
          selectedPlayer: selectedPlayer,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        bookings.add(result);
        calendarDay = result.date;
        calendarFilter = 'À venir';
        tab = 2;
      });
      notify('Réservation ajoutée à votre planning de démonstration.');
    }
  }

  Widget calendar() {
    final start = DateTime(
      calendarDay.year,
      calendarDay.month,
      calendarDay.day,
    ).subtract(Duration(days: calendarDay.weekday - 1));
    final filtered = bookings
        .where(
          (b) => calendarFilter == 'Historique'
              ? ['Annulée', 'Terminée'].contains(b.status)
              : !['Annulée', 'Terminée'].contains(b.status) &&
                    DateUtils.isSameDay(b.date, calendarDay),
        )
        .toList();
    return page(
      children: [
        heading(
          'ON SE RETROUVE SUR LE TERRAIN',
          'Votre planning.',
          trailing: IconButton(
            tooltip: 'Réserver une séance',
            onPressed: () => go(1),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                '${monthName(calendarDay.month)} ${calendarDay.year}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              tooltip: 'Semaine précédente',
              onPressed: () => setState(
                () =>
                    calendarDay = calendarDay.subtract(const Duration(days: 7)),
              ),
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: 'Semaine suivante',
              onPressed: () => setState(
                () => calendarDay = calendarDay.add(const Duration(days: 7)),
              ),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 15),
        Row(
          children: List.generate(7, (i) {
            final d = start.add(Duration(days: i));
            final selected = DateUtils.isSameDay(d, calendarDay);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: InkWell(
                  borderRadius: BorderRadius.circular(13),
                  onTap: () => setState(() => calendarDay = d),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: selected ? forest : Colors.white,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: selected ? forest : line),
                    ),
                    child: Column(
                      children: [
                        Text(
                          ['L', 'M', 'M', 'J', 'V', 'S', 'D'][i],
                          style: TextStyle(
                            fontSize: 10,
                            color: selected ? lime : muted,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '${d.day}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: selected ? Colors.white : forest,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                bookings.any(
                                  (b) =>
                                      DateUtils.isSameDay(b.date, d) &&
                                      b.status != 'Annulée',
                                )
                                ? (selected ? lime : forest)
                                : Colors.transparent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 8,
          children: ['À venir', 'Historique']
              .map(
                (f) => ChoiceChip(
                  label: Text(f),
                  selected: calendarFilter == f,
                  onSelected: (_) => setState(() => calendarFilter = f),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 22),
        if (filtered.isEmpty)
          Panel(
            child: Column(
              children: [
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 44,
                  color: Color(0xFFA1B18E),
                ),
                const SizedBox(height: 18),
                Text(
                  calendarFilter == 'Historique'
                      ? 'Son histoire commence ici.'
                      : 'Un peu de place pour jouer.',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Aucune séance à afficher pour cette sélection.',
                  style: TextStyle(color: muted, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => go(1),
                  child: const Text('Trouver une séance'),
                ),
              ],
            ),
          )
        else
          ...filtered.map(bookingCard),
        const PreviewFootnote(),
      ],
    );
  }

  static const tournamentNames = [
    'Little Champions Cup',
    'Douala Junior Open',
    'Future Stars Series',
  ];
  Widget tournaments() => page(
    children: [
      heading('LES DÉFIS QUI FONT GRANDIR', 'Place au jeu.'),
      const Text(
        'Des rencontres, des émotions et de beaux souvenirs.',
        style: TextStyle(color: muted),
      ),
      const SizedBox(height: 24),
      ...List.generate(
        3,
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: InkWell(
            onTap: () => tournamentDetails(i),
            borderRadius: BorderRadius.circular(22),
            child: Panel(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 145,
                    decoration: BoxDecoration(
                      color: [
                        const Color(0xFFEDF3DE),
                        const Color(0xFFF3EADD),
                        const Color(0xFFEAE5F0),
                      ][i],
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.emoji_events_outlined,
                        size: 70,
                        color: [
                          forest,
                          const Color(0xFFAB884D),
                          const Color(0xFF8E75A4),
                        ][i],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(21),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StatusBadge(
                          registrations.contains(tournamentNames[i])
                              ? 'Inscrit'
                              : i == 2
                              ? 'Complet'
                              : 'Inscriptions ouvertes',
                        ),
                        const SizedBox(height: 13),
                        Text(
                          tournamentNames[i],
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 7),
                        Text(
                          [
                            '17–18 octobre · Bonanjo',
                            '07–08 novembre · Club Noah',
                            '21 novembre · Littoral',
                          ][i],
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                i == 1 ? 'Vert · U12' : 'Orange · U10',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              [
                                '26 / 32 joueurs',
                                '38 / 48 joueurs',
                                '24 / 24 joueurs',
                              ][i],
                              style: const TextStyle(
                                color: muted,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward, size: 18),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      const PreviewFootnote(),
    ],
  );
  void tournamentDetails(int i) => sheet(
    tournamentNames[i],
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.emoji_events_outlined,
          size: 70,
          color: Color(0xFF9AAA67),
        ),
        const SizedBox(height: 20),
        const Text(
          'Une journée pour se dépasser, rencontrer de nouveaux joueurs et célébrer les progrès de chacun.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 20),
        InfoRow(Icons.person_outline, 'Joueur', selectedPlayer),
        InfoRow(
          Icons.flag_outlined,
          'Catégorie',
          i == 1 ? 'Vert · U12' : 'Orange · U10',
        ),
        const InfoRow(
          Icons.location_on_outlined,
          'Lieu',
          'Tennis Club Bonanjo',
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: i == 2 || registrations.contains(tournamentNames[i])
              ? null
              : () {
                  setState(() => registrations.add(tournamentNames[i]));
                  Navigator.pop(context);
                  notify(
                    'Inscription de $selectedPlayer simulée dans l’aperçu.',
                  );
                },
          child: Text(
            i == 2
                ? 'Tournoi complet'
                : registrations.contains(tournamentNames[i])
                ? 'Déjà inscrit'
                : 'Simuler l’inscription',
          ),
        ),
        const PreviewFootnote(),
      ],
    ),
  );

  Widget profile() => page(
    children: [
      heading('VOTRE ESPACE, VOTRE RYTHME', 'Mon profil.'),
      Panel(
        child: Row(
          children: [
            Avatar(coachMode ? 'DK' : 'SM', dark: true, size: 60),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    coachMode ? 'David Kengne' : 'Sophie Martin',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    coachMode ? 'Coach · Tennis' : 'Parent · Famille Martin',
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  const PreviewBadge(),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Modifier le profil',
              onPressed: editProfile,
              icon: const Icon(Icons.edit_outlined, size: 19),
            ),
          ],
        ),
      ),
      section('Ma famille', action: 'Ajouter', onTap: addPlayer),
      ...players.map(
        (name) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Panel(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 4),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Avatar(name[0]),
              title: Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              subtitle: const Text(
                'Profil sportif & progression',
                style: TextStyle(fontSize: 11, color: muted),
              ),
              trailing: const Icon(Icons.chevron_right, size: 19),
              onTap: () => playerDetails(name),
            ),
          ),
        ),
      ),
      section('Au quotidien'),
      Panel(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            menuRow(
              Icons.receipt_long_outlined,
              'Factures & forfaits',
              invoices,
            ),
            const Divider(height: 1),
            menuRow(
              Icons.chat_bubble_outline,
              'Mes échanges',
              () => push(const ChatPreview()),
            ),
            const Divider(height: 1),
            menuRow(
              Icons.notifications_none,
              'Notifications',
              () => sheet(
                'Mes notifications',
                StatefulBuilder(
                  builder: (context, update) => SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Actualités de mon académie',
                      style: TextStyle(fontSize: 13),
                    ),
                    subtitle: const Text('Préférence de démonstration'),
                    value: notifications,
                    onChanged: (v) {
                      setState(() => notifications = v);
                      update(() {});
                    },
                  ),
                ),
              ),
            ),
            const Divider(height: 1),
            menuRow(
              Icons.help_outline,
              'À propos de SportA',
              () => sheet(
                'Play. Grow. Together.',
                const Column(
                  children: [
                    SportaMark(),
                    SizedBox(height: 20),
                    Text(
                      'SportA rapproche les académies, les coachs et les familles autour du plaisir de progresser.',
                    ),
                    PreviewFootnote(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      section('Explorer les parcours'),
      Panel(
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Espace coach',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              subtitle: const Text(
                'Découvrir les séances et le suivi des joueurs',
                style: TextStyle(fontSize: 11),
              ),
              value: coachMode,
              onChanged: (v) => setState(() {
                coachMode = v;
                tab = 0;
              }),
            ),
            const Divider(),
            menuRow(
              Icons.auto_awesome_outlined,
              'Découvrir l’accueil SportA',
              () => setState(() => welcome = true),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      OutlinedButton.icon(
        onPressed: () => setState(() => welcome = true),
        icon: const Icon(Icons.logout, size: 18),
        label: const Text('Se déconnecter de l’aperçu'),
      ),
      const PreviewFootnote(),
    ],
  );
  Widget menuRow(IconData icon, String label, VoidCallback action) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, size: 21, color: forest),
    title: Text(
      label,
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
    ),
    trailing: const Icon(Icons.chevron_right, size: 18, color: muted),
    onTap: action,
  );
  void showNotifications() => sheet(
    'Les nouvelles du terrain',
    Column(
      children: [
        menuRow(Icons.calendar_month, 'La séance de Lucas est confirmée', () {
          Navigator.pop(context);
          go(2);
        }),
        const Divider(),
        menuRow(
          Icons.emoji_events_outlined,
          'Little Champions Cup approche',
          () {
            Navigator.pop(context);
            go(3);
          },
        ),
        const PreviewFootnote(),
      ],
    ),
  );
  Future<void> addPlayer() async {
    final controller = TextEditingController();
    final key = GlobalKey<FormState>();
    await sheet(
      'Un nouveau joueur dans l’équipe',
      Form(
        key: key,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Prénom du joueur'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Indiquez un prénom.' : null,
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: () {
                if (!key.currentState!.validate()) return;
                setState(() {
                  players.add(controller.text.trim());
                  child = players.length - 1;
                });
                Navigator.pop(context);
                notify('Joueur ajouté à votre famille de démonstration.');
              },
              child: const Text('Ajouter à ma famille'),
            ),
            const PreviewFootnote(),
          ],
        ),
      ),
    );
    // The closing sheet can still paint during its reverse animation.
    await Future<void>.delayed(const Duration(milliseconds: 350));
    controller.dispose();
  }

  void playerDetails(String name) => sheet(
    'Les progrès de $name',
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: Avatar(name[0], size: 70)),
        const SizedBox(height: 20),
        const Center(child: StatusBadge('Orange · U10')),
        const SizedBox(height: 22),
        const Panel(
          child: Row(
            children: [
              Expanded(child: Metric('8', 'séances suivies')),
              Expanded(child: Metric('4', 'séances restantes')),
            ],
          ),
        ),
        const SizedBox(height: 23),
        ...[
          ('Service', .72),
          ('Coup droit', .84),
          ('Revers', .65),
          ('Déplacements', .78),
        ].map(
          (s) => Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(s.$1, style: const TextStyle(fontSize: 12)),
                    Text(
                      '${(s.$2 * 100).round()} %',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: s.$2,
                    color: forest,
                    backgroundColor: line,
                    minHeight: 6,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Panel(
          color: Color(0xFFEDF3DE),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Le mot du coach',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 8),
              Text(
                'Une belle énergie sur le terrain ! On continue à travailler le service, les progrès sont déjà là.',
                style: TextStyle(fontSize: 12),
              ),
              SizedBox(height: 8),
              Text(
                'David Kengne · Exemple d’évaluation',
                style: TextStyle(fontSize: 10, color: muted),
              ),
            ],
          ),
        ),
        const PreviewFootnote(),
      ],
    ),
  );
  void invoices() => sheet(
    'Mes factures & forfaits',
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Panel(
          color: forest,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow('LE FORFAIT DE LUCAS', color: lime),
              SizedBox(height: 12),
              Text(
                '12 séances pour progresser',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 10),
              Text(
                '4 séances restantes · Tennis privé',
                style: TextStyle(color: Color(0xFFBDCCB3), fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ...[
          ('INV-001', '180 000 FCFA', 'Réglée'),
          ('INV-002', '64 000 FCFA', 'En attente'),
        ].map(
          (f) => Padding(
            padding: const EdgeInsets.only(bottom: 13),
            child: Panel(
              child: Row(
                children: [
                  const Icon(Icons.receipt_long_outlined, color: muted),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.$1,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          f.$2,
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  StatusBadge(f.$3),
                ],
              ),
            ),
          ),
        ),
        const PreviewFootnote(),
      ],
    ),
  );
  void editProfile() => sheet(
    'Informations personnelles',
    Form(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            initialValue: coachMode ? 'David Kengne' : 'Sophie Martin',
            decoration: const InputDecoration(labelText: 'Nom complet'),
            readOnly: true,
          ),
          const SizedBox(height: 15),
          TextFormField(
            initialValue: 'sophie@example.test',
            decoration: const InputDecoration(labelText: 'Adresse e-mail'),
            readOnly: true,
          ),
          const SizedBox(height: 15),
          const Text(
            'Le compte est fictif. La modification du profil sera reliée au backend ultérieurement.',
            style: TextStyle(fontSize: 12, color: muted),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    ),
  );

  Widget coachHome() => page(
    children: [
      heading(
        'FAIRE GRANDIR LE TALENT',
        'Bonjour, David.',
        trailing: IconButton(
          tooltip: 'Notifications',
          onPressed: showNotifications,
          icon: const Icon(Icons.notifications_none),
        ),
      ),
      const Panel(
        color: forest,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Eyebrow('AUJOURD’HUI, ON PROGRESSE', color: lime),
            SizedBox(height: 16),
            Text(
              'Votre équipe.\nVotre impact.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 30,
                height: 1.15,
              ),
            ),
            SizedBox(height: 17),
            Text(
              'Chaque conseil peut faire la différence.',
              style: TextStyle(color: Color(0xFFBDCCB3), fontSize: 12),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      const Row(
        children: [
          Expanded(child: Panel(child: Metric('3', 'séances du jour'))),
          SizedBox(width: 12),
          Expanded(child: Panel(child: Metric('12', 'joueurs attendus'))),
        ],
      ),
      section('Votre prochaine séance'),
      const Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusBadge('17:30 · Court central'),
            SizedBox(height: 13),
            Text(
              'Perfectionnement tennis',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
            ),
            SizedBox(height: 7),
            Text(
              'Groupe Orange U10 · 60 minutes',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        ),
      ),
      section('Présences & suivi'),
      ...players.map(
        (name) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Panel(
            child: Column(
              children: [
                Row(
                  children: [
                    Avatar(name[0]),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Switch(
                      value: attendance[name] ?? false,
                      onChanged: (value) =>
                          setState(() => attendance[name] = value),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      attendance[name] == true
                          ? 'Présence confirmée'
                          : 'À confirmer',
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                    TextButton(
                      onPressed: () => evaluation(name),
                      child: const Text(
                        'Évaluer',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      const PreviewFootnote(),
    ],
  );
  void evaluation(String name) {
    double score = 3;
    sheet(
      'Évaluation de $name',
      StatefulBuilder(
        builder: (context, update) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Technique & engagement',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            Text(
              '${score.round()} / 5',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Slider(
              value: score,
              min: 1,
              max: 5,
              divisions: 4,
              label: '${score.round()}',
              onChanged: (v) => update(() => score = v),
            ),
            const TextField(
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Le mot du coach',
                hintText: 'Un encouragement, un objectif…',
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                notify('Évaluation de $name simulée : ${score.round()}/5.');
              },
              child: const Text('Simuler l’enregistrement'),
            ),
            const PreviewFootnote(),
          ],
        ),
      ),
    );
  }
}

String monthName(int month) => [
  'JAN',
  'FÉV',
  'MARS',
  'AVR',
  'MAI',
  'JUIN',
  'JUIL',
  'AOÛT',
  'SEPT',
  'OCT',
  'NOV',
  'DÉC',
][month - 1];

class BookingFlow extends StatefulWidget {
  const BookingFlow({
    super.key,
    required this.sport,
    required this.players,
    required this.selectedPlayer,
  });
  final String sport, selectedPlayer;
  final List<String> players;
  @override
  State<BookingFlow> createState() => _BookingFlowState();
}

class _BookingFlowState extends State<BookingFlow> {
  int step = 0;
  String package = 'Cours privé';
  late String player = widget.selectedPlayer;
  String coach = 'David Kengne';
  DateTime date = DateTime.now().add(const Duration(days: 1));
  String time = '17:30';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        'Réserver · ${widget.sport}',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      leading: IconButton(
        tooltip: 'Retour',
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          if (step > 0) {
            setState(() => step--);
          } else {
            Navigator.pop(context);
          }
        },
      ),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: List.generate(
                  3,
                  (i) => Expanded(
                    child: Container(
                      height: 4,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: i <= step ? forest : line,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 27),
              Eyebrow('ÉTAPE ${step + 1} SUR 3'),
              const SizedBox(height: 8),
              Text(
                ['La bonne formule.', 'Le bon moment.', 'Tout est prêt.'][step],
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 10),
              Text(
                [
                  'Une séance adaptée à son envie de progresser.',
                  'Choisissez les personnes et le créneau.',
                  'Vérifiez les détails de votre réservation.',
                ][step],
                style: const TextStyle(color: muted),
              ),
              const SizedBox(height: 28),
              if (step == 0)
                ...[
                  'Cours privé',
                  'Cours semi-privé',
                  'Cours collectif',
                ].asMap().entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: InkWell(
                      onTap: () => setState(() => package = entry.value),
                      borderRadius: BorderRadius.circular(20),
                      child: Panel(
                        color: package == entry.value
                            ? const Color(0xFFEDF3DE)
                            : Colors.white,
                        child: Row(
                          children: [
                            Icon(
                              package == entry.value
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_unchecked,
                              color: forest,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    entry.value,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    [
                                      'Toute l’attention du coach',
                                      'Progresser à deux',
                                      'L’énergie du groupe',
                                    ][entry.key],
                                    style: const TextStyle(
                                      color: muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    '${['15 000', '12 000', '8 000'][entry.key]} FCFA · 60 min',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (step == 1) ...[
                DropdownButtonFormField<String>(
                  initialValue: player,
                  decoration: const InputDecoration(labelText: 'Votre joueur'),
                  items: widget.players
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) => setState(() => player = v!),
                ),
                const SizedBox(height: 18),
                DropdownButtonFormField<String>(
                  initialValue: coach,
                  decoration: const InputDecoration(labelText: 'Votre coach'),
                  items: ['David Kengne', 'Émilie Mballa', 'Marc Essama']
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() => coach = v!),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 90)),
                    );
                    if (picked != null && mounted) {
                      setState(() => date = picked);
                    }
                  },
                  icon: const Icon(Icons.calendar_month, size: 19),
                  label: Text(
                    '${date.day} ${monthName(date.month)} ${date.year}',
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Créneaux de démonstration',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 5,
                  children:
                      ['09:00', '10:30', '14:00', '16:00', '17:30', '18:30']
                          .map(
                            (t) => ChoiceChip(
                              label: Text(t),
                              selected: time == t,
                              onSelected: (_) => setState(() => time = t),
                            ),
                          )
                          .toList(),
                ),
              ],
              if (step == 2) ...[
                Panel(
                  child: Column(
                    children: [
                      InfoRow(
                        Icons.sports_tennis,
                        'Séance',
                        '${widget.sport} · $package',
                      ),
                      InfoRow(Icons.person_outline, 'Joueur', player),
                      InfoRow(Icons.school_outlined, 'Coach', coach),
                      InfoRow(
                        Icons.calendar_month,
                        'Date',
                        '${date.day} ${monthName(date.month)} · $time',
                      ),
                      const InfoRow(
                        Icons.location_on_outlined,
                        'Lieu',
                        'Tennis Club Bonanjo',
                      ),
                      const Divider(),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(child: Text('Montant indicatif')),
                          const SizedBox(width: 12),
                          Text(
                            '${package == 'Cours privé'
                                ? '15 000'
                                : package == 'Cours semi-privé'
                                ? '12 000'
                                : '8 000'} FCFA',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Aucun paiement ne sera effectué. Cette réservation permet de découvrir le parcours.',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
              const SizedBox(height: 30),
              FilledButton.icon(
                onPressed: () {
                  if (step < 2) {
                    setState(() => step++);
                  } else {
                    Navigator.pop(
                      context,
                      PreviewBooking(
                        title: '${widget.sport} · $package',
                        date: date,
                        time: time,
                        player: player,
                        coach: coach,
                        sport: widget.sport,
                      ),
                    );
                  }
                },
                label: Text(
                  step == 2 ? 'Confirmer dans l’aperçu' : 'Continuer',
                ),
                icon: const Icon(Icons.arrow_forward, size: 18),
                iconAlignment: IconAlignment.end,
              ),
              const PreviewFootnote(),
            ],
          ),
        ),
      ),
    ),
  );
}

class WelcomePreview extends StatefulWidget {
  const WelcomePreview({super.key, required this.onEnter});
  final VoidCallback onEnter;
  @override
  State<WelcomePreview> createState() => _WelcomePreviewState();
}

class _WelcomePreviewState extends State<WelcomePreview> {
  int page = 0;
  bool login = false;
  final form = GlobalKey<FormState>();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.all(28),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SportaMark(),
                  TextButton(
                    onPressed: widget.onEnter,
                    child: const Text(
                      'Explorer',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              if (!login) ...[
                Container(
                  height: 250,
                  decoration: BoxDecoration(
                    color: forest,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Transform.rotate(
                        angle: -.25,
                        child: const CourtDrawing(width: 175, height: 210),
                      ),
                      Positioned(
                        right: 55,
                        top: 55,
                        child: Container(
                          width: 70,
                          height: 70,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: lime,
                          ),
                          child: Icon(
                            [
                              Icons.sports_tennis,
                              Icons.groups_outlined,
                              Icons.emoji_events_outlined,
                            ][page],
                            size: 36,
                            color: forest,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 35),
                Eyebrow('PLAY. GROW. TOGETHER. · 0${page + 1}'),
                const SizedBox(height: 15),
                Text(
                  [
                    'Chaque point raconte une histoire.',
                    'Son équipe, toujours à portée.',
                    'De petits rêves aux grands trophées.',
                  ][page],
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 15),
                Text(
                  [
                    'Suivez les progrès, célébrez les efforts et gardez chaque beau souvenir.',
                    'Coachs, parents et académie réunis autour de son épanouissement.',
                    'Cours, défis et tournois : un parcours motivant, construit à son rythme.',
                  ][page],
                  style: const TextStyle(color: muted, height: 1.7),
                ),
                const SizedBox(height: 28),
                Row(
                  children: List.generate(
                    3,
                    (i) => Container(
                      width: i == page ? 25 : 7,
                      height: 7,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: i == page ? forest : line,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                FilledButton.icon(
                  onPressed: () => setState(() {
                    if (page < 2) {
                      page++;
                    } else {
                      login = true;
                    }
                  }),
                  label: Text(page == 2 ? 'C’est parti' : 'Continuer'),
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  iconAlignment: IconAlignment.end,
                ),
                TextButton(
                  onPressed: () => setState(() => login = true),
                  child: const Text('J’ai déjà un compte'),
                ),
              ] else ...[
                const SizedBox(height: 25),
                Text(
                  'Heureux de vous retrouver.',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 14),
                const Text(
                  'Votre académie vous attend.',
                  style: TextStyle(color: muted),
                ),
                const SizedBox(height: 30),
                Form(
                  key: form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Adresse e-mail',
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) => v == null || !v.contains('@')
                            ? 'Indiquez une adresse e-mail.'
                            : null,
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Mot de passe',
                        ),
                        obscureText: true,
                        validator: (v) => v == null || v.length < 6
                            ? 'Au moins 6 caractères.'
                            : null,
                      ),
                      const SizedBox(height: 28),
                      FilledButton(
                        onPressed: () {
                          if (form.currentState!.validate()) widget.onEnter();
                        },
                        child: const Text('Ouvrir l’aperçu'),
                      ),
                      const SizedBox(height: 15),
                      OutlinedButton(
                        onPressed: widget.onEnter,
                        child: const Text('Explorer sans compte'),
                      ),
                    ],
                  ),
                ),
              ],
              const PreviewFootnote(),
            ],
          ),
        ),
      ),
    ),
  );
}

class ChatPreview extends StatefulWidget {
  const ChatPreview({super.key});
  @override
  State<ChatPreview> createState() => _ChatPreviewState();
}

class _ChatPreviewState extends State<ChatPreview> {
  final controller = TextEditingController();
  final List<String> messages = [
    'Lucas a fait une très belle séance aujourd’hui ! Son service est de plus en plus précis.',
    'Merci David, il était ravi en rentrant !',
  ];
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Coach David',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          Text(
            'Conversation de démonstration',
            style: TextStyle(fontSize: 10, color: muted),
          ),
        ],
      ),
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Center(child: Eyebrow('AUJOURD’HUI')),
                const SizedBox(height: 28),
                ...messages.asMap().entries.map(
                  (e) => Align(
                    alignment: e.key == 0
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 310),
                      padding: const EdgeInsets.all(17),
                      margin: const EdgeInsets.only(bottom: 18),
                      decoration: BoxDecoration(
                        color: e.key == 0 ? Colors.white : forest,
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Text(
                        e.value,
                        style: TextStyle(
                          color: e.key == 0 ? forest : Colors.white,
                          height: 1.6,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      hintText: 'Votre message…',
                    ),
                    onSubmitted: (_) => send(),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(
                  tooltip: 'Envoyer',
                  onPressed: send,
                  icon: const Icon(Icons.arrow_upward),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  void send() {
    if (controller.text.trim().isEmpty) return;
    setState(() => messages.add(controller.text.trim()));
    controller.clear();
  }
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.color = Colors.white,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final Color color;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color == Colors.white ? line : color),
    ),
    child: child,
  );
}

class Avatar extends StatelessWidget {
  const Avatar(
    this.text, {
    super.key,
    this.dark = false,
    this.color = const Color(0xFFEDF3DE),
    this.size = 42,
  });
  final String text;
  final bool dark;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: dark ? forest : color,
      borderRadius: BorderRadius.circular(size * .3),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: size * .3,
        fontWeight: FontWeight.w700,
        color: dark ? lime : forest,
      ),
    ),
  );
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color = muted});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      color: color,
    ),
  );
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) {
    final warm = ['En attente', 'Complet', 'Annulée'].contains(label);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: warm ? const Color(0xFFFAF0DF) : const Color(0xFFEDF3DE),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          '•  $label',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: warm ? const Color(0xFFA88745) : const Color(0xFF63804B),
          ),
        ),
      ),
    );
  }
}

class PreviewBadge extends StatelessWidget {
  const PreviewBadge({super.key});
  @override
  Widget build(BuildContext context) => const Text(
    '● APERÇU',
    style: TextStyle(
      fontSize: 8,
      letterSpacing: 1,
      color: Color(0xFF8B9D6B),
      fontWeight: FontWeight.w700,
    ),
  );
}

class PreviewFootnote extends StatelessWidget {
  const PreviewFootnote({super.key});
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(top: 27),
    child: Text(
      'Aperçu du design · Données fictives\nModifications locales, réinitialisées au redémarrage.',
      textAlign: TextAlign.center,
      style: TextStyle(color: muted, fontSize: 9, height: 1.7),
    ),
  );
}

class Metric extends StatelessWidget {
  const Metric(this.value, this.label, {super.key});
  final String value, label;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          fontSize: 25,
          fontWeight: FontWeight.w800,
          color: forest,
          letterSpacing: -1,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        label,
        style: const TextStyle(fontSize: 9, color: muted),
        textAlign: TextAlign.center,
      ),
    ],
  );
}

class InfoRow extends StatelessWidget {
  const InfoRow(this.icon, this.label, this.value, {super.key});
  final IconData icon;
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 19),
    child: Row(
      children: [
        Icon(icon, size: 21, color: muted),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: muted, fontSize: 10)),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class SportaMark extends StatelessWidget {
  const SportaMark({super.key});
  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Avatar('s↗', dark: true),
      SizedBox(width: 10),
      Text(
        'sporta.',
        style: TextStyle(
          color: forest,
          fontSize: 29,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.8,
        ),
      ),
    ],
  );
}

class CourtDrawing extends StatelessWidget {
  const CourtDrawing({super.key, required this.width, required this.height});
  final double width, height;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(width, height), painter: _CourtPainter());
}

class _CourtPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF7D9E78).withValues(alpha: .45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)),
      paint,
    );
    canvas.drawRect(Rect.fromLTWH(15, 0, size.width - 30, size.height), paint);
    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint,
    );
    canvas.drawLine(
      Offset(15, size.height * .25),
      Offset(size.width - 15, size.height * .25),
      paint,
    );
    canvas.drawLine(
      Offset(15, size.height * .75),
      Offset(size.width - 15, size.height * .75),
      paint,
    );
    canvas.drawLine(
      Offset(size.width / 2, size.height * .25),
      Offset(size.width / 2, size.height * .75),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
