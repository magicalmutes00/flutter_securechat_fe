import 'package:flutter_test/flutter_test.dart';
import 'package:secure_chat/presentation/blocs/auth/auth_state.dart';

void main() {
  group('AuthState profile saving', () {
    test('defaults to not saving with no profile error', () {
      const state = AuthState(status: AuthStatus.authenticated);
      expect(state.isSavingProfile, isFalse);
      expect(state.profileErrorMessage, isNull);
    });

    test('profile work never touches the global status', () {
      const state = AuthState(status: AuthStatus.authenticated);
      final saving = state.copyWith(isSavingProfile: true);
      expect(saving.isSavingProfile, isTrue);
      expect(saving.status, AuthStatus.authenticated);
      final failed = saving.copyWith(
        isSavingProfile: false,
        profileErrorMessage: 'boom',
      );
      expect(failed.profileErrorMessage, 'boom');
      expect(failed.status, AuthStatus.authenticated);
    });

    test('clearProfileError drops the error and keeps everything else', () {
      const state = AuthState(
        status: AuthStatus.authenticated,
        profileErrorMessage: 'boom',
      );
      final cleared = state.copyWith(clearProfileError: true);
      expect(cleared.profileErrorMessage, isNull);
      expect(cleared.status, AuthStatus.authenticated);
      expect(state.copyWith().profileErrorMessage, 'boom');
    });
  });
}
