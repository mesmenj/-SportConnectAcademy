import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  resolve: { dedupe: ['react', 'react-dom'] },
  build: {
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (id.includes('@firebase/firestore') || id.includes('firebase/firestore')) return 'firebase-firestore'
          if (id.includes('@firebase/auth') || id.includes('firebase/auth')) return 'firebase-auth'
          if (id.includes('@firebase/functions') || id.includes('firebase/functions')) return 'firebase-functions'
          if (id.includes('node_modules/firebase') || id.includes('node_modules/@firebase')) return 'firebase-core'
          if (id.includes('node_modules/@reduxjs') || id.includes('node_modules/react-redux') || id.includes('node_modules/redux-persist') || id.includes('node_modules/localforage')) return 'state'
          if (id.includes('node_modules/@mui') || id.includes('node_modules/@emotion')) return 'mui'
        },
      },
    },
  },
})
