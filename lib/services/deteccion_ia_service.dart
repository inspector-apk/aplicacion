import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/backend_config.dart';

class DeteccionIAException implements Exception {
  final String mensaje;
  DeteccionIAException(this.mensaje);
  @override
  String toString() => mensaje;
}

/// Resultado del análisis de una foto antes de enviarla como respuesta.
class ResultadoDeteccionIA {
  final int iaPorcentaje;
  final int veracidadPorcentaje;
  const ResultadoDeteccionIA(
      {required this.iaPorcentaje, required this.veracidadPorcentaje});
}

/// Analiza si una foto parece generada por IA, usando el backend (ver
/// `backend/deteccion_ia.js`) para no exponer ninguna clave en la app.
class DeteccionIAService {
  DeteccionIAService._();

  static Future<ResultadoDeteccionIA> analizarImagen(
      String imagenBase64) async {
    final respuesta = await http
        .post(
          Uri.parse('${BackendConfig.baseUrl}/api/deteccion-ia'),
          headers: {
            'Content-Type': 'application/json',
            'x-api-key': BackendConfig.apiKey,
          },
          body: jsonEncode({'imagenBase64': imagenBase64}),
        )
        .timeout(const Duration(seconds: 25));

    final Map<String, dynamic> cuerpo;
    try {
      cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
    } catch (_) {
      throw DeteccionIAException('Respuesta inválida del servidor.');
    }
    if (cuerpo['ok'] != true) {
      throw DeteccionIAException(
          (cuerpo['error'] as String?) ?? 'No se pudo analizar la imagen.');
    }
    return ResultadoDeteccionIA(
      iaPorcentaje: cuerpo['iaPorcentaje'] as int,
      veracidadPorcentaje: cuerpo['veracidadPorcentaje'] as int,
    );
  }
}
