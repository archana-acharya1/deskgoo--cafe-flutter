// class AppConfig {
//   static const apiBase  = String.fromEnvironment(
//     'API_BASE',
//     defaultValue: 'http://192.168.1.85:3000/api/v1',
//   );
//   static const hostBase = String.fromEnvironment(
//     'HOST_BASE',
//     defaultValue: 'http://192.168.1.85:3000',
//   );
// }

class AppConfig {
  static const apiBase  = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://202.51.3.168:3000/api/v1',
  );
  static const hostBase = String.fromEnvironment(
    'HOST_BASE',
    defaultValue: 'http://202.51.3.168:3000',
  );
  static const socketBase = String.fromEnvironment(
    'SOCKET_BASE',
    defaultValue: 'http://202.51.3.168:3000'
  );
}
