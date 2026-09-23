import { initializeApp } from 'firebase/app'
import { connectAuthEmulator, getAuth } from 'firebase/auth'
import { connectFirestoreEmulator, getFirestore } from 'firebase/firestore'
import { connectFunctionsEmulator, getFunctions } from 'firebase/functions'
import { initializeAppCheck, ReCaptchaV3Provider } from 'firebase/app-check'
const env = import.meta.env
const emulators = env.VITE_USE_EMULATORS === 'true'
const projectId = env.VITE_FIREBASE_PROJECT_ID || (emulators ? 'demo-sporta' : '')
if (!projectId || projectId === 'classcard-79419') throw new Error('Configurer un projet Firebase SportA indépendant.')
if (emulators && !projectId.startsWith('demo-')) throw new Error('Les émulateurs exigent un projet demo- pour éviter tout accès réel.')
const app = initializeApp({ projectId, apiKey: env.VITE_FIREBASE_API_KEY || 'demo-key', appId: env.VITE_FIREBASE_APP_ID || 'demo-app', authDomain: env.VITE_FIREBASE_AUTH_DOMAIN, storageBucket: env.VITE_FIREBASE_STORAGE_BUCKET, messagingSenderId: env.VITE_FIREBASE_MESSAGING_SENDER_ID })
export const auth = getAuth(app)
export const db = getFirestore(app)
export const functions = getFunctions(app, 'europe-west1')
if (emulators) {
  connectAuthEmulator(auth, 'http://127.0.0.1:9099', { disableWarnings: true })
  connectFirestoreEmulator(db, '127.0.0.1', 8080)
  connectFunctionsEmulator(functions, '127.0.0.1', 5001)
} else {
  if (!env.VITE_APPCHECK_SITE_KEY) throw new Error('Clé App Check requise en production.')
  initializeAppCheck(app, { provider: new ReCaptchaV3Provider(env.VITE_APPCHECK_SITE_KEY), isTokenAutoRefreshEnabled: true })
}
