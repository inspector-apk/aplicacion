enum TipoSolicitud { texto, imagen, audio, video }

extension TipoSolicitudX on TipoSolicitud {
  String get valor => name;

  String get etiqueta {
    switch (this) {
      case TipoSolicitud.texto:
        return 'Texto';
      case TipoSolicitud.imagen:
        return 'Imagen';
      case TipoSolicitud.audio:
        return 'Audio';
      case TipoSolicitud.video:
        return 'Video';
    }
  }

  static TipoSolicitud fromValor(String valor) {
    return TipoSolicitud.values.firstWhere((t) => t.valor == valor);
  }
}

/// Categoría de la solicitud: cambia el valor (ficticio) que se muestra
/// por cada tipo de contenido pedido.
enum Categoria { personal, comercial, industrial }

extension CategoriaX on Categoria {
  String get valor => name;

  String get etiqueta {
    switch (this) {
      case Categoria.personal:
        return 'Personal';
      case Categoria.comercial:
        return 'Comercial';
      case Categoria.industrial:
        return 'Industrial';
    }
  }

  static Categoria fromValor(String valor) {
    return Categoria.values.firstWhere((c) => c.valor == valor);
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

  /// Uno o más tipos de contenido pedidos (ej. texto + imagen).
  final List<TipoSolicitud> tipos;
  final Categoria categoria;

  /// Valor ficticio (no es un cobro real) calculado a partir de la
  /// categoría y los tipos pedidos — ver `lib/core/precios.dart`.
  final int valorTotal;

  final String descripcion;
  final String localidad;

  /// Dirección exacta (texto libre) escrita por el cliente, dentro de
  /// la localidad elegida — para que el colaborador sepa a dónde ir.
  final String direccion;

  final double latitud;
  final double longitud;
  final EstadoSolicitud estado;
  final String fechaCreacion;
  final String fechaActualizacion;

  /// Metadatos de la respuesta del colaborador — NUNCA el contenido en
  /// sí (ese solo se obtiene, una única vez, con
  /// `SolicitudService.verRespuesta`).
  final String? respuestaFecha;
  final bool respuestaVista;

  const Solicitud({
    this.id,
    required this.clienteAlias,
    this.colaboradorAlias,
    required this.tipos,
    required this.categoria,
    required this.valorTotal,
    required this.descripcion,
    required this.localidad,
    this.direccion = '',
    required this.latitud,
    required this.longitud,
    required this.estado,
    required this.fechaCreacion,
    required this.fechaActualizacion,
    this.respuestaFecha,
    this.respuestaVista = false,
  });

  /// true si hay una respuesta esperando a que el cliente la vea.
  bool get tieneRespuestaSinVer =>
      estado == EstadoSolicitud.completada && !respuestaVista;

  String get tiposEtiqueta => tipos.map((t) => t.etiqueta).join(' + ');

  Map<String, Object?> toJson() {
    return {
      'clienteAlias': clienteAlias,
      'tipos': tipos.map((t) => t.valor).toList(),
      'categoria': categoria.valor,
      'valorTotal': valorTotal,
      'descripcion': descripcion,
      'localidad': localidad,
      'direccion': direccion,
      'latitud': latitud,
      'longitud': longitud,
    };
  }

  factory Solicitud.fromJson(Map<String, dynamic> json) {
    final tiposRaw = json['tipos'];
    final tipos = tiposRaw is List
        ? tiposRaw.map((t) => TipoSolicitudX.fromValor(t as String)).toList()
        : [TipoSolicitudX.fromValor(json['tipo'] as String)]; // compatibilidad

    return Solicitud(
      id: json['id'] as int?,
      clienteAlias: json['cliente_alias'] as String,
      colaboradorAlias: json['colaborador_alias'] as String?,
      tipos: tipos,
      categoria: json['categoria'] != null
          ? CategoriaX.fromValor(json['categoria'] as String)
          : Categoria.personal,
      valorTotal: (json['valor_total'] as num?)?.toInt() ?? 0,
      descripcion: json['descripcion'] as String,
      direccion: json['direccion'] as String? ?? '',
      localidad: json['localidad'] as String,
      latitud: (json['latitud'] as num).toDouble(),
      longitud: (json['longitud'] as num).toDouble(),
      estado: EstadoSolicitudX.fromValor(json['estado'] as String),
      fechaCreacion: json['fecha_creacion'] as String,
      fechaActualizacion: json['fecha_actualizacion'] as String,
      respuestaFecha: json['respuesta_fecha'] as String?,
      respuestaVista: ((json['respuesta_vista'] as num?)?.toInt() ?? 0) == 1,
    );
  }
}
