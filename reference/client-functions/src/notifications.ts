import { createHash } from 'node:crypto';
import type { BookingEvent } from './notifications/outbox.js';

const sender = { name: 'SportA', email: 'info@sporta.example.invalid' };
const coachAppUrl = 'https://web.sporta.example.invalid/#/coach';
const logoUrl = 'https://admin.sporta.example.invalid/challengeme-academy-logo.jpg';
export const notificationConfig = {
  sender, coachAppUrl, userAppUrl: 'https://web.sporta.example.invalid/#/home',
  adminAppUrl: 'https://admin.sporta.example.invalid',
};

export type NotificationLanguage = 'en' | 'fr';

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, character => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[character]!);
}

export function invitationTemplate(name: string, actionUrl: string, locale: NotificationLanguage, audience: 'coach' | 'administrator' = 'coach') {
  const copy = locale === 'fr' ? {
    subject: 'Créez votre mot de passe SportA',
    heading: 'Bienvenue dans SportA',
    message: `Votre compte ${audience === 'coach' ? 'coach' : 'administrateur'} a été créé. Utilisez le bouton ci-dessous pour définir votre mot de passe. Ce lien personnel est temporaire et ne doit pas être partagé.`,
    button: 'Créer mon mot de passe',
    fallback: 'Si le bouton ne fonctionne pas, copiez ce lien dans votre navigateur :',
    ignore: 'Si vous n’attendiez pas cette invitation, vous pouvez ignorer cet e-mail.',
    contact: 'Besoin d’aide ? Contactez-nous à',
  } : {
    subject: 'Create your SportA password',
    heading: 'Welcome to SportA',
    message: `Your ${audience === 'coach' ? 'coach' : 'administrator'} account has been created. Use the button below to set your password. This personal link is temporary and must not be shared.`,
    button: 'Create my password',
    fallback: 'If the button does not work, copy this link into your browser:',
    ignore: 'If you were not expecting this invitation, you can safely ignore this email.',
    contact: 'Need help? Contact us at',
  };
  const safeName = escapeHtml(name);
  const safeUrl = escapeHtml(actionUrl);
  const html = `<!doctype html><html lang="${locale}"><body style="margin:0;background:#f4f6f5;font-family:Arial,sans-serif;color:#17241c"><table role="presentation" width="100%" cellspacing="0" cellpadding="0"><tr><td align="center" style="padding:32px 12px"><table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:600px;background:#fff;border-radius:16px;overflow:hidden"><tr><td align="center" style="padding:28px;background:#123d29"><img src="${logoUrl}" width="110" alt="SportA" style="display:block;border-radius:8px"></td></tr><tr><td style="padding:32px"><h1 style="font-size:25px;margin:0 0 20px">${copy.heading}</h1><p style="font-size:16px;line-height:1.6">${locale === 'fr' ? 'Bonjour' : 'Hello'} ${safeName},</p><p style="font-size:16px;line-height:1.6">${copy.message}</p><p style="text-align:center;margin:30px 0"><a href="${safeUrl}" style="display:inline-block;background:#123d29;color:#fff;text-decoration:none;font-weight:700;padding:14px 24px;border-radius:9px">${copy.button}</a></p><p style="font-size:13px;line-height:1.5;color:#59645e">${copy.fallback}<br><a href="${safeUrl}" style="color:#176b45;word-break:break-all">${safeUrl}</a></p><p style="font-size:13px;line-height:1.5;color:#59645e">${copy.ignore}</p></td></tr><tr><td style="padding:20px 32px;background:#edf3ef;font-size:13px;color:#59645e">${copy.contact} <a href="mailto:${sender.email}" style="color:#176b45">${sender.email}</a><br><a href="${coachAppUrl}" style="color:#176b45">SportA</a></td></tr></table></td></tr></table></body></html>`;
  const text = `${copy.heading}\n\n${locale === 'fr' ? 'Bonjour' : 'Hello'} ${name},\n\n${copy.message}\n\n${copy.button}: ${actionUrl}\n\n${copy.ignore}\n${copy.contact} ${sender.email}`;
  return { ...copy, html, text };
}

export function deliveryId(eventId: string, template: string, recipient: string): string {
  return createHash('sha256').update(`${eventId}|${template}|${recipient}`).digest('hex');
}

export function bookingTemplate(input: { recipientName: string; playerName: string; event: BookingEvent; startsAt: Date | null; locationName: string; coachName: string; actionUrl: string; locale: NotificationLanguage }) {
  const labels = input.locale === 'fr' ? {
    created: ['Nouvelle réservation SportA', 'Réservation reçue', 'La réservation a bien été enregistrée.'],
    confirmed: ['Réservation confirmée', 'Votre réservation est confirmée', 'La réservation a été confirmée.'],
    rejected: ['Réservation refusée', 'Mise à jour de votre réservation', 'La réservation n’a pas été acceptée.'],
    cancelled: ['Réservation annulée', 'Réservation annulée', 'La réservation a été annulée.'],
    reminder: ['Rappel de votre cours SportA', 'Rappel de votre cours', 'Votre cours approche. Retrouvez les détails de votre réservation ci-dessous.'],
    hello: 'Bonjour', player: 'Joueur', date: 'Date', court: 'Lieu', coach: 'Coach', button: 'Ouvrir l’application', contact: 'Besoin d’aide ? Contactez-nous à',
  } : {
    created: ['New SportA booking', 'Booking received', 'The booking has been successfully recorded.'],
    confirmed: ['Booking confirmed', 'Your booking is confirmed', 'The booking has been confirmed.'],
    rejected: ['Booking declined', 'Your booking update', 'The booking was not accepted.'],
    cancelled: ['Booking cancelled', 'Booking cancelled', 'The booking has been cancelled.'],
    reminder: ['Your SportA lesson reminder', 'Your upcoming lesson', 'Your lesson is coming up. Here are your booking details.'],
    hello: 'Hello', player: 'Player', date: 'Date', court: 'Location', coach: 'Coach', button: 'Open the application', contact: 'Need help? Contact us at',
  };
  const eventCopy = labels[input.event] as [string, string, string];
  const date = input.startsAt ? new Intl.DateTimeFormat(input.locale === 'fr' ? 'fr-FR' : 'en-GB', { dateStyle: 'full', timeStyle: 'short', timeZone: 'Asia/Dubai' }).format(input.startsAt) : '—';
  const details = `${labels.player}: ${input.playerName}\n${labels.date}: ${date}\n${labels.court}: ${input.locationName}\n${labels.coach}: ${input.coachName}`;
  const safeUrl = escapeHtml(input.actionUrl);
  const rows = [[labels.player, input.playerName], [labels.date, date], [labels.court, input.locationName], [labels.coach, input.coachName]]
    .map(([key, value]) => `<tr><td style="padding:7px 12px;color:#647069">${escapeHtml(key!)}</td><td style="padding:7px 12px;font-weight:700">${escapeHtml(value!)}</td></tr>`).join('');
  const html = `<!doctype html><html lang="${input.locale}"><body style="margin:0;background:#f4f6f5;font-family:Arial,sans-serif;color:#17241c"><table role="presentation" width="100%" cellspacing="0" cellpadding="0"><tr><td align="center" style="padding:32px 12px"><table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:600px;background:#fff;border-radius:16px;overflow:hidden"><tr><td align="center" style="padding:28px;background:#123d29"><img src="${logoUrl}" width="110" alt="SportA" style="display:block;border-radius:8px"></td></tr><tr><td style="padding:32px"><h1 style="font-size:25px;margin:0 0 20px">${eventCopy[1]}</h1><p style="font-size:16px;line-height:1.6">${labels.hello} ${escapeHtml(input.recipientName)},</p><p style="font-size:16px;line-height:1.6">${eventCopy[2]}</p><table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f4f6f5;border-radius:10px">${rows}</table><p style="text-align:center;margin:30px 0"><a href="${safeUrl}" style="display:inline-block;background:#123d29;color:#fff;text-decoration:none;font-weight:700;padding:14px 24px;border-radius:9px">${labels.button}</a></p></td></tr><tr><td style="padding:20px 32px;background:#edf3ef;font-size:13px;color:#59645e">${labels.contact} <a href="mailto:${sender.email}" style="color:#176b45">${sender.email}</a></td></tr></table></td></tr></table></body></html>`;
  return { subject: eventCopy[0], html, text: `${eventCopy[1]}\n\n${labels.hello} ${input.recipientName},\n\n${eventCopy[2]}\n\n${details}\n\n${labels.button}: ${input.actionUrl}\n\n${labels.contact} ${sender.email}` };
}
