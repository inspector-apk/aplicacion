import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:exif/exif.dart' as exif_pkg;
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

/// Resultado del análisis de una foto antes de enviarla como respuesta.
class ResultadoDeteccionIA {
  final int iaPorcentaje;
  final int veracidadPorcentaje;

  /// false cuando la foto no trae ninguna señal clara: el resultado es
  /// un estimado neutral, no una detección segura en ningún sentido.
  final bool concluyente;

  const ResultadoDeteccionIA({
    required this.iaPorcentaje,
    required this.veracidadPorcentaje,
    required this.concluyente,
  });
}

/// Nombres de generadores/herramientas de IA que suelen quedar escritos
/// en los metadatos de la imagen (XMP, PNG tEXt/iTXt, EXIF Software,
/// comentarios JPEG...).
const _kMarcadoresGeneradores = [
  'stable diffusion',
  'stablediffusion',
  'midjourney',
  'dall-e',
  'dalle',
  'gpt-image',
  'sora',
  'novelai',
  'invokeai',
  'comfyui',
  'automatic1111',
  'firefly',
  'nightcafe',
  'leonardo.ai',
  'leonardo ai',
  'ideogram',
  'playground ai',
  'playgroundai',
  'craiyon',
  'dreamstudio',
  'fooocus',
  'bing image creator',
  'copilot designer',
  'runwayml',
  'runway gen',
  'imagen',
  'flux.1',
  'flux1',
  'recraft',
  'canva magic media',
  'meta ai',
  'grok imagine',
  'luma ai',
  'krea ai',
  'seedream',
  'qwen-image',
  'kling ai',
  'pika labs',
  'generative fill',
];

/// Términos "genéricos" de generación (aparecen junto a un prompt, ej.
/// en el chunk "parameters" que deja el WebUI de Stable Diffusion).
const _kMarcadoresGenericosIA = ['negative prompt:', 'cfg scale:', 'sampler:'];

/// El estándar IPTC/C2PA ("Content Credentials") que cada vez más
/// generadores (OpenAI, Google, Microsoft, Adobe...) usan por norma
/// para declarar que una imagen fue creada o editada por IA. Es la
/// señal más confiable de todas las que se pueden leer sin conexión.
const _kMarcadoresEstandarIA = [
  'trainedalgorithmicmedia',
  'compositewithtrainedalgorithmicmedia',
  'digitalsourcetype',
];

/// Presencia de un manifiesto C2PA genérico (caja JUMBF), aunque no se
/// pueda leer su tipo exacto: hoy en día lo usan sobre todo apps y
/// generadores de IA, muy pocas cámaras físicas lo incluyen todavía.
/// Señal débil por sí sola.
const _kMarcadorC2paGenerico = 'c2pa';

/// Analiza una foto ANTES de enviarla, buscando señales tanto en sus
/// metadatos como en sus píxeles. No llama a ningún servicio externo
/// ni requiere cuenta ni conexión — todo corre en el celular.
///
/// Combina varias señales con un puntaje ponderado en vez de una regla
/// única, y siempre dice explícitamente que es una estimación: nunca
/// afirma 0% ni 100%, y solo exige confirmación cuando el puntaje total
/// de señales de IA es alto.
class DeteccionIAService {
  DeteccionIAService._();

  static Future<ResultadoDeteccionIA> analizarImagen(Uint8List bytes) async {
    var puntosIA = 0;
    var puntosReal = 0;

    // 1) Búsqueda de texto en TODO el archivo: cubre PNG (tEXt/iTXt),
    // JPEG (comentarios, paquetes XMP en APP1) y el estándar C2PA/IPTC,
    // sin necesidad de interpretar cada formato por separado. Es segura
    // ante falsos positivos: los datos binarios/comprimidos del resto
    // del archivo no van a coincidir por azar con estas frases.
    final texto = _aTextoBusqueda(bytes);

    if (_kMarcadoresEstandarIA.any(texto.contains)) {
      puntosIA += 55; // estándar oficial de procedencia: la señal más fuerte
    } else if (texto.contains(_kMarcadorC2paGenerico)) {
      puntosIA += 10; // manifiesto de procedencia presente, pero sin poder leer el tipo
    }
    if (_kMarcadoresGeneradores.any(texto.contains)) {
      puntosIA += 45; // nombre de una herramienta de IA conocida
    }
    if (_kMarcadoresGenericosIA.any(texto.contains)) {
      puntosIA += 35; // parámetros típicos de un generador (steps, sampler...)
    }

    // 2) Metadatos EXIF de cámara (solo aplica a JPEG; en PNG casi
    // nunca existen). Cuantos más campos típicos de una cámara real
    // aparecen, más fuerte la señal de que es una foto real.
    final esJpeg = _esJpeg(bytes);
    if (esJpeg) {
      try {
        final tags = await exif_pkg.readExifFromBytes(bytes);
        if (_valorTag(tags, 'Image Make').isNotEmpty) puntosReal += 20;
        if (_valorTag(tags, 'Image Model').isNotEmpty) puntosReal += 20;
        if (_valorTag(tags, 'EXIF DateTimeOriginal').isNotEmpty) puntosReal += 10;
        if (_valorTag(tags, 'EXIF ExposureTime').isNotEmpty) puntosReal += 8;
        if (_valorTag(tags, 'EXIF FNumber').isNotEmpty) puntosReal += 8;
        if (_valorTag(tags, 'EXIF ISOSpeedRatings').isNotEmpty) puntosReal += 8;
        if (_valorTag(tags, 'EXIF FocalLength').isNotEmpty) puntosReal += 8;
        if (_valorTag(tags, 'GPS GPSLatitude').isNotEmpty) puntosReal += 12;
        if (tags.containsKey('JPEGThumbnail')) puntosReal += 10;
      } catch (_) {
        // Metadatos corruptos o ilegibles: no suma en ningún sentido.
      }
    }

    // 3) Dimensiones "de laboratorio": muchos generadores de IA entregan
    // imágenes cuadradas y múltiplos exactos de 64 píxeles (limitación
    // técnica de los modelos de difusión); una foto de cámara real casi
    // nunca cae justo en esa combinación. Señal débil, solo de apoyo.
    final dimensiones = _dimensionesDeCabecera(bytes);
    if (dimensiones != null) {
      final (ancho, alto) = dimensiones;
      final esCuadrada = ancho == alto;
      final multiploDe64 = ancho % 64 == 0 && alto % 64 == 0;
      if (esCuadrada && multiploDe64) puntosIA += 10;
    }

    // 4) Ruido de los píxeles: en un aparte (isolate) para no trabar la
    // interfaz mientras decodifica y analiza la imagen.
    try {
      final ruido = await compute(_analizarRuidoDePixeles, bytes);
      if (ruido != null) {
        if (ruido < 1.1) {
          puntosIA += 20; // zonas planas anormalmente "limpias"
        } else if (ruido > 3.2) {
          puntosReal += 15; // grano de sensor típico de una cámara real
        }
      }
    } catch (_) {
      // No se pudo decodificar la imagen: se ignora esta señal.
    }

    if (puntosIA == 0 && puntosReal == 0) {
      return const ResultadoDeteccionIA(
          iaPorcentaje: 50, veracidadPorcentaje: 50, concluyente: false);
    }

    // Puntaje relativo entre las dos señales, acotado para nunca
    // afirmar una certeza absoluta (3%–97%): sigue siendo una
    // estimación, no una prueba.
    final total = puntosIA + puntosReal;
    final crudo = total == 0 ? 50 : (100 * puntosIA / total).round();
    final iaPorcentaje = crudo.clamp(3, 97);

    return ResultadoDeteccionIA(
      iaPorcentaje: iaPorcentaje,
      veracidadPorcentaje: 100 - iaPorcentaje,
      concluyente: true,
    );
  }

  static String _valorTag(Map<String, exif_pkg.IfdTag> tags, String clave) {
    return tags[clave]?.printable.trim() ?? '';
  }

  static bool _esJpeg(Uint8List bytes) {
    return bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8;
  }

  /// Convierte el archivo completo a texto en minúsculas para buscar
  /// palabras clave, usando latin1 (byte a byte, sin decodificar como
  /// UTF-8) para que nunca falle sobre datos binarios.
  static String _aTextoBusqueda(Uint8List bytes) {
    return latin1.decode(bytes, allowInvalid: true).toLowerCase();
  }

  /// Ancho/alto reales del archivo, leídos de la cabecera (JPEG SOF o
  /// PNG IHDR) sin decodificar toda la imagen — barato y rápido.
  static (int, int)? _dimensionesDeCabecera(Uint8List bytes) {
    try {
      if (_esPng(bytes) && bytes.length >= 24) {
        final ancho = ByteData.sublistView(bytes, 16, 20).getUint32(0);
        final alto = ByteData.sublistView(bytes, 20, 24).getUint32(0);
        return (ancho, alto);
      }
      if (_esJpeg(bytes)) {
        var i = 2;
        while (i + 9 < bytes.length) {
          if (bytes[i] != 0xFF) break;
          final marcador = bytes[i + 1];
          // Marcadores SOFn (inicio de imagen), excluyendo DHT/JPG ext.
          final esSof = marcador >= 0xC0 &&
              marcador <= 0xCF &&
              marcador != 0xC4 &&
              marcador != 0xC8 &&
              marcador != 0xCC;
          final longitudSegmento =
              ByteData.sublistView(bytes, i + 2, i + 4).getUint16(0);
          if (esSof) {
            final alto = ByteData.sublistView(bytes, i + 5, i + 7).getUint16(0);
            final ancho = ByteData.sublistView(bytes, i + 7, i + 9).getUint16(0);
            return (ancho, alto);
          }
          i += 2 + longitudSegmento;
        }
      }
    } catch (_) {
      // Cabecera corta o corrupta: se ignora esta señal.
    }
    return null;
  }

  static bool _esPng(Uint8List bytes) {
    if (bytes.length < 8) return false;
    const firma = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    for (var i = 0; i < 8; i++) {
      if (bytes[i] != firma[i]) return false;
    }
    return true;
  }
}

/// Corre en un isolate aparte (vía `compute`). Decodifica la imagen,
/// la reduce a un tamaño manejable y mide cuánto "grano"/ruido de alta
/// frecuencia queda en sus zonas más planas: las imágenes generadas por
/// IA suelen tener regiones (cielos, fondos, paredes) anormalmente
/// lisas, mientras que una foto real conserva ruido de sensor incluso
/// ahí. Es una heurística aproximada, no una medición exacta.
double? _analizarRuidoDePixeles(Uint8List bytes) {
  final decodificada = img.decodeImage(bytes);
  if (decodificada == null) return null;

  final reducida = decodificada.width >= decodificada.height
      ? img.copyResize(decodificada,
          width: math.min(320, decodificada.width),
          interpolation: img.Interpolation.average)
      : img.copyResize(decodificada,
          height: math.min(320, decodificada.height),
          interpolation: img.Interpolation.average);

  final ancho = reducida.width;
  final alto = reducida.height;
  if (ancho < 20 || alto < 20) return null;

  // Luminancia en escala de grises.
  final gris = Float32List(ancho * alto);
  for (var y = 0; y < alto; y++) {
    for (var x = 0; x < ancho; x++) {
      final p = reducida.getPixel(x, y);
      gris[y * ancho + x] = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
    }
  }

  const tamanoParche = 16;
  final variasParches = <double>[];
  final ruidoParches = <double>[];

  for (var py = 1; py + tamanoParche < alto - 1; py += tamanoParche) {
    for (var px = 1; px + tamanoParche < ancho - 1; px += tamanoParche) {
      double sumaLaplacianoAbs = 0;
      double sumaCuadrados = 0;
      double suma = 0;
      var n = 0;
      for (var y = py; y < py + tamanoParche; y++) {
        for (var x = px; x < px + tamanoParche; x++) {
          final centro = gris[y * ancho + x];
          final laplaciano = 4 * centro -
              gris[y * ancho + (x - 1)] -
              gris[y * ancho + (x + 1)] -
              gris[(y - 1) * ancho + x] -
              gris[(y + 1) * ancho + x];
          sumaLaplacianoAbs += laplaciano.abs();
          suma += centro;
          sumaCuadrados += centro * centro;
          n++;
        }
      }
      final media = suma / n;
      final varianza = (sumaCuadrados / n) - (media * media);
      variasParches.add(varianza);
      ruidoParches.add(sumaLaplacianoAbs / n);
    }
  }

  if (variasParches.isEmpty) return null;

  // Nos quedamos con el cuartil de parches más "planos" (menor
  // varianza de intensidad): ahí es donde el ruido de sensor de una
  // cámara real es más fácil de distinguir del suavizado típico de IA.
  final indices = List<int>.generate(variasParches.length, (i) => i)
    ..sort((a, b) => variasParches[a].compareTo(variasParches[b]));
  final cuartil = math.max(1, indices.length ~/ 4);
  final ruidoPlano = indices
      .take(cuartil)
      .map((i) => ruidoParches[i])
      .toList()
    ..sort();

  return ruidoPlano[ruidoPlano.length ~/ 2]; // mediana
}
