import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/ui.dart';
import '../../core/localization/app_language.dart';
import '../../data/firebase_profile_repository.dart';

enum AuthSheetResult { signedIn, registered }

Future<AuthSheetResult?> showAuthSheet(
  BuildContext context, {
  required String audience,
  bool allowRegistration = false,
}) => showModalBottomSheet<AuthSheetResult>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) =>
      AuthSheet(audience: audience, allowRegistration: allowRegistration),
);

class AuthSheet extends StatefulWidget {
  const AuthSheet({
    super.key,
    required this.audience,
    this.allowRegistration = false,
  });

  final String audience;
  final bool allowRegistration;

  @override
  State<AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends State<AuthSheet> {
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  bool register = false;
  bool loading = false;
  bool obscurePassword = true;
  String? error;
  String? info;
  final children = <_ChildDraft>[];
  List<PlayerSessionConfiguration> configurations = const [];

  @override
  void initState() {
    super.initState();
    FirebaseProfileRepository().loadPlayerConfigurations().then((value) {
      if (mounted) setState(() => configurations = value);
    });
  }

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
    for (final child in children) {
      child.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (email.text.trim().isEmpty ||
        password.text.length < 6 ||
        (register && name.text.trim().isEmpty)) {
      setState(
        () => error = 'Veuillez compléter correctement tous les champs.',
      );
      return;
    }
    setState(() {
      loading = true;
      error = null;
      info = null;
    });
    try {
      if (register) {
        final credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
              email: email.text.trim(),
              password: password.text,
            );
        await credential.user?.updateDisplayName(name.text.trim());
        await FirebaseFunctions.instanceFor(
          region: 'europe-west1',
        ).httpsCallable('registerUserProfile').call(<String, Object>{
          'displayName': name.text.trim(),
          'accountType': widget.audience == 'student' ? 'student' : 'parent',
          'preferredLanguage': AppLanguageController.isEnglish ? 'en' : 'fr',
        });
        for (final child in children) {
          final childAge = int.tryParse(child.age.text.trim());
          if (child.firstName.text.trim().isEmpty ||
              child.lastName.text.trim().isEmpty ||
              childAge == null ||
              childAge < 3 ||
              childAge > 80) {
            throw const FormatException('CHILD_INVALID');
          }
          if (child.sessionConfigurationId == null ||
              child.paymentMethod == null) {
            throw const FormatException('CHILD_OPTIONS_REQUIRED');
          }
          await FirebaseFunctions.instanceFor(
            region: 'europe-west1',
          ).httpsCallable('createPlayerProfile').call(<String, Object>{
            'firstName': child.firstName.text.trim(),
            'lastName': child.lastName.text.trim(),
            'age': childAge,
            'gender': child.gender,
            'sessionConfigurationId': child.sessionConfigurationId!,
            'paymentMethod': child.paymentMethod!,
          });
        }
      } else {
        final credential = await FirebaseAuth.instance
            .signInWithEmailAndPassword(
              email: email.text.trim(),
              password: password.text,
            );
        final profile = await FirebaseFirestore.instance
            .collection('users')
            .doc(credential.user!.uid)
            .get();
        final role = profile.data()?['role']?.toString();
        final active = profile.data()?['status'] == 'active';
        final expected = widget.audience == 'coach'
            ? role == 'coach'
            : role == 'parent' || role == 'student';
        if (!profile.exists || !active || !expected) {
          await FirebaseAuth.instance.signOut();
          throw FormatException(
            widget.audience == 'coach' ? 'COACH_ACCESS' : 'STUDENT_ACCESS',
          );
        }
      }
      if (mounted) {
        Navigator.of(
          context,
        ).pop(register ? AuthSheetResult.registered : AuthSheetResult.signedIn);
      }
    } on FirebaseAuthException catch (exception) {
      setState(
        () => error = switch (exception.code) {
          'email-already-in-use' => 'Cette adresse e-mail est déjà utilisée.',
          'weak-password' =>
            'Le mot de passe doit contenir au moins 6 caractères.',
          'invalid-credential' => 'E-mail ou mot de passe incorrect.',
          _ => 'Authentification impossible. Réessayez.',
        },
      );
    } on FormatException catch (exception) {
      setState(
        () => error = switch (exception.message) {
          'COACH_ACCESS' =>
            'Ce compte n’est pas un compte coach actif. Contactez votre administrateur.',
          'STUDENT_ACCESS' =>
            'Ce compte est réservé à un autre espace SportA.',
          _ =>
            exception.message == 'CHILD_OPTIONS_REQUIRED'
                ? 'Choisissez une séance et un mode de paiement pour chaque joueur.'
                : 'Complétez correctement chaque profil joueur (âge de 3 à 80 ans).',
        },
      );
    } catch (_) {
      setState(() => error = 'Impossible de créer le profil. Réessayez.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> resetPassword() async {
    final address = email.text.trim().toLowerCase();
    if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(address)) {
      setState(() {
        error = 'Saisissez d’abord une adresse e-mail valide.';
        info = null;
      });
      return;
    }
    setState(() {
      loading = true;
      error = null;
      info = null;
    });
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: address);
      if (mounted) {
        setState(
          () => info =
              'Si un compte correspond à cette adresse, un lien de réinitialisation vient d’être envoyé.',
        );
      }
    } on FirebaseAuthException catch (exception) {
      if (!mounted) return;
      setState(() {
        if (exception.code == 'too-many-requests') {
          error = 'Trop de tentatives. Réessayez dans quelques minutes.';
        } else if (exception.code == 'invalid-email') {
          error = 'Saisissez d’abord une adresse e-mail valide.';
        } else if (exception.code == 'user-not-found') {
          info =
              'Si un compte correspond à cette adresse, un lien de réinitialisation vient d’être envoyé.';
        } else {
          error = 'Impossible d’envoyer le lien. Réessayez.';
        }
      });
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
        16,
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
            Icon(
              widget.audience == 'coach'
                  ? Icons.sports_tennis
                  : Icons.family_restroom,
              size: 42,
              color: AppColors.ink,
            ),
            const SizedBox(height: 12),
            LText(
              register
                  ? 'Créer mon profil'
                  : widget.audience == 'coach'
                  ? 'Connexion coach'
                  : 'Se connecter pour réserver',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            LText(
              register
                  ? 'Votre profil protège et personnalise vos réservations.'
                  : 'Utilisez votre adresse e-mail et votre mot de passe.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 22),
            if (error != null) ...[
              LText(error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(
                    child: LText(
                      'Profils joueurs',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => children.add(_ChildDraft())),
                    icon: const Icon(Icons.add),
                    label: const LText('Ajouter un joueur'),
                  ),
                ],
              ),
              const LText(
                'Facultatif : vous pourrez aussi ajouter d’autres joueurs depuis votre profil.',
                style: TextStyle(fontSize: 11, color: AppColors.muted),
              ),
              ...children.asMap().entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.cloud,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: LText(
                                'Joueur ${entry.key + 1}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => setState(() {
                                final removed = children.removeAt(entry.key);
                                removed.dispose();
                              }),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        TextField(
                          controller: entry.value.firstName,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(labelText: tr('Prénom')),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: entry.value.lastName,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(labelText: tr('Nom')),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: entry.value.age,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setState(() {
                                  final childAge = int.tryParse(
                                    entry.value.age.text.trim(),
                                  );
                                  if (childAge == null ||
                                      !configurations.any(
                                        (item) =>
                                            item.id ==
                                                entry
                                                    .value
                                                    .sessionConfigurationId &&
                                            item.accepts(childAge),
                                      )) {
                                    entry.value.sessionConfigurationId = null;
                                  }
                                }),
                                decoration: InputDecoration(
                                  labelText: tr('Âge'),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: entry.value.gender,
                                decoration: InputDecoration(
                                  labelText: tr('Sexe'),
                                ),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'female',
                                    child: LText('Fille'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'male',
                                    child: LText('Garçon'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'woman',
                                    child: LText('Femme'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'man',
                                    child: LText('Homme'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'other',
                                    child: LText('Autre'),
                                  ),
                                ],
                                onChanged: (value) => entry.value.gender =
                                    value ?? entry.value.gender,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          key: ValueKey(entry.value.sessionConfigurationId),
                          initialValue: entry.value.sessionConfigurationId,
                          decoration: InputDecoration(
                            labelText: tr('Type de séance'),
                          ),
                          items: configurations
                              .where((item) {
                                final childAge = int.tryParse(
                                  entry.value.age.text.trim(),
                                );
                                return childAge != null &&
                                    item.accepts(childAge);
                              })
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item.id,
                                  child: Text(
                                    tr(item.label),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => setState(
                            () => entry.value.sessionConfigurationId = value,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          key: ValueKey(entry.value.paymentMethod),
                          initialValue: entry.value.paymentMethod,
                          decoration: InputDecoration(
                            labelText: tr('Mode de paiement'),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'cash',
                              child: LText('Cash'),
                            ),
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
                          onChanged: (value) =>
                              setState(() => entry.value.paymentMethod = value),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (info != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: LText(
                  info!,
                  style: const TextStyle(color: AppColors.green),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (register) ...[
              TextField(
                controller: name,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: tr('Nom complet'),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
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
              obscureText: obscurePassword,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: tr('Mot de passe'),
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: tr(
                    obscurePassword
                        ? 'Afficher le mot de passe'
                        : 'Masquer le mot de passe',
                  ),
                  onPressed: () =>
                      setState(() => obscurePassword = !obscurePassword),
                  icon: Icon(
                    obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            if (!register)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: loading ? null : resetPassword,
                  child: const LText('Mot de passe oublié ?'),
                ),
              ),
            const SizedBox(height: 16),
            AppButton(
              loading
                  ? 'Veuillez patienter...'
                  : register
                  ? 'Créer mon profil'
                  : 'Se connecter',
              icon: register ? Icons.person_add_alt_1 : Icons.login,
              onPressed: loading ? null : submit,
            ),
            if (widget.allowRegistration)
              TextButton(
                onPressed: loading
                    ? null
                    : () => setState(() {
                        register = !register;
                        error = null;
                        info = null;
                      }),
                child: LText(
                  register ? 'J’ai déjà un compte' : 'Créer un nouveau profil',
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _ChildDraft {
  final firstName = TextEditingController();
  final lastName = TextEditingController();
  final age = TextEditingController();
  String gender = 'female';
  String? sessionConfigurationId;
  String? paymentMethod;
  void dispose() {
    firstName.dispose();
    lastName.dispose();
    age.dispose();
  }
}
