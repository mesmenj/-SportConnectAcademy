import { getFunctions, httpsCallable } from 'firebase/functions'
import { firebaseApp } from '../firebase'

const functions = getFunctions(firebaseApp, 'europe-west1')

export type AdminRole = 'admin' | 'academy_manager' | 'booking_manager'
export interface AdministratorInput { email: string; displayName: string; role: AdminRole; academyIds: string[] }
export interface AdministratorAccessInput { uid: string; role: AdminRole; status: 'active' | 'suspended'; academyIds: string[] }

export const createAdministrator = (input: AdministratorInput) => httpsCallable<AdministratorInput, { uid: string; email: string } & CoachInvitationResult>(functions, 'createAdministrator')(input)
export const updateAdministratorAccess = (input: AdministratorAccessInput) => httpsCallable<AdministratorAccessInput>(functions, 'updateAdministratorAccess')(input)
export const createAcademy = (input: { name: string; city: string; country: string }) => httpsCallable(functions, 'createAcademy')(input)
export const updateAcademyBranding = (input: { academyId: string; logoDataUrl: string }) => httpsCallable<typeof input, { academyId: string; logoUrl: string }>(functions, 'updateAcademyBranding')(input)
export const updateValidatedRevenue = (input: { amount: number; currency: SessionCurrency }) => httpsCallable<typeof input, { amount: number; currency: SessionCurrency }>(functions, 'updateValidatedRevenue')(input)
export const createStadium = (input: { academyId: string; name: string; address: string; courtCount: number }) => httpsCallable(functions, 'createStadium')(input)
export interface CoachInvitationResult { resetLink: string; emailStatus: 'queued' | 'sent' | 'failed'; emailDeliveryId: string; emailEventId?: string }
export const createCoach = (input: { academyId: string; displayName: string; email: string; specialties: string[] }) => httpsCallable<typeof input, { id: string } & CoachInvitationResult>(functions, 'createCoach')(input)
export const resendCoachPasswordLink = (coachId: string) => httpsCallable<{ coachId: string }, { coachId: string; email: string } & CoachInvitationResult>(functions, 'resendCoachPasswordLink')({ coachId })
export const deleteCoach = (coachId: string) => httpsCallable<{ coachId: string }, { coachId: string; deleted: true }>(functions, 'deleteCoach')({ coachId })
export interface TournamentInput { academyId: string | null; name: string; venue: string; category: string; description: string; startsAt: string; capacity: number; imageDataUrl: string | null }
export const createTournament = (input: TournamentInput) => httpsCallable<TournamentInput, { id: string; name: string; imageUrl: string | null; status: 'open' }>(functions, 'createTournament')(input)
export type UpdateTournamentInput = TournamentInput & { tournamentId: string }
export const updateTournament = (input: UpdateTournamentInput) => httpsCallable<UpdateTournamentInput, { tournamentId: string; updated: true; imageUrl: string | null }>(functions, 'updateTournament')(input)
export const softDeleteTournament = (tournamentId: string) => httpsCallable<{ tournamentId: string }, { tournamentId: string; isDelete: true }>(functions, 'softDeleteTournament')({ tournamentId })
export const updateMyProfile = (input: { displayName: string; phone: string; preferredLanguage: 'fr' | 'en' }) => httpsCallable(functions, 'updateMyProfile')(input)
export type SessionConfigurationType = 'private' | 'semi_private' | 'group'
export type SessionActivityType = 'tennis' | 'padel'
export type SessionCurrency = 'AED' | 'XAF' | 'EUR' | 'USD' | 'MAD'
export interface SessionConfigurationInput { academyId: string; activityType: SessionActivityType; type: SessionConfigurationType; price: number; sessionCount: number; minAge: number; maxAge: number | null; currency: SessionCurrency }
export const updateSessionConfiguration = (input: SessionConfigurationInput) => httpsCallable<SessionConfigurationInput>(functions, 'updateSessionConfiguration')(input)
export const deleteSessionConfiguration = (configurationId: string) => httpsCallable<{ configurationId: string }>(functions, 'deleteSessionConfiguration')({ configurationId })
export interface CreateSessionInput { configurationId: string; coachId: string; stadiumId: string | null; courtNumber: number | null; capacity: number; startsAt: string; endsAt: string }
export interface CreatedSession { id: string; academyId: string; status: 'open' }
export const createSession = (input: CreateSessionInput) => httpsCallable<CreateSessionInput, CreatedSession>(functions, 'createSession')(input)
export interface PlayerCreationConfiguration { id: string; activityType: SessionActivityType; type: SessionConfigurationType; minAge: number; maximumAge: number | null; price: number; currency: SessionCurrency; sessionCount: number; padelSlotTemplateId?: string | null; dayOfWeek?: number | null; startTime?: string | null; durationMinutes?: number | null }
export const getPlayerCreationOptions = () => httpsCallable<void, { configurations: PlayerCreationConfiguration[] }>(functions, 'getPlayerCreationOptions')()
export interface PadelSlotTemplateInput { templateId?: string; academyId: string; durationMinutes: number; price: number; currency: SessionCurrency }
export const upsertPadelSlotTemplate = (input: PadelSlotTemplateInput) => httpsCallable<PadelSlotTemplateInput>(functions, 'upsertPadelSlotTemplate')(input)
export const deletePadelSlotTemplate = (templateId: string) => httpsCallable<{ templateId: string }>(functions, 'deletePadelSlotTemplate')({ templateId })
export const createCommunity = (input: { academyId: string; name: string; description: string }) => httpsCallable<typeof input>(functions, 'createCommunity')(input)
export interface UpdateCommunityInput { communityId: string; name: string; description: string; active: boolean }
export const updateCommunity = (input: UpdateCommunityInput) => httpsCallable<UpdateCommunityInput>(functions, 'updateCommunity')(input)
export const createCommunityCourse = (input: { communityId: string; name: string; description: string }) => httpsCallable<typeof input>(functions, 'createCommunityCourse')(input)
export const updateCommunityCourse = (input: { courseId: string; name: string; description: string }) => httpsCallable<typeof input>(functions, 'updateCommunityCourse')(input)
export const softDeleteCommunity = (communityId: string) => httpsCallable<{ communityId: string }>(functions, 'softDeleteCommunity')({ communityId })
export const softDeleteCommunityCourse = (courseId: string) => httpsCallable<{ courseId: string }>(functions, 'softDeleteCommunityCourse')({ courseId })
export const assignPlayerCommunity = (input: { playerId: string; communityId: string | null }) => httpsCallable<typeof input>(functions, 'assignPlayerCommunity')(input)
export const confirmCashPlayerPayment = (playerId: string) => httpsCallable<{ playerId: string }>(functions, 'confirmCashPlayerPayment')({ playerId })
export const adjustPlayerSessionQuota = (input: { playerId: string; delta: -1 | 1 }) => httpsCallable<typeof input, { playerId: string; remainingSessions: number; totalSessions: number }>(functions, 'adjustPlayerSessionQuota')(input)
export const updatePlayerPackage = (input: { playerId: string; sessionCount: number }) => httpsCallable<typeof input, { playerId: string; sessionCount: number; remainingSessions: number; packageDelta: number }>(functions, 'updatePlayerPackage')(input)
export const softDeletePlayer = (playerId: string) => httpsCallable<{ playerId: string }, { playerId: string; isDelete: true }>(functions, 'softDeletePlayer')({ playerId })
export interface AdminPlayerInput { firstName: string; lastName: string; age: number; gender: 'female' | 'male' | 'woman' | 'man' | 'other'; sessionConfigurationId: string; paymentMethod: 'cash' | 'card' | 'payment_link' | 'bank_transfer'; userId: string | null }
export const createPlayerForUser = (input: AdminPlayerInput) => httpsCallable<AdminPlayerInput>(functions, 'createPlayerForUser')(input)
export const assignPlayerToUser = (input: { playerId: string; userId: string }) => httpsCallable<typeof input>(functions, 'assignPlayerToUser')(input)

export interface NotificationDelivery {
  id: string; eventId: string | null; bookingId: string | null;
  recipient: { email: string | null; name: string } | null; template: string;
  status: string; attempts: number; lastError: string | null;
  providerMessageId: string | null; retryable: boolean; createdAt: number; updatedAt: number;
}
export const listNotificationDeliveries = (input: { academyId?: string; beforeId?: string }) => httpsCallable<typeof input, { deliveries: NotificationDelivery[]; nextCursor: string | null }>(functions, 'listNotificationDeliveries')(input)
export const retryNotificationDelivery = (deliveryId: string) => httpsCallable(functions, 'retryNotificationDelivery')({ deliveryId })
