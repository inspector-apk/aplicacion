import 'dart:convert';
import 'dart:typed_data';

import 'package:exif/exif.dart' as exif_pkg;

/// Resultado del análisis de una foto antes de enviarla como respuesta.
class ResultadoDeteccionIA {
  final int iaPorcentaje;
  final int veracidadPorcentaje;

  /// false cuando la foto no trae ninguna señal clara (ni metadatos de
  /// cámara ni marcas de generador de IA): el resultado es un estimado
  /// neutral, no una detección segura en ningún sentido.
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
  'imagen',
  'flux.1',
  'flux1',
  'recraft',
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

/// Analiza una foto ANTES de enviarla, buscando señales en sus propios
/// metadatos (nunca el contenido/píxeles): no llama a ningún servicio
/// externo ni requiere cuenta ni conexión — todo corre en el celular.
///
/// Combina varias señales con un puntaje ponderado en vez de una regla
/// única, y siempre dice explícitamente que es una estimación: una foto
/// real sin metadatos (ej. reenviada por WhatsApp, o con los metadatos
/// borrados a propósito) puede salir "no concluyente", igual que una
/// foto de IA a la que le quitaron las marcas. Por eso nunca se afirma
/// 0% ni 100%, y solo se exige confirmación cuando aparece una señal
/// de IA explícita y fuerte.
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
    if (_esJpeg(bytes)) {
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
}
