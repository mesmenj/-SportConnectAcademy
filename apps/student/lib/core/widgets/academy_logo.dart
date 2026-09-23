import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class AcademyLogo extends StatelessWidget {
  const AcademyLogo({super.key, this.academyId, this.size = 48});

  final String? academyId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final id = academyId;
    if (id == null || id.isEmpty) return _LogoImage(size: size);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('academies')
          .doc(id)
          .snapshots(),
      builder: (_, snapshot) => _LogoImage(
        size: size,
        url: snapshot.data?.data()?['logoUrl']?.toString(),
      ),
    );
  }
}

class _LogoImage extends StatelessWidget {
  const _LogoImage({required this.size, this.url});

  final double size;
  final String? url;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size * .22),
    child: url == null || url!.isEmpty
        ? Image.asset(
            'assets/images/challengeme-academy-logo.jpg',
            width: size,
            height: size,
            fit: BoxFit.contain,
          )
        : Image.network(
            url!,
            width: size,
            height: size,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Image.asset(
              'assets/images/challengeme-academy-logo.jpg',
              width: size,
              height: size,
              fit: BoxFit.contain,
            ),
          ),
  );
}
