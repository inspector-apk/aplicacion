import '../models/solicitud.dart';

/// Valores FICTICIOS de referencia (no es un cobro real, no hay pasarela
/// de pagos): cada tipo de contenido tiene un precio base en pesos
/// colombianos, que cambia según la categoría de la solicitud
/// (personal/comercial/industrial).
const Map<Categoria, Map<TipoSolicitud, int>> kPrecios = {
  Categoria.personal: {
    TipoSolicitud.texto: 15000,
    TipoSolicitud.imagen: 25000,
    TipoSolicitud.audio: 20000,
    TipoSolicitud.video: 40000,
  },
  Categoria.comercial: {
    TipoSolicitud.texto: 30000,
    TipoSolicitud.imagen: 50000,
    TipoSolicitud.audio: 40000,
    TipoSolicitud.video: 80000,
  },
  Categoria.industrial: {
    TipoSolicitud.texto: 60000,
    TipoSolicitud.imagen: 100000,
    TipoSolicitud.audio: 80000,
    TipoSolicitud.video: 160000,
  },
};

int precioDe(Categoria categoria, TipoSolicitud tipo) =>
    kPrecios[categoria]![tipo]!;

int calcularValorTotal(Categoria categoria, Iterable<TipoSolicitud> tipos) {
  return tipos.fold(0, (suma, t) => suma + precioDe(categoria, t));
}

/// Comisión FICTICIA de la plataforma: 10% de lo que pagó el cliente.
/// El otro 90% es lo que "gana" el colaborador. No hay dinero real de
/// por medio en ningún lado.
const double kComisionPlataforma = 0.10;

int gananciaColaborador(int valorTotal) =>
    valorTotal - comisionPlataforma(valorTotal);

int comisionPlataforma(int valorTotal) =>
    (valorTotal * kComisionPlataforma).round();

/// Formatea un valor entero como pesos colombianos: "$45.000".
String formatearPesos(int valor) {
  final texto = valor.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < texto.length; i++) {
    final posicionDesdeElFinal = texto.length - i;
    if (i > 0 && posicionDesdeElFinal % 3 == 0) buffer.write('.');
    buffer.write(texto[i]);
  }
  return '\$$buffer';
}
