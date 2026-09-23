import { createSlice, type PayloadAction } from '@reduxjs/toolkit'

export type Page = 'dashboard' | 'bookings' | 'sessionSettings' | 'players' | 'coaches' | 'academies' | 'stadiums' | 'tournaments' | 'messages' | 'administration' | 'profile'

interface UiState {
  page: Page
  createBookingOpen: boolean
  toast: string
}

const initialState: UiState = { page: 'dashboard', createBookingOpen: false, toast: '' }

const uiSlice = createSlice({
  name: 'ui',
  initialState,
  reducers: {
    pageChanged(state, action: PayloadAction<Page>) { state.page = action.payload },
    bookingDialogOpened(state) { state.createBookingOpen = true },
    bookingDialogClosed(state) { state.createBookingOpen = false },
    toastShown(state, action: PayloadAction<string>) { state.toast = action.payload },
    toastClosed(state) { state.toast = '' },
    uiReset: () => initialState,
  },
})

export const { pageChanged, bookingDialogOpened, bookingDialogClosed, toastShown, toastClosed, uiReset } = uiSlice.actions
export default uiSlice.reducer
