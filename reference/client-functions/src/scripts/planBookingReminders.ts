import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { backfillBookingReminders } from '../notifications/reminders.js';

async function main() {
  const projectIndex = process.argv.indexOf('--project');
  const projectId = projectIndex >= 0 ? process.argv[projectIndex + 1] : undefined;
  if (!projectId || !/^[a-z][a-z0-9-]+$/.test(projectId)) throw new Error('Spécifiez explicitement --project <project-id>. Sans --apply, aucune écriture ne sera effectuée.');
  initializeApp({ projectId });
  const apply = process.argv.includes('--apply');
  const result = await backfillBookingReminders(getFirestore(), apply);
  console.info({ projectId, mode: apply ? 'apply' : 'dry-run', ...result });
}
main().catch(error => { console.error(error instanceof Error ? error.message : 'Reminder migration failed'); process.exitCode = 1; });
