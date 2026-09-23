import { lazy } from 'react'
const design = import.meta.env.VITE_DESIGN_PREVIEW !== 'false' && import.meta.env.MODE !== 'sporta'
const App = lazy(() => design ? import('./design/DesignApp') : import('./TenantApp'))
export default function EntryApp() { return <App /> }
