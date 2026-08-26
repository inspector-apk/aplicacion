import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/backend_config.dart';
import '../core/bogota_localidades.dart';
import '../models/solicitud.dart';

class SolicitudException implements Exception {
  final String mensaje;
  SolicitudException(this.mensaje);
  @override
  String toString() => mensaje;
}

/// Las solicitudes viven en el backend compartido (ver `backend/`), no
/// en SQLite local: una solicitud creada por un Cliente en su
/// dispositivo tiene que poder verla un Colaborador en otro dispositivo
/// distinto, y eso requiere una base de datos compartida. Requiere
/// internet; sin conexión al backend, esta parte de la app no funciona.
class SolicitudService {
  SolicitudService._();

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'x-api-key': BackendConfig.apiKey,
      };

  static Uri _uri(String path, [Map<String, String>? query]) {
    return Uri.parse('${BackendConfig.baseUrl}$path')
        .replace(queryParameters: query);
  }

  static Future<Solicitud> crearSolicitud({
    required String clienteAlias,
    required TipoSolicitud tipo,
    required String descripcion,
    required String localidad,
  }) async {
    final centro = kLocalidadesBogota[localidad] ?? kBogotaCenter;

    final respuesta = await http
        .post(
          _uri('/api/solicitudes'),
          headers: _headers,
          body: jsonEncode({
            'clienteAlias': clienteAlias,
            'tipo': tipo.valor,
            'descripcion': descripcion.trim(),
            'localidad': localidad,
            'latitud': centro.latitude,
            'longitud': centro.longitude,
          }),
        )
        .timeout(const Duration(seconds: 15));

    final cuerpo = _decodificar(respuesta);
    if (cuerpo['ok'] != true) {
      throw SolicitudException(
          (cuerpo['error'] as String?) ?? 'No se pudo enviar la solicitud.');
    }
    return Solicitud.fromJson(cuerpo['solicitud'] as Map<String, dynamic>);
  }

  static Future<Solicitud?> solicitudActivaDeCliente(
      String clienteAlias) async {
    final respuesta = await http
        .get(
          _uri('/api/solicitudes/activa', {'clienteAlias': clienteAlias}),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 15));

    final cuerpo = _decodificar(respuesta);
    if (cuerpo['ok'] != true) {
      throw SolicitudException(
          (cuerpo['error'] as String?) ?? 'No se pudo consultar tu solicitud.');
    }
    final solicitud = cuerpo['solicitud'];
    if (solicitud == null) return null;
    return Solicitud.fromJson(solicitud as Map<String, dynamic>);
  }

  static Future<List<Solicitud>> solicitudesPendientes() async {
    final respuesta = await http
        .get(_uri('/api/solicitudes/pendientes'), headers: _headers)
        .timeout(const Duration(seconds: 15));

    final cuerpo = _decodificar(respuesta);
    if (cuerpo['ok'] != true) {
      throw SolicitudException(
          (cuerpo['error'] as String?) ?? 'No se pudieron cargar las solicitudes.');
    }
    return (cuerpo['solicitudes'] as List)
        .map((s) => Solicitud.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  static Future<List<Solicitud>> solicitudesEnCursoDeColaborador(
    String colaboradorAlias,
  ) async {
    final respuesta = await http
        .get(
          _uri('/api/solicitudes/en-curso', {'colaboradorAlias': colaboradorAlias}),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 15));

    final cuerpo = _decodificar(respuesta);
    if (cuerpo['ok'] != true) {
      throw SolicitudException(
          (cuerpo['error'] as String?) ?? 'No se pudieron cargar tus solicitudes.');
    }
    return (cuerpo['solicitudes'] as List)
        .map((s) => Solicitud.fromJson(s as Map<String, dynamic>))
        .toList();
  }

  static Future<void> aceptarSolicitud({
    required int solicitudId,
    required String colaboradorAlias,
  }) async {
    final respuesta = await http
        .post(
          _uri('/api/solicitudes/$solicitudId/aceptar'),
          headers: _headers,
          body: jsonEncode({'colaboradorAlias': colaboradorAlias}),
        )
        .timeout(const Duration(seconds: 15));

    final cuerpo = _decodificar(respuesta);
    if (cuerpo['ok'] != true) {
      throw SolicitudException((cuerpo['error'] as String?) ??
          'Esta solicitud ya no está disponible.');
    }
  }

  static Future<void> completarSolicitud({
    required int solicitudId,
    required String colaboradorAlias,
  }) async {
    final respuesta = await http
        .post(
          _uri('/api/solicitudes/$solicitudId/completar'),
          headers: _headers,
          body: jsonEncode({'colaboradorAlias': colaboradorAlias}),
        )
        .timeout(const Duration(seconds: 15));

    final cuerpo = _decodificar(respuesta);
    if (cuerpo['ok'] != true) {
      throw SolicitudException(
          (cuerpo['error'] as String?) ?? 'No se pudo completar la solicitud.');
    }
  }

  static Future<void> cancelarSolicitud({
    required int solicitudId,
    required String clienteAlias,
  }) async {
    final respuesta = await http
        .post(
          _uri('/api/solicitudes/$solicitudId/cancelar'),
          headers: _headers,
          body: jsonEncode({'clienteAlias': clienteAlias}),
        )
        .timeout(const Duration(seconds: 15));

    final cuerpo = _decodificar(respuesta);
    if (cuerpo['ok'] != true) {
      throw SolicitudException(
          (cuerpo['error'] as String?) ?? 'No se pudo cancelar la solicitud.');
    }
  }

  static Map<String, dynamic> _decodificar(http.Response respuesta) {
    try {
      return jsonDecode(respuesta.body) as Map<String, dynamic>;
    } catch (_) {
      return {'ok': false, 'error': 'Respuesta inválida del servidor.'};
    }
  }
}
