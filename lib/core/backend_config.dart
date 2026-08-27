/// Configuración del backend compartido de solicitudes (ver carpeta
/// `backend/` en la raíz del proyecto y su README con la guía de
/// despliegue). Edita estos dos valores después de desplegarlo en tu
/// servidor, con los mismos que hayas puesto en su archivo `.env`.
///
/// Es necesario porque una solicitud creada por un Cliente en su
/// celular tiene que poder verla un Colaborador en otro celular
/// distinto — eso requiere una base de datos compartida, no solo local.
/// El resto de Inspector (usuarios, 2FA, verificación de correo) sigue
/// siendo 100% local por dispositivo.
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
