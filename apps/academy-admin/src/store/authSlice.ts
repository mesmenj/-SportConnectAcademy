import { createSlice, type PayloadAction } from '@reduxjs/toolkit'

export interface AdminUser {
  uid: string
  email: string
  name: string
  initials: string
  role: 'root' | 'admin' | 'academy_manager' | 'booking_manager'
  academyIds: string[]
  permissions: string[]
  phone?: string
  preferredLanguage?: 'fr' | 'en'
}

export interface AuthState {
  user: AdminUser | null
  isAuthenticated: boolean
  remember: boolean
  initialized: boolean
}

const initialState: AuthState = { user: null, isAuthenticated: false, remember: false, initialized: false }

const authSlice = createSlice({
  name: 'auth',
  initialState,
  reducers: {
    loginSucceeded(state, action: PayloadAction<{ user: AdminUser; remember: boolean }>) {
      state.user = action.payload.user
      state.isAuthenticated = true
      state.remember = action.payload.remember
      state.initialized = true
    },
    firebaseSessionResolved(state, action: PayloadAction<AdminUser | null>) {
      state.user = action.payload
      state.isAuthenticated = Boolean(action.payload)
      state.initialized = true
    },
    loggedOut(state) {
      state.user = null
      state.isAuthenticated = false
      state.remember = false
      state.initialized = true
    },
  },
})

export const { loginSucceeded, firebaseSessionResolved, loggedOut } = authSlice.actions
export default authSlice.reducer
