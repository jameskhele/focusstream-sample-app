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

  Future<void> signIn(String email, String password) async {
    status = SessionStatus.signingIn;
    errorMessage = null;
    notifyListeners();

    try {
      final auth = await FirebaseAuthRest.signIn(email, password);
      final apiInstance = DartstreamApi(idToken: auth.idToken);
      final ids = await apiInstance.signup();

      debugPrint('======================');
      debugPrint('LOGIN SUCCESS');
      debugPrint('EMAIL: ${auth.email}');
      debugPrint('USER ID: ${ids.userId}');
      debugPrint('TENANT ID: ${ids.tenantId}');
      debugPrint('======================');

      api = apiInstance;
      this.email = auth.email;
      userId = ids.userId;
      tenantId = ids.tenantId;
      status = SessionStatus.signedIn;
    } catch (e) {
      status = SessionStatus.error;
      errorMessage = e.toString();
    }
    notifyListeners();
  }

  Future<void> signUp(String email, String password) async {
    status = SessionStatus.signingIn;
    errorMessage = null;
    notifyListeners();

    try {
      final auth = await FirebaseAuthRest.signUp(email, password);
      final apiInstance = DartstreamApi(idToken: auth.idToken);
      final ids = await apiInstance.signup();

      debugPrint('======================');
      debugPrint('ACCOUNT CREATED');
      debugPrint('EMAIL: ${auth.email}');
      debugPrint('USER ID: ${ids.userId}');
      debugPrint('TENANT ID: ${ids.tenantId}');
      debugPrint('======================');

      api = apiInstance;
      this.email = auth.email;
      userId = ids.userId;
      tenantId = ids.tenantId;
      status = SessionStatus.signedIn;
    } catch (e) {
      status = SessionStatus.error;
      errorMessage = e.toString();
    }
    notifyListeners();
  }

  void signOut() {
    status = SessionStatus.signedOut;
    email = null;
    userId = null;
    tenantId = null;
    errorMessage = null;
    api = null;
    notifyListeners();
  }
}
