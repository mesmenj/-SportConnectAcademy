import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class SportATenantApp extends StatelessWidget {
  const SportATenantApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SportA',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF175B4B)),
      useMaterial3: true,
    ),
    home: StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting)
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        final user = snapshot.data;
        return user == null
            ? const _Login()
            : _Academies(key: ValueKey(user.uid), uid: user.uid);
      },
    ),
  );
}

class _Login extends StatefulWidget {
  const _Login();
  @override
  State<_Login> createState() => _LoginState();
}

class _LoginState extends State<_Login> {
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.text.trim(),
        password: password.text,
      );
    } catch (_) {
      if (mounted)
        setState(
          () => error =
              'Connexion impossible. Vérifiez vos identifiants et la connexion.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.sports_tennis,
                  size: 64,
                  color: Color(0xFF175B4B),
                ),
                const SizedBox(height: 20),
                Text(
                  'SportA',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displaySmall,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Votre sport. Votre académie.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.username],
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: password,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(labelText: 'Mot de passe'),
                  onSubmitted: (_) {
                    if (!busy) login();
                  },
                ),
                const SizedBox(height: 24),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
                FilledButton(
                  onPressed: busy ? null : login,
                  child: Text(busy ? 'Connexion…' : 'Se connecter'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _Academies extends StatelessWidget {
  const _Academies({super.key, required this.uid});
  final String uid;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Mes académies'),
      actions: [
        IconButton(
          tooltip: 'Se déconnecter',
          onPressed: () => FirebaseAuth.instance.signOut(),
          icon: const Icon(Icons.logout),
        ),
      ],
    ),
    body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('memberships')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return const Center(
            child: Text('Impossible de charger vos académies.'),
          );
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final academies = snapshot.data!.docs;
        if (academies.isEmpty)
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Aucune académie associée à votre compte. Contactez votre académie.',
              ),
            ),
          );
        return ListView(
          padding: const EdgeInsets.all(20),
          children: academies
              .map(
                (academy) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.sports_tennis),
                    title: Text(
                      academy.data()['name'] as String? ?? academy.id,
                    ),
                    subtitle: const Text('Ouvrir mon académie'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _Academy(academyId: academy.id),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    ),
  );
}

class _Academy extends StatelessWidget {
  const _Academy({required this.academyId});
  final String academyId;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Mon académie')),
    body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('academies')
          .doc(academyId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return const Center(
            child: Text('Votre accès à cette académie est indisponible.'),
          );
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final academy = snapshot.data!.data();
        if (academy == null)
          return const Center(child: Text('Académie introuvable.'));
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.sports_tennis, size: 80),
            const SizedBox(height: 24),
            Text(
              academy['name'] as String? ?? '',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 12),
            Text(academy['country'] as String? ?? ''),
            const SizedBox(height: 24),
            const Text('Bienvenue dans votre espace SportA.'),
          ],
        );
      },
    ),
  );
}
