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

/// Palabras que suelen aparecer en los metadatos que dejan los
/// generadores de imágenes por IA más comunes.
const _kMarcadoresIA = [
  'stable diffusion',
  'midjourney',
  'dall-e',
  'dalle',
  'novelai',
  'invokeai',
  'firefly',
  'nightcafe',
  'leonardo.ai',
  'comfyui',
  'automatic1111',
];

/// Analiza una foto ANTES de enviarla, buscando señales en sus propios
/// metadatos (nunca el contenido/píxeles): no llama a ningún servicio
/// externo ni requiere cuenta ni conexión — todo corre en el celular.
///
/// Es, a propósito, una heurística aproximada y no una detección
/// certera: una foto real sin metadatos de cámara (ej. reenviada por
/// WhatsApp) puede salir como "no concluyente", y una foto de IA a la
/// que le borraron los metadatos también. Por eso siempre se muestra
/// junto con el % y se dejan enviar igual, salvo que se encuentre una
/// marca explícita de generador de IA.
class DeteccionIAService {
  DeteccionIAService._();

  static Future<ResultadoDeteccionIA> analizarImagen(
      Uint8List bytes) async {
    // PNG: los generadores de IA suelen guardar el "prompt" y el nombre
    // del generador directamente en los chunks de texto del archivo.
    if (_esPng(bytes)) {
      if (_pngTieneMarcadorIA(bytes)) {
        return const ResultadoDeteccionIA(
            iaPorcentaje: 92, veracidadPorcentaje: 8, concluyente: true);
      }
      return const ResultadoDeteccionIA(
          iaPorcentaje: 50, veracidadPorcentaje: 50, concluyente: false);
    }

    // JPEG: las fotos reales de cámara/celular casi siempre traen
    // metadatos EXIF (marca y modelo); las imágenes de IA normalmente
    // no los traen (o traen el nombre del generador en su lugar).
    try {
      final tags = await exif_pkg.readExifFromBytes(bytes);
      if (tags.isNotEmpty) {
        final software = tags['Image Software']?.printable.toLowerCase() ?? '';
        if (_kMarcadoresIA.any((m) => software.contains(m))) {
          return const ResultadoDeteccionIA(
              iaPorcentaje: 92, veracidadPorcentaje: 8, concluyente: true);
        }
        final marca = tags['Image Make']?.printable.trim() ?? '';
        final modelo = tags['Image Model']?.printable.trim() ?? '';
        if (marca.isNotEmpty || modelo.isNotEmpty) {
          return const ResultadoDeteccionIA(
              iaPorcentaje: 12, veracidadPorcentaje: 88, concluyente: true);
        }
      }
    } catch (_) {
      // Metadatos corruptos o ilegibles: se trata como "sin datos".
    }

    return const ResultadoDeteccionIA(
        iaPorcentaje: 50, veracidadPorcentaje: 50, concluyente: false);
  }

  static bool _esPng(Uint8List bytes) {
    if (bytes.length < 8) return false;
    const firma = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    for (var i = 0; i < 8; i++) {
      if (bytes[i] != firma[i]) return false;
    }
    return true;
  }

  /// Recorre los chunks de un PNG buscando texto (tEXt/iTXt/zTXt) con
  /// alguna marca conocida de generador de IA. zTXt va comprimido y no
  /// se descomprime aquí (no vale la pena la dependencia extra); con
  /// tEXt/iTXt basta para los casos más comunes (ej. AUTOMATIC1111).
  static bool _pngTieneMarcadorIA(Uint8List bytes) {
    var i = 8; // después de la firma
    while (i + 8 <= bytes.length) {
      final longitud = ByteData.sublistView(bytes, i, i + 4).getUint32(0);
      final tipo = String.fromCharCodes(bytes.sublist(i + 4, i + 8));
      final inicioDatos = i + 8;
      final finDatos = inicioDatos + longitud;
      if (finDatos > bytes.length) break;

      if (tipo == 'tEXt' || tipo == 'iTXt') {
        final texto =
            String.fromCharCodes(bytes.sublist(inicioDatos, finDatos))
                .toLowerCase();
        if (_kMarcadoresIA.any((m) => texto.contains(m)) ||
            texto.contains('parameters') ||
            texto.contains('prompt')) {
          return true;
        }
      }
      if (tipo == 'IEND') break;
      i = finDatos + 4; // salta el CRC de 4 bytes
    }
    return false;
  }
}
