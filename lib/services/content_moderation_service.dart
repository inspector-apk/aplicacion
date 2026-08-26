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
