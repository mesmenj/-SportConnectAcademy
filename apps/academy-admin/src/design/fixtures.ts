export type Item = {
    id: string;
    name: string;
    detail: string;
    category: string;
    status: string;
    value: string;
    initials?: string;
    metadata?: Record<string, string>;
};
export const initialData: Record<string, Item[]> = {
    bookings: [
        { id: 'b1', name: 'Lucas Martin', detail: 'Aujourd’hui · 17:30 – 18:30', category: 'Tennis · Cours privé', status: 'Confirmée', value: '15 000 FCFA' },
        { id: 'b2', name: 'Emma Ngono', detail: 'Aujourd’hui · 18:00 – 19:00', category: 'Tennis · Cours collectif', status: 'En attente', value: '8 000 FCFA' },
        { id: 'b3', name: 'Nathan Etoa', detail: 'Demain · 09:00 – 10:00', category: 'Padel · Initiation', status: 'Confirmée', value: '12 000 FCFA' },
        { id: 'b4', name: 'Chloé Mbappe', detail: 'Demain · 16:00 – 17:00', category: 'Tennis · Cours privé', status: 'Terminée', value: '15 000 FCFA' },
        { id: 'b5', name: 'Inès Fotso', detail: 'Samedi · 10:00 – 11:00', category: 'Tennis · Cours collectif', status: 'En attente', value: '8 000 FCFA' },
    ],
    players: [
        { id: 'p1', name: 'Lucas Martin', detail: '9 ans · Sophie Martin', category: 'Orange · U10', status: 'Actif', value: '8 / 12 séances' },
        { id: 'p2', name: 'Emma Ngono', detail: '11 ans · Paul Ngono', category: 'Vert · U12', status: 'Actif', value: '6 / 12 séances' },
        { id: 'p3', name: 'Nathan Etoa', detail: '8 ans · Marie Etoa', category: 'Rouge · U8', status: 'Actif', value: '3 / 8 séances' },
        { id: 'p4', name: 'Chloé Mbappe', detail: '10 ans · Anne Mbappe', category: 'Orange · U10', status: 'Actif', value: '10 / 12 séances' },
        { id: 'p5', name: 'Noah Bell', detail: '12 ans · Alex Bell', category: 'Vert · U12', status: 'En pause', value: '4 / 8 séances' },
        { id: 'p6', name: 'Inès Fotso', detail: '9 ans · Claire Fotso', category: 'Orange · U10', status: 'Actif', value: '5 / 12 séances' },
    ],
    coaches: [
        { id: 'c1', name: 'David Kengne', detail: 'Compétition U8 – U12', category: 'Tennis', status: 'Disponible', value: '18 joueurs · 42 séances' },
        { id: 'c2', name: 'Émilie Mballa', detail: 'Initiation & technique', category: 'Tennis', status: 'En séance', value: '15 joueurs · 36 séances' },
        { id: 'c3', name: 'Sarah Tchana', detail: 'Préparation physique', category: 'Multisport', status: 'Disponible', value: '12 joueurs · 29 séances' },
        { id: 'c4', name: 'Marc Essama', detail: 'Performance & stratégie', category: 'Padel', status: 'Disponible', value: '16 joueurs · 34 séances' },
    ],
    academies: [
        { id: 'a1', name: 'Tennis Club Bonanjo', detail: 'Douala, Cameroun', category: 'Performance', status: 'Active', value: '128 joueurs · 8 coachs' },
        { id: 'a2', name: 'Académie Littoral', detail: 'Douala, Cameroun', category: 'Essentiel', status: 'Active', value: '64 joueurs · 4 coachs' },
        { id: 'a3', name: 'Club Noah', detail: 'Yaoundé, Cameroun', category: 'Performance', status: 'À renouveler', value: '96 joueurs · 6 coachs' },
        { id: 'a4', name: 'Green Court Academy', detail: 'Kribi, Cameroun', category: 'Découverte', status: 'Active', value: '32 joueurs · 2 coachs' },
    ],
    stadiums: [
        { id: 's1', name: 'Court central', detail: 'Tennis Club Bonanjo · Extérieur', category: 'Terre battue', status: 'Disponible', value: '07:00 – 21:00' },
        { id: 's2', name: 'Court 2', detail: 'Tennis Club Bonanjo · Extérieur', category: 'Surface dure', status: 'Occupé', value: '07:00 – 21:00' },
        { id: 's3', name: 'Piste de padel', detail: 'Tennis Club Bonanjo · Couvert', category: 'Padel', status: 'Disponible', value: '08:00 – 22:00' },
    ],
    tournaments: [
        { id: 't1', name: 'Little Champions Cup', detail: '17 – 18 octobre · Bonanjo', category: 'Orange · U10', status: 'Inscriptions ouvertes', value: '26 / 32 participants' },
        { id: 't2', name: 'Douala Junior Open', detail: '07 – 08 novembre · Club Noah', category: 'Vert · U12', status: 'Inscriptions ouvertes', value: '38 / 48 participants' },
        { id: 't3', name: 'Future Stars Series', detail: '21 novembre · Littoral', category: 'Orange · U10', status: 'Complet', value: '24 / 24 participants' },
    ],
    sessions: [
        { id: 'sc1', name: 'Cours privé', detail: 'Tennis · Dès 6 ans · 60 min', category: '12 séances', status: 'Actif', value: '15 000 FCFA' },
        { id: 'sc2', name: 'Cours collectif', detail: 'Tennis · 8 à 12 ans · 60 min', category: '8 séances', status: 'Actif', value: '8 000 FCFA' },
        { id: 'sc3', name: 'Initiation padel', detail: 'Padel · Dès 12 ans · 90 min', category: '4 séances', status: 'Actif', value: '12 000 FCFA' },
    ],
    communities: [
        { id: 'g1', name: 'Les petits champions', detail: 'Initiation · Mercredi et samedi', category: 'U8 – U10', status: 'Actif', value: '12 joueurs' },
        { id: 'g2', name: 'Équipe compétition', detail: 'Perfectionnement · Mardi et jeudi', category: 'U12', status: 'Actif', value: '8 joueurs' },
    ],
    invoices: [
        { id: 'INV-001', name: 'Sophie Martin', detail: 'Forfait Lucas · 12 séances', category: 'Espèces', status: 'Réglée', value: '180 000 FCFA' },
        { id: 'INV-002', name: 'Paul Ngono', detail: 'Forfait Emma · 8 séances', category: 'Virement', status: 'En attente', value: '64 000 FCFA' },
        { id: 'INV-003', name: 'Marie Etoa', detail: 'Forfait Nathan · 4 séances', category: 'Espèces', status: 'Réglée', value: '48 000 FCFA' },
    ],
    team: [
        { id: 'u1', name: 'Alex Morgan', detail: 'alex@example.test', category: 'Propriétaire', status: 'Actif', value: 'Accès complet' },
        { id: 'u2', name: 'Marie Kamga', detail: 'marie@example.test', category: 'Gestionnaire', status: 'Actif', value: 'Opérations & joueurs' },
        { id: 'u3', name: 'Paul Nana', detail: 'paul@example.test', category: 'Accueil', status: 'Invitation envoyée', value: 'Réservations' },
    ],
    audit: [
        { id: 'l1', name: 'Académie créée', detail: 'Aujourd’hui · 10:42', category: 'Green Court Academy', status: 'Effectué', value: 'Alex Morgan' },
        { id: 'l2', name: 'Abonnement renouvelé', detail: 'Aujourd’hui · 09:15', category: 'Tennis Club Bonanjo', status: 'Effectué', value: 'Alex Morgan' },
        { id: 'l3', name: 'Invitation envoyée', detail: 'Hier · 16:30', category: 'Académie Littoral', status: 'Effectué', value: 'Marie Kamga' },
    ],
};
export const navigation = [
    { id: 'overview', label: 'Vue d’ensemble', icon: 'grid' }, { id: 'bookings', label: 'Réservations', icon: 'calendar' },
    { id: 'players', label: 'Joueurs & familles', icon: 'users' }, { id: 'coaches', label: 'Coachs', icon: 'whistle' },
    { id: 'sessions', label: 'Séances & tarifs', icon: 'sliders' }, { id: 'communities', label: 'Groupes & cours', icon: 'layers' },
    { id: 'stadiums', label: 'Terrains', icon: 'court' }, { id: 'tournaments', label: 'Tournois', icon: 'trophy' },
    { id: 'invoices', label: 'Factures & paiements', icon: 'receipt' }, { id: 'messages', label: 'Communication', icon: 'chat' },
    { id: 'team', label: 'Équipe & accès', icon: 'shield' }, { id: 'profile', label: 'Paramètres', icon: 'settings' },
];
export const platformNavigation = [
    { id: 'overview', label: 'Vue d’ensemble', icon: 'grid' }, { id: 'academies', label: 'Académies', icon: 'court' },
    { id: 'subscriptions', label: 'Abonnements', icon: 'layers' }, { id: 'plans', label: 'Forfaits', icon: 'receipt' },
    { id: 'team', label: 'Équipe & accès', icon: 'users' }, { id: 'audit', label: 'Journal d’activité', icon: 'clock' },
    { id: 'profile', label: 'Paramètres', icon: 'settings' },
];
