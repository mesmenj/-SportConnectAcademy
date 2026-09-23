import { createEntityAdapter, createSlice, type PayloadAction } from '@reduxjs/toolkit'
import type { Booking, BookingStatus } from '../data'
import type { RootState } from './store'

const bookingsAdapter = createEntityAdapter<Booking>({
  sortComparer: (a, b) => b.id.localeCompare(a.id),
})

const bookingsSlice = createSlice({
  name: 'bookings',
  initialState: bookingsAdapter.getInitialState(),
  reducers: {
    bookingAdded: bookingsAdapter.addOne,
    bookingsReceived: bookingsAdapter.setAll,
    bookingStatusChanged(state, action: PayloadAction<{ id: string; status: BookingStatus }>) {
      bookingsAdapter.updateOne(state, { id: action.payload.id, changes: { status: action.payload.status } })
    },
    bookingsReset: bookingsAdapter.removeAll,
  },
})

export const { bookingAdded, bookingsReceived, bookingStatusChanged, bookingsReset } = bookingsSlice.actions
export const bookingSelectors = bookingsAdapter.getSelectors<RootState>(state => state.bookings)
export default bookingsSlice.reducer
