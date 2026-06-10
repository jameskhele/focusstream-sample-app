/// Hosts and Firebase configuration for the FocusStream sample application.
class AppConfig {
  static const firebaseApiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: 'AIzaSyAtJLCMoEtw3lFUNa4agcuaKA9kSkXOuaA',
  );

  static bool get hasFirebaseApiKey => firebaseApiKey.isNotEmpty;

  static const authHost = 'https://dev-apiauth.dartstream.io';
  static const platformHost = 'https://dev-apiplatform.dartstream.io';
  static const experienceHost = 'https://dev-apiexperience.dartstream.io';
  static const reactiveHost = 'https://dev-apireactive.dartstream.io';
  static const persistenceHost = 'https://dev-apipersistence.dartstream.io';
}
