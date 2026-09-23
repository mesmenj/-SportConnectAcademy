abstract final class AppAccessController {
  static bool guestAccessGranted = false;

  static void grantGuestAccess() {
    guestAccessGranted = true;
  }

  static void revokeGuestAccess() {
    guestAccessGranted = false;
  }
}
