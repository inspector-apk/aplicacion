/// Credenciales SMTP para enviar el código de verificación de correo
/// directamente desde la app (sin backend ni servidor propio).
///
/// IMPORTANTE: esta contraseña queda dentro del APK/IPA compilado y es
/// extraíble por cualquiera que lo decompile. Usa una cuenta de Gmail
/// dedicada solo para esto, nunca una cuenta personal o crítica.
///
/// Cómo generarla: activa la verificación en 2 pasos en esa cuenta de
/// Gmail y genera una "contraseña de aplicación" en
/// https://myaccount.google.com/apppasswords
class SmtpConfig {
  SmtpConfig._();

  static const String gmailUser = 'CAMBIA-ESTO-POR-TU-CORREO@gmail.com';
  static const String gmailAppPassword =
      'CAMBIA-ESTO-POR-TU-CONTRASENA-DE-APLICACION';
}
