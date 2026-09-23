import type { Item } from './fixtures';
export interface Field {
    key: string;
    label: string;
    type?: string;
    options?: string[];
    placeholder?: string;
    min?: number;
    max?: number;
    optional?: boolean;
}
const sports = ['Tennis', 'Padel'];
const currencies = ['FCFA', 'EUR', 'USD', 'AED', 'MAD'];
export function fieldsFor(page: string, data: Record<string, Item[]>): Field[] {
    const options = (key: string) => data[key].map(x => x.name);
    const amount: Field = { key: 'amount', label: 'Montant', type: 'number', min: 0 };
    const currency: Field = { key: 'currency', label: 'Devise', options: currencies };
    const email: Field = { key: 'email', label: 'Adresse e-mail', type: 'email' };
    switch (page) {
        case 'bookings': return [{ key: 'name', label: 'Joueur', options: options('players') }, { key: 'sport', label: 'Activité', options: sports }, { key: 'category', label: 'Formule', options: ['Cours privé', 'Cours semi-privé', 'Cours collectif'] }, { key: 'coach', label: 'Coach', options: options('coaches') }, { key: 'venue', label: 'Terrain', options: options('stadiums') }, { key: 'date', label: 'Date de la séance', type: 'date' }, { key: 'time', label: 'Heure de début', type: 'time' }, amount, currency];
        case 'players': return [{ key: 'name', label: 'Nom complet du joueur' }, { key: 'age', label: 'Âge', type: 'number', min: 3, max: 100 }, { key: 'gender', label: 'Genre', options: ['Fille', 'Garçon', 'Femme', 'Homme', 'Autre'] }, { key: 'parent', label: 'Parent ou responsable' }, email, { key: 'category', label: 'Niveau', options: ['Rouge · U8', 'Orange · U10', 'Vert · U12', 'Adulte'] }, { key: 'package', label: 'Nombre de séances', type: 'number', min: 1 }, { key: 'payment', label: 'Mode de règlement', options: ['Espèces', 'Virement', 'Carte', 'Lien de paiement'] }];
        case 'coaches': return [{ key: 'name', label: 'Nom complet du coach' }, email, { key: 'category', label: 'Spécialité', options: sports }, { key: 'detail', label: 'Expertise', placeholder: 'Initiation, compétition, préparation physique…' }];
        case 'sessions': return [{ key: 'name', label: 'Nom de la formule' }, { key: 'sport', label: 'Activité', options: sports }, { key: 'category', label: 'Type de séance', options: ['Cours privé', 'Cours semi-privé', 'Cours collectif'] }, amount, currency, { key: 'package', label: 'Nombre de séances', type: 'number', min: 1 }, { key: 'age', label: 'Âge minimum', type: 'number', min: 3 }, { key: 'maxAge', label: 'Âge maximum', type: 'number', min: 3, optional: true }];
        case 'communities': return [{ key: 'name', label: 'Nom du groupe' }, { key: 'category', label: 'Catégorie', options: ['U8', 'U10', 'U12', 'U14', 'Adulte'] }, { key: 'coach', label: 'Coach référent', options: options('coaches') }, { key: 'detail', label: 'Description', type: 'textarea' }];
        case 'stadiums': return [{ key: 'name', label: 'Nom du terrain' }, { key: 'detail', label: 'Adresse' }, { key: 'category', label: 'Surface', options: ['Terre battue', 'Surface dure', 'Gazon', 'Padel'] }, { key: 'courts', label: 'Nombre de courts', type: 'number', min: 1 }, { key: 'opening', label: 'Ouverture', type: 'time' }, { key: 'closing', label: 'Fermeture', type: 'time' }];
        case 'tournaments': return [{ key: 'name', label: 'Nom du tournoi' }, { key: 'venue', label: 'Lieu' }, { key: 'category', label: 'Catégorie', options: ['Rouge · U8', 'Orange · U10', 'Vert · U12', 'Adulte'] }, { key: 'date', label: 'Date de début', type: 'date' }, { key: 'capacity', label: 'Nombre de participants', type: 'number', min: 2 }, { key: 'description', label: 'Description', type: 'textarea' }];
        case 'invoices': return [{ key: 'name', label: 'Destinataire' }, { key: 'detail', label: 'Objet de la facture' }, { key: 'category', label: 'Mode de règlement', options: ['Espèces', 'Virement', 'Carte', 'Lien de paiement'] }, amount, currency];
        case 'team': return [{ key: 'name', label: 'Nom complet' }, email, { key: 'category', label: 'Rôle', options: ['Gestionnaire', 'Accueil', 'Coach'] }, { key: 'value', label: 'Accès', options: ['Opérations & joueurs', 'Réservations', 'Suivi sportif'] }];
        case 'academies': return [{ key: 'name', label: 'Nom de l’académie' }, { key: 'city', label: 'Ville' }, { key: 'country', label: 'Pays' }, { key: 'owner', label: 'Nom du propriétaire' }, email, { key: 'category', label: 'Forfait', options: ['Découverte', 'Essentiel', 'Performance'] }];
        default: return [];
    }
}
export function itemFromForm(page: string, form: FormData): Item {
    const f = Object.fromEntries(Array.from(form.entries(), ([k, v]) => [k, String(v)]));
    const date = f.date ? new Date(`${f.date}T12:00:00`).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' }) : '';
    let detail = f.detail || f.email || '', category = f.category || '', value = f.value || '';
    let status = 'Actif';
    switch (page) {
        case 'bookings':
            detail = `${date} · ${f.time}`;
            category = `${f.sport} · ${category}`;
            value = `${f.amount} ${f.currency}`;
            status = 'En attente';
            break;
        case 'players':
            detail = `${f.age} ans · ${f.parent}`;
            value = `0 / ${f.package} séances`;
            break;
        case 'coaches':
            value = '0 joueur · 0 séance';
            status = 'Invitation envoyée';
            break;
        case 'sessions':
            detail = `${f.sport} · Dès ${f.age} ans · ${f.package} séances`;
            value = `${f.amount} ${f.currency}`;
            break;
        case 'communities':
            value = `Coach ${f.coach}`;
            break;
        case 'stadiums':
            value = `${f.opening} – ${f.closing}`;
            status = 'Disponible';
            break;
        case 'tournaments':
            detail = `${date} · ${f.venue}`;
            value = `0 / ${f.capacity} participants`;
            status = 'Inscriptions ouvertes';
            break;
        case 'invoices':
            value = `${f.amount} ${f.currency}`;
            status = 'En attente';
            break;
        case 'team':
            status = 'Invitation envoyée';
            break;
        case 'academies':
            detail = `${f.city}, ${f.country}`;
            value = '0 joueur · 0 coach';
            status = 'Active';
            break;
    }
    return { id: crypto.randomUUID(), name: f.name, detail, category, status, value, metadata: f };
}
