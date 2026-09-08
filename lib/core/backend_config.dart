/// Configuración del backend compartido (ver carpeta `backend/` en la
/// raíz del proyecto y su README con la guía de despliegue). Edita
/// estos dos valores después de desplegarlo en tu servidor, con los
/// mismos que hayas puesto en su archivo `.env`.
///
/// Cuentas de usuario y solicitudes viven ahí (para que un Cliente y un
/// Colaborador en celulares distintos puedan verse entre sí, y para
/// poder crear/gestionar cuentas desde el panel de administrador web).
/// La verificación de correo y el 2FA siguen siendo cosas que la propia
/// app hace directamente (SMTP y TOTP locales), sin pasar por este
/// backend.
class BackendConfig {
  BackendConfig._();

  static const String baseUrl = 'http://appinspector.servialco.com:12443';

  /// Se inyecta en tiempo de compilación con
  /// `--dart-define=INSPECTOR_API_KEY=...` para no dejar la clave real
  /// en el código fuente (el repo es público). En CI viene de un
  /// GitHub Actions secret; en local, pásala a mano al compilar.
  static const String apiKey = String.fromEnvironment(
    'INSPECTOR_API_KEY',
    defaultValue: 'CAMBIA-ESTA-CLAVE-POR-LA-DE-TU-.env',
  );
}
