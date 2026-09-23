import { StrictMode, Suspense } from 'react'
import { createRoot } from 'react-dom/client'
import EntryApp from './EntryApp'
createRoot(document.getElementById('root')!).render(<StrictMode><Suspense fallback={<p>Chargement de SportA…</p>}><EntryApp /></Suspense></StrictMode>)
