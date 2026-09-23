import { combineReducers, configureStore, type Reducer } from '@reduxjs/toolkit'
import localforage from 'localforage'
import { FLUSH, PAUSE, PERSIST, PURGE, REGISTER, REHYDRATE, createTransform, persistReducer, persistStore } from 'redux-persist'
import authReducer, { type AuthState } from './authSlice'
import bookingsReducer from './bookingsSlice'
import uiReducer from './uiSlice'

const storage = localforage.createInstance({
  name: 'classcard-admin',
  storeName: 'redux_state',
  description: 'État local persistant de SportA Admin',
})

const rootReducer = combineReducers({ auth: authReducer, bookings: bookingsReducer, ui: uiReducer })
type RootReducerState = ReturnType<typeof rootReducer>
const sessionTransform = createTransform(
  inbound => {
    const state = inbound as AuthState
    return state.remember
      ? { ...state, initialized: false }
      : { user: null, isAuthenticated: false, remember: false, initialized: false }
  },
  outbound => outbound,
  { whitelist: ['auth'] },
)
const persistedReducer = persistReducer<RootReducerState>(
  { key: 'classcard-admin-v1', version: 1, storage, whitelist: ['auth', 'bookings'], transforms: [sessionTransform] },
  rootReducer as Reducer<RootReducerState>,
)

export const store = configureStore({
  reducer: persistedReducer,
  middleware: getDefaultMiddleware => getDefaultMiddleware({
    serializableCheck: { ignoredActions: [FLUSH, REHYDRATE, PAUSE, PERSIST, PURGE, REGISTER] },
  }),
  devTools: import.meta.env.DEV,
})

export const persistor = persistStore(store)
export type RootState = RootReducerState
export type AppStore = typeof store
export type AppDispatch = AppStore['dispatch']
