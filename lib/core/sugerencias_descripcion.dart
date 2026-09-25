import '../models/solicitud.dart';

/// Una acción predefinida que el cliente puede pedirle al colaborador.
/// El formulario de solicitud no tiene campos de texto libre: el cliente
/// elige una de estas opciones, que ya están redactadas para que no se
/// presten a malas interpretaciones.
class OpcionSolicitud {
  final String texto;

  /// Tipos de contenido que el cliente debe haber elegido para que esta
  /// opción tenga sentido (ej. "tomar una foto" solo aparece si pidió
  /// imagen). Vacío = aplica siempre.
  final Set<TipoSolicitud> requiere;

  const OpcionSolicitud(this.texto, {this.requiere = const {}});
}

const Map<Categoria, List<OpcionSolicitud>> kOpcionesSolicitud = {
  Categoria.personal: [
    OpcionSolicitud('Confirmar si hay alguien en el lugar indicado'),
    OpcionSolicitud('Verificar que el lugar indicado existe y cómo se ve'),
    OpcionSolicitud('Confirmar que un paquete fue entregado en el lugar'),
    OpcionSolicitud('Verificar el estado exterior de un vehículo parqueado'),
    OpcionSolicitud('Tomar una foto del frente de la vivienda',
        requiere: {TipoSolicitud.imagen}),
    OpcionSolicitud('Grabar un video del entorno del lugar indicado',
        requiere: {TipoSolicitud.video}),
    OpcionSolicitud('Describir con una nota de voz lo que se ve en el lugar',
        requiere: {TipoSolicitud.audio}),
  ],
  Categoria.comercial: [
    OpcionSolicitud('Verificar si el local está abierto ahora'),
    OpcionSolicitud('Confirmar el horario de atención publicado en el local'),
    OpcionSolicitud('Verificar cómo está el inventario o la exhibición'),
    OpcionSolicitud('Comprobar si hay fila o disponibilidad de atención'),
    OpcionSolicitud('Tomar una foto de la fachada o vitrina del negocio',
        requiere: {TipoSolicitud.imagen}),
    OpcionSolicitud('Grabar un video de la entrada o el interior del local',
        requiere: {TipoSolicitud.video}),
    OpcionSolicitud('Describir con una nota de voz lo que se ve en el local',
        requiere: {TipoSolicitud.audio}),
  ],
  Categoria.industrial: [
    OpcionSolicitud('Verificar el estado exterior de una bodega o planta'),
    OpcionSolicitud('Confirmar la llegada de un cargamento o proveedor'),
    OpcionSolicitud(
        'Revisar las condiciones de seguridad visibles en la instalación'),
    OpcionSolicitud('Documentar el estado visible de la infraestructura'),
    OpcionSolicitud('Tomar fotos de la maquinaria o equipos visibles',
        requiere: {TipoSolicitud.imagen}),
    OpcionSolicitud('Grabar un video del recorrido exterior de la instalación',
        requiere: {TipoSolicitud.video}),
    OpcionSolicitud(
        'Describir con una nota de voz lo que se ve en la instalación',
        requiere: {TipoSolicitud.audio}),
  ],
};

/// Opciones que aplican a la categoría y a los tipos de contenido que el
/// cliente ya eligió.
List<OpcionSolicitud> opcionesPara(
    Categoria categoria, Set<TipoSolicitud> tipos) {
  return (kOpcionesSolicitud[categoria] ?? const <OpcionSolicitud>[])
      .where((o) => o.requiere.every(tipos.contains))
      .toList();
}
