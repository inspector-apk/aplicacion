/// Filtro por palabras clave para bloquear automáticamente solicitudes
/// con contenido sexual, de explotación infantil o similar. No es un
/// filtro perfecto (es una lista de palabras, no comprende contexto),
/// pero evita el uso más obvio y grave de la app para pedir ese tipo de
/// contenido.
class ContentModerationService {
  ContentModerationService._();

  static const List<String> _palabrasProhibidas = [
    // Contenido sexual / pornográfico
    'porno',
    'pornografia',
    'pornografico',
    'pornografica',
    'sexo',
    'sexual',
    'desnudo',
    'desnuda',
    'desnudos',
    'desnudas',
    'prostitucion',
    'prostituta',
    'prostituto',
    'erotico',
    'erotica',
    'xxx',
    'nsfw',
    // Explotación / contenido infantil
    'nino',
    'ninos',
    'nina',
    'ninas',
    'menor',
    'menores',
    'infantil',
    'pedofilia',
    'pedofilo',
    'pedofila',
    'pederasta',
    // Otros contenidos graves relacionados
    'incesto',
    'violacion',
    'abuso sexual',
    'explotacion sexual',
    'trata de personas',
  ];

  /// true si el texto contiene alguna palabra prohibida (sin distinguir
  /// mayúsculas ni acentos).
  static bool contieneContenidoProhibido(String texto) {
    final normalizado = _normalizar(texto);
    return _palabrasProhibidas
        .any((palabra) => normalizado.contains(palabra));
  }

  static final RegExp _sexualOViolento = RegExp(
    r'\b(porno|pornograf|xxx|nsfw|desnud|erotic|prostitu|sexo explicit|'
    r'acto sexual|relaciones sexuales|genitales|abuso sexual|'
    r'explotacion sexual|violacion|violar|incesto|pedofil|pederast|'
    r'decapit|descuartiz|desmembr|mutilad|tortur|masacr|asesinat|'
    r'asesinar|degollar|apunal|acuchill|ahorcad|cadaver|gore|autolesion|'
    r'suicid)',
  );

  /// Revisión rápida del texto que escribe un colaborador al responder:
  /// contenido sexual explícito o violento. Es un aviso inmediato; la
  /// verificación oficial (texto, imagen y video) la hace el servidor.
  static bool respuestaContieneContenidoProhibido(String texto) {
    return _sexualOViolento.hasMatch(_normalizar(texto));
  }

  static String _normalizar(String texto) {
    var resultado = texto.toLowerCase();
    const conAcento = 'áàäâãéèëêíìïîóòöôõúùüûñ';
    const sinAcento = 'aaaaaeeeeiiiiooooouuuun';
    for (var i = 0; i < conAcento.length; i++) {
      resultado = resultado.replaceAll(conAcento[i], sinAcento[i]);
    }
    return resultado;
  }
}
