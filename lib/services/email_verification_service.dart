import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/backend_config.dart';

class EmailVerificationException implements Exception {
  final String mensaje;
  EmailVerificationException(this.mensaje);
  @override
  String toString() => mensaje;
}

/// Verificación de correo por código de 6 dígitos, enviado por el
/// backend propio (carpeta `backend/`) vía SMTP de Gmail/Outlook.
/// Requiere conexión a internet — es la única parte de Inspector que
/// depende de un servidor externo.
class EmailVerificationService {
  EmailVerificationService._();

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'x-api-key': BackendConfig.apiKey,
      };

  static Future<void> enviarCodigo(String correo) async {
    final uri = Uri.parse('${BackendConfig.baseUrl}/api/enviar-codigo');
    final respuesta = await http
        .post(uri, headers: _headers, body: jsonEncode({'correo': correo}))
        .timeout(const Duration(seconds: 15));

    _lanzarSiHayError(respuesta, 'No se pudo enviar el código.');
  }

  static Future<void> verificarCodigo(String correo, String codigo) async {
    final uri = Uri.parse('${BackendConfig.baseUrl}/api/verificar-codigo');
    final respuesta = await http
        .post(
          uri,
          headers: _headers,
          body: jsonEncode({'correo': correo, 'codigo': codigo}),
        )
        .timeout(const Duration(seconds: 15));

    _lanzarSiHayError(respuesta, 'Código incorrecto.');
  }

  static void _lanzarSiHayError(http.Response respuesta, String mensajePorDefecto) {
    Map<String, dynamic>? cuerpo;
    try {
      cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
    } catch (_) {
      cuerpo = null;
    }

    final ok = cuerpo?['ok'] == true;
    if (respuesta.statusCode != 200 || !ok) {
      throw EmailVerificationException(
        (cuerpo?['error'] as String?) ?? mensajePorDefecto,
      );
    }
  }
}
