/// Configuración del backend de verificación de correo (ver carpeta
/// `backend/` en la raíz del proyecto y su README con la guía de
/// despliegue). Edita estos dos valores después de desplegarlo en tu
/// servidor, con los mismos que hayas puesto en su archivo `.env`.
///
/// Es la única parte de Inspector que depende de internet y de un
/// servidor propio; el resto de la app sigue siendo 100% local.
class BackendConfig {
  BackendConfig._();

  static const String baseUrl = 'https://TU-DOMINIO-O-IP:3000';
  static const String apiKey = 'CAMBIA-ESTA-CLAVE-POR-LA-DE-TU-.env';
}
