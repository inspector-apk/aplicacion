import 'dart:math';

import 'package:mailer/mailer.dart';
import 'package:mailer/smtp_server.dart';

import '../core/smtp_config.dart';

class EmailVerificationException implements Exception {
  final String mensaje;
  EmailVerificationException(this.mensaje);
  @override
  String toString() => mensaje;
}

class _CodigoPendiente {
  final String codigo;
  final DateTime expira;
  final DateTime ultimoEnvio;
  _CodigoPendiente({
    required this.codigo,
    required this.expira,
    required this.ultimoEnvio,
  });
}

/// Verificación de correo por código de 6 dígitos, enviado directamente
/// desde la app por SMTP de Gmail — sin backend ni servidor propio.
/// Requiere que el dispositivo del usuario tenga internet; los códigos
/// pendientes solo viven en memoria mientras dura el registro.
class EmailVerificationService {
  EmailVerificationService._();

  static const int _duracionCodigoMinutos = 10;
  static const int _reenvioMinSegundos = 30;

  static final Map<String, _CodigoPendiente> _pendientes = {};

  static Future<void> enviarCodigo(String correo) async {
    final correoNormalizado = correo.trim().toLowerCase();
    final ahora = DateTime.now();

    final pendiente = _pendientes[correoNormalizado];
    if (pendiente != null &&
        ahora.difference(pendiente.ultimoEnvio).inSeconds <
            _reenvioMinSegundos) {
      throw EmailVerificationException(
          'Espera unos segundos antes de reenviar el código.');
    }

    final codigo = _generarCodigo();
    _pendientes[correoNormalizado] = _CodigoPendiente(
      codigo: codigo,
      expira: ahora.add(const Duration(minutes: _duracionCodigoMinutos)),
      ultimoEnvio: ahora,
    );

    final smtpServer =
        gmail(SmtpConfig.gmailUser, SmtpConfig.gmailAppPassword);

    final mensaje = Message()
      ..from = Address(SmtpConfig.gmailUser, 'Inspector')
      ..recipients.add(correoNormalizado)
      ..subject = 'Tu código de verificación de Inspector'
      ..text = 'Tu código de verificación es: $codigo\n\n'
          'Expira en $_duracionCodigoMinutos minutos. Si no solicitaste '
          'este código, ignora este mensaje.'
      ..html = '''
        <div style="font-family: sans-serif; background:#000000; color:#F5F5F5; padding:24px;">
          <h2 style="color:#FFD700; margin-top:0;">Inspector</h2>
          <p>Tu código de verificación es:</p>
          <p style="font-size:28px; font-weight:bold; letter-spacing:6px; color:#FFD700;">$codigo</p>
          <p style="color:#A0A0A3; font-size:13px;">Expira en $_duracionCodigoMinutos minutos. Si no solicitaste este código, ignora este mensaje.</p>
        </div>
      ''';

    try {
      await send(mensaje, smtpServer);
    } on MailerException {
      // Un código ya quedó reservado arriba; lo liberamos para permitir
      // reintentar de inmediato en vez de esperar el enfriamiento.
      _pendientes.remove(correoNormalizado);
      throw EmailVerificationException(
          'No se pudo enviar el correo. Revisa tu conexión e inténtalo '
          'de nuevo.');
    } catch (_) {
      _pendientes.remove(correoNormalizado);
      throw EmailVerificationException(
          'No se pudo enviar el correo. Revisa tu conexión e inténtalo '
          'de nuevo.');
    }
  }

  static Future<void> verificarCodigo(String correo, String codigo) async {
    final correoNormalizado = correo.trim().toLowerCase();
    final codigoLimpio = codigo.trim();
    final pendiente = _pendientes[correoNormalizado];

    if (pendiente == null || DateTime.now().isAfter(pendiente.expira)) {
      throw EmailVerificationException(
          'El código expiró, solicita uno nuevo.');
    }
    if (pendiente.codigo != codigoLimpio) {
      throw EmailVerificationException('Código incorrecto.');
    }

    _pendientes.remove(correoNormalizado);
  }

  static String _generarCodigo() {
    final random = Random.secure();
    return List.generate(6, (_) => random.nextInt(10)).join();
  }
}
