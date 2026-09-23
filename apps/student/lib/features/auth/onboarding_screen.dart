import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/theme/app_theme.dart';
import '../../core/navigation/app_access_controller.dart';
import '../../core/widgets/ui.dart';
import '../../core/localization/app_language.dart';
import 'auth_sheet.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final controller = PageController();
  int page = 0;
  static const pages = [
    (
      'Chaque point raconte une histoire.',
      'Suivez les progrès, célébrez les efforts et gardez chaque beau souvenir.',
      Icons.sports_tennis_rounded,
      Color(0xFFE6F7FD),
    ),
    (
      'Son équipe, toujours à portée.',
      'Coachs, parents et académie réunis autour de ce qui compte : son épanouissement.',
      Icons.groups_rounded,
      Color(0xFFE9F5EF),
    ),
    (
      'Des rêves aux premiers trophées.',
      'Cours, défis et tournois : un parcours motivant, construit à son rythme.',
      Icons.emoji_events_rounded,
      Color(0xFFFFF1DD),
    ),
  ];
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  static const posters = [
    'assets/images/onboarding-open-day.jpg',
    'assets/images/onboarding-camp.jpg',
  ];

  void _showPoster(int index) => showDialog<void>(
    context: context,
    builder: (context) => Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Image.asset(
                posters[index],
                fit: BoxFit.contain,
                semanticLabel: tr(
                  index == 0
                      ? 'Affiche de la journée portes ouvertes tennis et padel'
                      : 'Affiche du stage de tennis et padel d’octobre',
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filled(
                tooltip: tr('Fermer'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: page < posters.length ? Colors.black : Colors.white,
    body: Stack(
      fit: StackFit.expand,
      children: [
        if (page < posters.length)
          Image.asset(
            posters[page],
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            excludeFromSemantics: true,
          ),
        if (page < posters.length)
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xB3000000),
                  Color(0x55000000),
                  Color(0xED000000),
                  Colors.black,
                ],
                stops: [0, .32, .7, 1],
              ),
            ),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 22),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _Logo(onDark: page < posters.length)),
                    TextButton(
                      onPressed: () => _showAudienceChoice(context),
                      child: LText(
                        'Passer',
                        style: TextStyle(
                          color: page < posters.length
                              ? Colors.white
                              : AppColors.muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: PageView.builder(
                    controller: controller,
                    onPageChanged: (i) => setState(() => page = i),
                    itemCount: pages.length,
                    itemBuilder: (_, i) {
                      final p = pages[i];
                      return LayoutBuilder(
                        builder: (context, constraints) =>
                            SingleChildScrollView(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 24,
                                  ),
                                  child: Column(
                                    mainAxisAlignment: i < posters.length
                                        ? MainAxisAlignment.end
                                        : MainAxisAlignment.center,
                                    children: [
                                      if (i < posters.length)
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.white,
                                            backgroundColor: const Color(
                                              0x66000000,
                                            ),
                                            side: const BorderSide(
                                              color: Colors.white54,
                                            ),
                                          ),
                                          onPressed: () => _showPoster(i),
                                          icon: const Icon(
                                            Icons.fullscreen_rounded,
                                          ),
                                          label: const LText('Voir l’affiche'),
                                        ),
                                      if (i >= posters.length)
                                        Container(
                                          width: 190,
                                          height: 190,
                                          decoration: BoxDecoration(
                                            color: p.$4,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            p.$3,
                                            size: 88,
                                            color: AppColors.ink,
                                          ),
                                        ),
                                      const SizedBox(height: 24),
                                      LText(
                                        p.$1,
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .displaySmall
                                            ?.copyWith(
                                              color: i < posters.length
                                                  ? Colors.white
                                                  : AppColors.ink,
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(height: 16),
                                      LText(
                                        p.$2,
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyLarge
                                            ?.copyWith(
                                              color: i < posters.length
                                                  ? Colors.white
                                                  : AppColors.muted,
                                              height: 1.5,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                      );
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    pages.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.all(4),
                      height: 7,
                      width: page == i ? 24 : 7,
                      decoration: BoxDecoration(
                        color: page == i
                            ? (page < posters.length
                                  ? AppColors.orange
                                  : AppColors.ink)
                            : (page < posters.length
                                  ? Colors.white38
                                  : AppColors.line),
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                AppButton(
                  page == pages.length - 1
                      ? 'Commencer l’aventure'
                      : 'Continuer',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: () {
                    if (page < pages.length - 1) {
                      controller.nextPage(
                        duration: const Duration(milliseconds: 450),
                        curve: Curves.easeOutCubic,
                      );
                    } else {
                      _showAudienceChoice(context);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
  void _showAudienceChoice(BuildContext context) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => Container(
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        24 + MediaQuery.paddingOf(sheetContext).bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: AppColors.line,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          const SizedBox(height: 24),
          LText(
            'Comment utilisez-vous SportA ?',
            style: Theme.of(sheetContext).textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const LText(
            'Choisissez votre espace pour continuer.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 22),
          AppButton(
            'Je suis parent ou élève',
            icon: Icons.family_restroom,
            onPressed: () {
              Navigator.pop(sheetContext);
              AppAccessController.grantGuestAccess();
              context.go('/home');
            },
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
            ),
            onPressed: () async {
              Navigator.pop(sheetContext);
              final result = await showAuthSheet(context, audience: 'coach');
              if (result == AuthSheetResult.signedIn && context.mounted) {
                context.go('/coach');
              }
            },
            icon: const Icon(Icons.sports_tennis),
            label: const LText('Je suis coach'),
          ),
        ],
      ),
    ),
  );
}

class _Logo extends StatelessWidget {
  const _Logo({this.onDark = false});
  final bool onDark;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Image.asset(
          'assets/images/challengeme-academy-logo.jpg',
          width: 48,
          height: 48,
          fit: BoxFit.contain,
        ),
      ),
      const SizedBox(width: 10),
      Flexible(
        child: LText(
          'SportA',
          style: TextStyle(
            color: onDark ? Colors.white : AppColors.ink,
            fontSize: 19,
            fontWeight: FontWeight.w900,
            letterSpacing: -.7,
          ),
        ),
      ),
    ],
  );
}

class _LoginSheet extends StatefulWidget {
  const _LoginSheet();
  @override
  State<_LoginSheet> createState() => _LoginSheetState();
}

class _LoginSheetState extends State<_LoginSheet> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool loading = false;
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.text.trim(),
        password: password.text,
      );
      if (mounted) context.go('/home');
    } on FirebaseAuthException catch (exception) {
      setState(
        () => error = exception.code == 'invalid-credential'
            ? 'E-mail ou mot de passe incorrect.'
            : 'Connexion impossible. Réessayez.',
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(
      24,
      16,
      24,
      24 + MediaQuery.paddingOf(context).bottom,
    ),
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 5,
          decoration: BoxDecoration(
            color: AppColors.line,
            borderRadius: BorderRadius.circular(5),
          ),
        ),
        const SizedBox(height: 26),
        const _Logo(),
        const SizedBox(height: 22),
        LText(
          'Heureux de vous revoir',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const LText(
          'Retrouvez le parcours de Lucas en un instant.',
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 26),
        if (error != null) ...[
          LText(error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: InputDecoration(
            labelText: tr('Adresse e-mail'),
            prefixIcon: const Icon(Icons.mail_outline),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: password,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            labelText: tr('Mot de passe'),
            prefixIcon: const Icon(Icons.lock_outline),
          ),
        ),
        const SizedBox(height: 16),
        AppButton(
          loading ? 'Connexion...' : 'Se connecter',
          icon: Icons.mail_outline,
          onPressed: loading ? null : login,
        ),
        const SizedBox(height: 16),
        const LText(
          'En continuant, vous acceptez nos Conditions d’utilisation.',
          style: TextStyle(fontSize: 11, color: AppColors.muted),
        ),
      ],
    ),
  );
}
