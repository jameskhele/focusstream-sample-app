import 'package:flutter/foundation.dart';
import '../api/dartstream.dart';
import '../api/firebase_auth.dart';

enum SessionStatus { signedOut, signingIn, signedIn, error }

class Session extends ChangeNotifier {
  SessionStatus status = SessionStatus.signedOut;
  String? email;
  String? userId;
  String? tenantId;
  String? errorMessage;
  DartstreamApi? api;

  Future<void> _authFlow(Future<FirebaseAuthResult> Function() authCall, String successMsg) async {
    status = SessionStatus.signingIn;
    errorMessage = null;
    notifyListeners();

    try {
      final auth = await authCall();
      final apiInstance = DartstreamApi(idToken: auth.idToken);
      final ids = await apiInstance.signup();

      debugPrint(successMsg);

      api = apiInstance;
      this.email = auth.email;
      userId = ids.userId;
      tenantId = ids.tenantId;
      status = SessionStatus.signedIn;
    } catch (e) {
      status = SessionStatus.error;
      errorMessage = _cleanError(e);
    }
    notifyListeners();
  }

  Future<void> signIn(String email, String password) =>
      _authFlow(() => FirebaseAuthRest.signIn(email, password), 'Session: Sign-in successful');

  Future<void> signUp(String email, String password) =>
      _authFlow(() => FirebaseAuthRest.signUp(email, password), 'Session: Sign-up successful');

  void signOut() {
    status = SessionStatus.signedOut;
    email = null;
    userId = null;
    tenantId = null;
    errorMessage = null;
    api = null;
    notifyListeners();
  }

  String _cleanError(Object e) {
    var str = e.toString();
    if (str.startsWith('DartstreamApiException: ')) {
      str = str.replaceFirst('DartstreamApiException: ', '');
    } else if (str.startsWith('DartstreamApiException(')) {
      final idx = str.indexOf('): ');
      if (idx != -1) {
        str = str.substring(idx + 3);
      }
    } else if (str.startsWith('Exception: ')) {
      str = str.replaceFirst('Exception: ', '');
    }
    return str;
  }
}
