import { lazy } from 'react'
const design = import.meta.env.VITE_DESIGN_PREVIEW !== 'false' && import.meta.env.MODE !== 'sporta'
const App = lazy(() => design ? import('../../academy-admin/src/design/DesignApp') : import('./App'))
export default function EntryApp() { return <App platform /> }
