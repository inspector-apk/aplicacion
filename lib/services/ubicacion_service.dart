import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/backend_config.dart';

/// Posición aproximada de un colaborador disponible, para pintarlo en
/// el mapa del cliente como los carros de Uber/Didi.
class ColaboradorCercano {
  final String colaboradorAlias;
  final LatLng punto;

  const ColaboradorCercano({required this.colaboradorAlias, required this.punto});

  factory ColaboradorCercano.fromJson(Map<String, dynamic> json) {
    return ColaboradorCercano(
      colaboradorAlias: json['colaboradorAlias'] as String,
      punto: LatLng(
        (json['latitud'] as num).toDouble(),
        (json['longitud'] as num).toDouble(),
      ),
    );
  }
}

/// Envía y consulta la posición "en vivo" (aproximada) de los
/// colaboradores disponibles. No se guarda en ningún lado de forma
/// permanente — ver `backend/ubicaciones.js`: es presencia efímera,
/// solo mientras el colaborador tiene la pantalla de inicio abierta.
class UbicacionService {
  UbicacionService._();

  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'x-api-key': BackendConfig.apiKey,
      };

  static Uri _uri(String path) => Uri.parse('${BackendConfig.baseUrl}$path');

  static Future<void> enviarUbicacion({
    required String colaboradorAlias,
    required double latitud,
    required double longitud,
  }) async {
    try {
      await http
          .post(
            _uri('/api/colaboradores/ubicacion'),
            headers: _headers,
            body: jsonEncode({
              'colaboradorAlias': colaboradorAlias,
              'latitud': latitud,
              'longitud': longitud,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Sin conexión momentánea: no es crítico, se reintenta en el
      // próximo ciclo del Timer.
    }
  }

  static Future<void> desconectar(String colaboradorAlias) async {
    try {
      await http
          .post(
            _uri('/api/colaboradores/desconectar'),
            headers: _headers,
            body: jsonEncode({'colaboradorAlias': colaboradorAlias}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Si no se pudo avisar, el colaborador igual desaparece solo del
      // mapa a los 90s por falta de actualizaciones.
    }
  }

  static Future<List<ColaboradorCercano>> colaboradoresCercanos() async {
    final respuesta = await http
        .get(_uri('/api/colaboradores/cercanos'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    final cuerpo = jsonDecode(respuesta.body) as Map<String, dynamic>;
    if (cuerpo['ok'] != true) return [];
    return (cuerpo['colaboradores'] as List)
        .map((c) => ColaboradorCercano.fromJson(c as Map<String, dynamic>))
        .toList();
  }
}
