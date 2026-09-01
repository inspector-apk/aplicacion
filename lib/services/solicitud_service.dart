import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/backend_config.dart';
import '../core/bogota_localidades.dart';
import '../core/precios.dart';
import '../models/solicitud.dart';

class SolicitudException implements Exception {
  final String mensaje;
  SolicitudException(this.mensaje);
  @override
  String toString() => mensaje;
}

/// Contenido de una respuesta, obtenido una única vez. No se guarda en
/// ningún archivo ni base de datos local — vive solo en memoria
/// mientras la pantalla que la muestra está abierta. Puede traer varios
/// campos a la vez si la solicitud pedía varios tipos (ej. texto + foto).
class RespuestaSolicitud {
  final String? texto;
  final String? imagenBase64;
  final String? audioBase64;
  final String? videoBase64;

  const RespuestaSolicitud({
    this.texto,
    this.imagenBase64,
    this.audioBase64,
    this.videoBase64,
  });

  factory RespuestaSolicitud.fromJson(Map<String, dynamic> json) {
    return RespuestaSolicitud(
      texto: json['texto'] as String?,
      imagenBase64: json['imagenBase64'] as String?,
      audioBase64: json['audioBase64'] as String?,
      videoBase64: json['videoBase64'] as String?,
    );
  }
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
    required List<TipoSolicitud> tipos,
    required Categoria categoria,
    required String descripcion,
    required String localidad,
    required String direccion,
  }) async {
    final centro = kLocalidadesBogota[localidad] ?? kBogotaCenter;
    final valorTotal = calcularValorTotal(categoria, tipos);

    final respuesta = await http
        .post(
          _uri('/api/solicitudes'),
          headers: _headers,
          body: jsonEncode({
            'clienteAlias': clienteAlias,
            'tipos': tipos.map((t) => t.valor).toList(),
            'categoria': categoria.valor,
            'valorTotal': valorTotal,
            'descripcion': descripcion.trim(),
            'localidad': localidad,
            'direccion': direccion.trim(),
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

  /// El colaborador envía su respuesta y con eso mismo queda completada
  /// la solicitud. Debe incluir contenido para cada tipo que se pidió
  /// (ej. si la solicitud pedía texto + audio, hay que mandar ambos).
  /// El timeout es más largo porque puede incluir audio/video en base64.
  static Future<void> responderSolicitud({
    required int solicitudId,
    required String colaboradorAlias,
    String? texto,
    String? imagenBase64,
    String? audioBase64,
    String? videoBase64,
  }) async {
    final respuesta = await http
        .post(
          _uri('/api/solicitudes/$solicitudId/responder'),
          headers: _headers,
          body: jsonEncode({
            'colaboradorAlias': colaboradorAlias,
            if (texto != null) 'texto': texto,
            if (imagenBase64 != null) 'imagenBase64': imagenBase64,
            if (audioBase64 != null) 'audioBase64': audioBase64,
            if (videoBase64 != null) 'videoBase64': videoBase64,
          }),
        )
        .timeout(const Duration(seconds: 90));

    final cuerpo = _decodificar(respuesta);
    if (cuerpo['ok'] != true) {
      throw SolicitudException(
          (cuerpo['error'] as String?) ?? 'No se pudo enviar la respuesta.');
    }
  }

  /// Obtiene el contenido de la respuesta UNA SOLA VEZ: el backend la
  /// borra de su base de datos en el mismo momento en que se entrega
  /// aquí. Nunca se guarda en el dispositivo — solo vive en memoria
  /// mientras la pantalla que la muestra está abierta.
  static Future<RespuestaSolicitud> verRespuesta({
    required int solicitudId,
    required String clienteAlias,
  }) async {
    final respuesta = await http
        .get(
          _uri('/api/solicitudes/$solicitudId/respuesta',
              {'clienteAlias': clienteAlias}),
          headers: _headers,
        )
        .timeout(const Duration(seconds: 60));

    final cuerpo = _decodificar(respuesta);
    if (cuerpo['ok'] != true) {
      throw SolicitudException((cuerpo['error'] as String?) ??
          'Esta respuesta ya fue vista o no existe.');
    }
    return RespuestaSolicitud.fromJson(
        cuerpo['respuesta'] as Map<String, dynamic>);
  }

  /// Historial completo (cualquier estado) del cliente. Nunca incluye
  /// el contenido de las respuestas, solo metadatos.
  static Future<List<Solicitud>> historialDeCliente(
      String clienteAlias) async {
    final respuesta = await http
        .get(_uri('/api/solicitudes/historial', {'clienteAlias': clienteAlias}),
            headers: _headers)
        .timeout(const Duration(seconds: 15));

    final cuerpo = _decodificar(respuesta);
    if (cuerpo['ok'] != true) {
      throw SolicitudException(
          (cuerpo['error'] as String?) ?? 'No se pudo cargar el historial.');
    }
    return (cuerpo['solicitudes'] as List)
        .map((s) => Solicitud.fromJson(s as Map<String, dynamic>))
        .toList();
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
