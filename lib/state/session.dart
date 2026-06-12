import 'package:flutter/foundation.dart';
import 'package:dartstream_client/dartstream_client.dart';
import '../config.dart';

enum SessionStatus { signedOut, signingIn, signedIn, error }

class Session extends ChangeNotifier {
  SessionStatus status = SessionStatus.signedOut;
  String? email;
  String? userId;
  String? tenantId;
  String? errorMessage;
  DartStreamClient? client;
  DartStreamSession? sdkSession;

  Future<void> _authFlow(Future<DartStreamConnection> Function() authCall, String successMsg) async {
    status = SessionStatus.signingIn;
    errorMessage = null;
    notifyListeners();

    try {
      final connection = await authCall();
      debugPrint(successMsg);

      client = connection.client;
      sdkSession = connection.session;
      email = sdkSession!.email;
      userId = sdkSession!.userId;
      tenantId = sdkSession!.tenantId;
      status = SessionStatus.signedIn;
    } catch (e) {
      status = SessionStatus.error;
      errorMessage = _cleanError(e);
    }
    notifyListeners();
  }

  Future<void> signIn(String email, String password) =>
      _authFlow(
        () => DartStreamClient.signIn(
          config: DartStreamConfig.dev(firebaseApiKey: AppConfig.firebaseApiKey),
          email: email,
          password: password,
        ),
        'Session: Sign-in successful',
      );

  Future<void> signUp(String email, String password) =>
      _authFlow(
        () => DartStreamClient.signUp(
          config: DartStreamConfig.dev(firebaseApiKey: AppConfig.firebaseApiKey),
          email: email,
          password: password,
        ),
        'Session: Sign-up successful',
      );

  void signOut() {
    status = SessionStatus.signedOut;
    email = null;
    userId = null;
    tenantId = null;
    errorMessage = null;
    client = null;
    sdkSession = null;
    notifyListeners();
  }

  String _cleanError(Object e) {
    if (e is DartStreamFirebaseAuthException) {
      return e.message;
    }
    if (e is DartStreamApiException) {
      return e.body;
    }
    var str = e.toString();
    if (str.startsWith('Exception: ')) {
      str = str.replaceFirst('Exception: ', '');
    }
    return str;
  }
}
