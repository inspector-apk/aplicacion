import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/backend_config.dart';

class BancoPSE {
  final String codigo;
  final String nombre;
  const BancoPSE({required this.codigo, required this.nombre});

  factory BancoPSE.fromJson(Map<String, dynamic> json) => BancoPSE(
        codigo: json['codigo'] as String,
        nombre: json['nombre'] as String,
      );
}

class PagoPseException implements Exception {
  final String mensaje;
  PagoPseException(this.mensaje);
}

/// Pago real por PSE, procesado con Wompi (ver `backend/wompi.js` y el
/// README del backend). A diferencia del resto de la app, este SÍ mueve
/// dinero real cuando el backend está configurado con llaves de
/// producción; en sandbox es dinero simulado.
class PagoPseService {
  PagoPseService._();

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'x-api-key': BackendConfig.apiKey,
      };

  static Uri _uri(String path) => Uri.parse('${BackendConfig.baseUrl}$path');

  static Future<List<BancoPSE>> bancosDisponibles() async {
    final resp = await http
        .get(_uri('/api/pagos/bancos-pse'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    final cuerpo = jsonDecode(resp.body) as Map<String, dynamic>;
    if (cuerpo['ok'] != true) {
      throw PagoPseException(cuerpo['error'] as String? ?? 'No se pudo obtener la lista de bancos');
    }
    return (cuerpo['bancos'] as List)
        .map((b) => BancoPSE.fromJson(b as Map<String, dynamic>))
        .toList();
  }

  /// Crea la transacción y devuelve `(referencia, urlBanco)`: la
  /// referencia identifica el pago en nuestro backend, y la URL es a
  /// donde hay que mandar al cliente para que autentique con su banco.
  static Future<(String referencia, String urlBanco)> crearPago({
    required String clienteAlias,
    required int montoCentavos,
    required String correo,
    required String codigoBanco,
    required String tipoPersona, // 'natural' o 'juridica'
    required String tipoDocumento, // CC, CE, NIT, PP...
    required String numeroDocumento,
    String? descripcion,
  }) async {
    final resp = await http
        .post(
          _uri('/api/pagos/pse'),
          headers: _headers,
          body: jsonEncode({
            'clienteAlias': clienteAlias,
            'montoCentavos': montoCentavos,
            'correo': correo,
            'codigoBanco': codigoBanco,
            'tipoPersona': tipoPersona,
            'tipoDocumento': tipoDocumento,
            'numeroDocumento': numeroDocumento,
            'redirectUrl': '${BackendConfig.baseUrl}/pago-completado',
            'descripcion': descripcion,
          }),
        )
        .timeout(const Duration(seconds: 20));
    final cuerpo = jsonDecode(resp.body) as Map<String, dynamic>;
    if (cuerpo['ok'] != true) {
      throw PagoPseException(cuerpo['error'] as String? ?? 'No se pudo iniciar el pago');
    }
    return (cuerpo['referencia'] as String, cuerpo['urlBanco'] as String);
  }

  /// PENDING, APPROVED, DECLINED, VOIDED o ERROR.
  static Future<String> estadoDePago(String referencia) async {
    final resp = await http
        .get(_uri('/api/pagos/estado/$referencia'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    final cuerpo = jsonDecode(resp.body) as Map<String, dynamic>;
    if (cuerpo['ok'] != true) {
      throw PagoPseException(cuerpo['error'] as String? ?? 'No se pudo consultar el pago');
    }
    return cuerpo['estado'] as String;
  }
}
