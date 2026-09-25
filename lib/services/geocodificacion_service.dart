import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/backend_config.dart';

/// Un lugar devuelto por el buscador (dirección, conjunto, edificio,
/// negocio, barrio...).
class LugarEncontrado {
  final String nombre;
  final String detalle;
  final LatLng punto;

  /// true cuando solo se ubicó la vía (no el número exacto): el cliente debe
  /// ajustar el punto tocando el mapa.
  final bool aproximado;

  const LugarEncontrado({
    required this.nombre,
    required this.detalle,
    required this.punto,
    this.aproximado = false,
  });

  /// Texto corto para guardar como "dirección" de la solicitud.
  String get etiqueta => detalle.isEmpty ? nombre : '$nombre, $detalle';
}

/// Buscador de lugares de Bogotá (como la búsqueda de Google Maps) sobre
/// datos de OpenStreetMap: primero Photon (bueno con nombres de
/// conjuntos, edificios y negocios) y, si no encuentra nada, Nominatim.
///
/// Limitación: OpenStreetMap no tiene todos los números de puerta de
/// Bogotá; si la dirección exacta no aparece, se busca por el nombre del
/// lugar o la vía y luego se ajusta el punto tocando el mapa.
class GeocodificacionService {
  GeocodificacionService._();

  // Caja que encierra Bogotá (minLon, minLat, maxLon, maxLat).
  static const double _minLon = -74.26;
  static const double _minLat = 4.45;
  static const double _maxLon = -73.98;
  static const double _maxLat = 4.85;

  static const Map<String, String> _headers = {
    'User-Agent': 'InspectorApp/1.0 (desarrollador.inspector@servialco.com)',
    'Accept': 'application/json',
  };

  static final Map<String, List<LugarEncontrado>> _cache = {};

  /// Busca lugares: primero en el caché del celular, luego en el servidor
  /// de Inspector (que tiene su propio caché y respeta los límites de los
  /// servicios gratuitos) y, solo si el servidor no responde, directo en
  /// los servicios de OpenStreetMap.
  static Future<List<LugarEncontrado>> buscar(
    String consulta, {
    LatLng? cerca,
  }) async {
    final q = _normalizar(consulta);
    if (q.length < 3) return [];

    final clave = q.toLowerCase();
    final enCache = _cache[clave];
    if (enCache != null) return enCache;

    final resultados =
        await _servidor(q, cerca) ?? await _directo(q, cerca);
    if (resultados.isNotEmpty) {
      if (_cache.length >= 100) _cache.remove(_cache.keys.first);
      _cache[clave] = resultados;
    }
    return resultados;
  }

  /// null si el servidor no respondió (para intentar directo).
  static Future<List<LugarEncontrado>?> _servidor(
      String q, LatLng? cerca) async {
    try {
      final uri = Uri.parse('${BackendConfig.baseUrl}/api/geocodificar')
          .replace(queryParameters: {
        'q': q,
        if (cerca != null) 'lat': '${cerca.latitude}',
        if (cerca != null) 'lon': '${cerca.longitude}',
      });
      final resp = await http
          .get(uri, headers: {'x-api-key': BackendConfig.apiKey})
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['ok'] != true) return null;
      return (data['lugares'] as List).map((l) {
        return LugarEncontrado(
          nombre: l['nombre'] as String,
          detalle: (l['detalle'] as String?) ?? '',
          punto: LatLng((l['latitud'] as num).toDouble(),
              (l['longitud'] as num).toDouble()),
          aproximado: l['aproximado'] == true,
        );
      }).toList();
    } catch (_) {
      return null;
    }
  }

  static Future<List<LugarEncontrado>> _directo(
      String q, LatLng? cerca) async {
    var resultados = await _photon(q, cerca);
    if (resultados.isEmpty && !q.toLowerCase().contains('bogot')) {
      resultados = await _photon('$q Bogotá', cerca);
    }
    if (resultados.isEmpty) {
      resultados = await _nominatim(q);
    }

    // Dirección con nomenclatura colombiana ("Cl 80 # 69-20"): OSM casi
    // nunca tiene el número de puerta, así que además se ubica la vía
    // ("Calle 80") y se ofrece como punto aproximado.
    final via = _viaDeDireccion(q);
    if (via != null) {
      final vias = await _photon('$via Bogotá', cerca);
      for (final v in vias.take(2)) {
        resultados.add(LugarEncontrado(
          nombre: q,
          detalle: v.detalle,
          punto: v.punto,
          aproximado: true,
        ));
      }
    }
    return resultados;
  }

  static final RegExp _viaRegex = RegExp(
    r'^(calle|carrera|avenida calle|avenida carrera|avenida|diagonal|'
    r'transversal|cll|cra|cl|cr|kr|av|dg|tv)\.?\s*(\d+)\s*([a-z])?'
    r'(\s*bis)?(\s*(sur|este|norte))?',
    caseSensitive: false,
  );

  static const Map<String, String> _abreviaturas = {
    'cll': 'Calle', 'cl': 'Calle', 'cra': 'Carrera', 'cr': 'Carrera',
    'kr': 'Carrera', 'av': 'Avenida', 'dg': 'Diagonal', 'tv': 'Transversal',
  };

  /// "Cl 80 69 20" → "Calle 80"; null si no parece una dirección con
  /// número de puerta.
  static String? _viaDeDireccion(String q) {
    final m = _viaRegex.firstMatch(q);
    if (m == null) return null;
    // Solo interesa si además trae el número de puerta (más dígitos).
    final resto = q.substring(m.end);
    if (!RegExp(r'\d').hasMatch(resto)) return null;
    final tipo = m.group(1)!.toLowerCase();
    final nombreTipo = _abreviaturas[tipo] ??
        tipo.split(' ').map((p) => p[0].toUpperCase() + p.substring(1)).join(' ');
    final letra = m.group(3)?.toUpperCase() ?? '';
    final bis = m.group(4) != null ? ' Bis' : '';
    final orient = m.group(6) != null
        ? ' ${m.group(6)![0].toUpperCase()}${m.group(6)!.substring(1).toLowerCase()}'
        : '';
    return '$nombreTipo ${m.group(2)}$letra$bis$orient';
  }

  /// Quita símbolos típicos de las direcciones colombianas ("#", "No.")
  /// que confunden al buscador, y espacios repetidos.
  static String _normalizar(String texto) {
    return texto
        .replaceAll(RegExp(r'(#|№|\bno\.?\s|\bnro\.?\s)', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static Future<List<LugarEncontrado>> _photon(String q, LatLng? cerca) async {
    try {
      final uri = Uri.https('photon.komoot.io', '/api/', {
        'q': q,
        'limit': '8',
        'bbox': '$_minLon,$_minLat,$_maxLon,$_maxLat',
        if (cerca != null) 'lat': '${cerca.latitude}',
        if (cerca != null) 'lon': '${cerca.longitude}',
      });
      final resp =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return [];
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final features = (data['features'] as List?) ?? [];
      final lugares = <LugarEncontrado>[];
      for (final f in features) {
        final props = (f['properties'] ?? {}) as Map<String, dynamic>;
        final coords = (f['geometry']?['coordinates'] as List?) ?? [];
        if (coords.length < 2) continue;
        final lon = (coords[0] as num).toDouble();
        final lat = (coords[1] as num).toDouble();
        if (!_dentroDeBogota(lat, lon)) continue;

        final calle = [props['street'], props['housenumber']]
            .whereType<String>()
            .where((s) => s.isNotEmpty)
            .join(' ');
        final nombre = (props['name'] as String?)?.trim().isNotEmpty == true
            ? (props['name'] as String).trim()
            : (calle.isNotEmpty ? calle : 'Lugar sin nombre');
        final detalle = <String>[
          if ((props['name'] as String?) != null && calle.isNotEmpty) calle,
          if (props['district'] is String) props['district'] as String,
          if (props['locality'] is String) props['locality'] as String,
          if (props['city'] is String) props['city'] as String,
        ].where((s) => s != nombre).toSet().join(', ');

        lugares.add(LugarEncontrado(
          nombre: nombre,
          detalle: detalle,
          punto: LatLng(lat, lon),
        ));
      }
      return lugares;
    } catch (_) {
      return [];
    }
  }

  static Future<List<LugarEncontrado>> _nominatim(String q) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': '$q, Bogotá, Colombia',
        'format': 'jsonv2',
        'limit': '8',
        'countrycodes': 'co',
        'viewbox': '$_minLon,$_maxLat,$_maxLon,$_minLat',
        'bounded': '1',
      });
      final resp =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return [];
      final lista = jsonDecode(resp.body) as List;
      final lugares = <LugarEncontrado>[];
      for (final r in lista) {
        final lat = double.tryParse('${r['lat']}');
        final lon = double.tryParse('${r['lon']}');
        if (lat == null || lon == null) continue;
        final partes = ('${r['display_name'] ?? ''}').split(', ');
        final nombre = (r['name'] as String?)?.isNotEmpty == true
            ? r['name'] as String
            : (partes.isNotEmpty ? partes.first : 'Lugar sin nombre');
        final detalle =
            partes.skip(1).where((s) => s != nombre).take(3).join(', ');
        lugares.add(LugarEncontrado(
          nombre: nombre,
          detalle: detalle,
          punto: LatLng(lat, lon),
        ));
      }
      return lugares;
    } catch (_) {
      return [];
    }
  }

  static bool _dentroDeBogota(double lat, double lon) =>
      lat >= _minLat && lat <= _maxLat && lon >= _minLon && lon <= _maxLon;
}
