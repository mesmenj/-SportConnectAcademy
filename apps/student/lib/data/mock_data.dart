import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

class Session {
  const Session(
    this.day,
    this.time,
    this.title,
    this.coach,
    this.place,
    this.color,
  );
  final String day, time, title, coach, place;
  final Color color;
}

class Tournament {
  const Tournament(
    this.name,
    this.date,
    this.place,
    this.level,
    this.players,
    this.color,
  );
  final String name, date, place, level;
  final int players;
  final Color color;
}

class Conversation {
  const Conversation(
    this.name,
    this.initials,
    this.message,
    this.time,
    this.unread,
    this.color,
  );
  final String name, initials, message, time;
  final int unread;
  final Color color;
}

abstract final class MockData {
  static const sessions = [
    Session(
      'AUJ.',
      '17:30',
      'Perfectionnement',
      'Coach David',
      'Court central · Tennis Club Bonanjo',
      AppColors.sky,
    ),
    Session(
      'MER. 12',
      '16:00',
      'Jeu & Match',
      'Coach Émilie',
      'Court 2 · Académie Littoral',
      AppColors.green,
    ),
    Session(
      'SAM. 15',
      '09:30',
      'Préparation tournoi',
      'Coach David',
      'Court central · Tennis Club Bonanjo',
      AppColors.orange,
    ),
  ];
  static const tournaments = [
    Tournament(
      'Little Champions Cup',
      '22–23 AOÛT',
      'Tennis Club Bonanjo',
      'Orange · U10',
      32,
      AppColors.orange,
    ),
    Tournament(
      'Douala Junior Open',
      '05–07 SEPT.',
      'Club Noah',
      'Vert · U12',
      48,
      AppColors.sky,
    ),
    Tournament(
      'Future Stars Series',
      '19 SEPT.',
      'Académie Littoral',
      'Orange · U10',
      24,
      AppColors.lilac,
    ),
  ];
  static const conversations = [
    Conversation(
      'Coach David',
      'DK',
      'Lucas a fait une très belle séance aujourd’hui 🎾',
      '10:42',
      2,
      AppColors.blue,
    ),
    Conversation(
      'Tennis Club Bonanjo',
      'TC',
      'Votre réservation de samedi est confirmée.',
      'Hier',
      0,
      AppColors.green,
    ),
    Conversation(
      'Parents · Groupe U10',
      'U10',
      'Sophie : Je peux apporter les boissons !',
      'Lun.',
      5,
      AppColors.orange,
    ),
    Conversation(
      'Coach Émilie',
      'EM',
      'Voici les photos de l’entraînement 📸',
      'Dim.',
      0,
      AppColors.lilac,
    ),
  ];
  static const skills = {
    'Service': .72,
    'Coup droit': .84,
    'Revers': .65,
    'Volée': .58,
    'Déplacement': .78,
    'Concentration': .70,
  };
}
