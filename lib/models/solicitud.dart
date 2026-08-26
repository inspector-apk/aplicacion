enum TipoSolicitud { texto, imagen }

extension TipoSolicitudX on TipoSolicitud {
  String get valor => name;
  String get etiqueta => this == TipoSolicitud.texto ? 'Texto' : 'Imagen';

  static TipoSolicitud fromValor(String valor) {
    return TipoSolicitud.values.firstWhere((t) => t.valor == valor);
  }
}

enum EstadoSolicitud { pendiente, aceptada, completada, cancelada }

extension EstadoSolicitudX on EstadoSolicitud {
  String get valor => name;

  String get etiqueta {
    switch (this) {
      case EstadoSolicitud.pendiente:
        return 'Buscando colaborador';
      case EstadoSolicitud.aceptada:
        return 'Colaborador en camino';
      case EstadoSolicitud.completada:
        return 'Completada';
      case EstadoSolicitud.cancelada:
        return 'Cancelada';
    }
  }

  static EstadoSolicitud fromValor(String valor) {
    return EstadoSolicitud.values.firstWhere((e) => e.valor == valor);
  }
}

/// Una solicitud vive en el backend compartido (no en SQLite local),
/// porque tiene que poder verla un Colaborador en un dispositivo
/// distinto al del Cliente que la creó. Por eso se identifica a las
/// personas por su `alias` (único, generado al registrarse) en vez de
/// un id local de base de datos, que no tendría sentido fuera del
/// dispositivo donde se creó.
class Solicitud {
  final int? id;
  final String clienteAlias;
  final String? colaboradorAlias;
  final TipoSolicitud tipo;
  final String descripcion;
  final String localidad;
  final double latitud;
  final double longitud;
  final EstadoSolicitud estado;
  final String fechaCreacion;
  final String fechaActualizacion;

  const Solicitud({
    this.id,
    required this.clienteAlias,
    this.colaboradorAlias,
    required this.tipo,
    required this.descripcion,
    required this.localidad,
    required this.latitud,
    required this.longitud,
    required this.estado,
    required this.fechaCreacion,
    required this.fechaActualizacion,
  });

  Map<String, Object?> toJson() {
    return {
      'clienteAlias': clienteAlias,
      'tipo': tipo.valor,
      'descripcion': descripcion,
      'localidad': localidad,
      'latitud': latitud,
      'longitud': longitud,
    };
  }

  factory Solicitud.fromJson(Map<String, dynamic> json) {
    return Solicitud(
      id: json['id'] as int?,
      clienteAlias: json['cliente_alias'] as String,
      colaboradorAlias: json['colaborador_alias'] as String?,
      tipo: TipoSolicitudX.fromValor(json['tipo'] as String),
      descripcion: json['descripcion'] as String,
      localidad: json['localidad'] as String,
      latitud: (json['latitud'] as num).toDouble(),
      longitud: (json['longitud'] as num).toDouble(),
      estado: EstadoSolicitudX.fromValor(json['estado'] as String),
      fechaCreacion: json['fecha_creacion'] as String,
      fechaActualizacion: json['fecha_actualizacion'] as String,
    );
  }
}
