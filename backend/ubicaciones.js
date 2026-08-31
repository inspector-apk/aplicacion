/**
 * Posición aproximada de los colaboradores "disponibles" (con su pantalla
 * de inicio abierta), para mostrarlos en el mapa del Cliente como hace
 * Uber/Didi con sus carros. A propósito NO se guarda en la base de datos
 * ni se persiste en disco: es presencia efímera en memoria, se pierde si
 * el backend se reinicia y cada posición expira sola a los pocos minutos
 * si el colaborador deja de enviarla (cierra la app, se desconecta, etc.).
 */

// alias -> { lat, lng, actualizado: <timestamp ms> }
const ubicaciones = new Map();

// Si un colaborador no envía su posición en este tiempo, se deja de
// mostrar (se asume que ya no está disponible).
const EXPIRA_MS = 90 * 1000;

// Difuminado de privacidad: nunca se entrega la posición exacta del
// colaborador a los clientes, solo un punto aleatorio dentro de este
// radio aproximado (~150m).
const RADIO_DIFUMINADO_GRADOS = 0.0014;

function actualizarUbicacion(alias, lat, lng) {
  ubicaciones.set(alias, { lat, lng, actualizado: Date.now() });
}

function quitarUbicacion(alias) {
  ubicaciones.delete(alias);
}

function difuminar(valor) {
  return valor + (Math.random() * 2 - 1) * RADIO_DIFUMINADO_GRADOS;
}

function colaboradoresCercanos() {
  const ahora = Date.now();
  const resultado = [];
  for (const [alias, u] of ubicaciones.entries()) {
    if (ahora - u.actualizado > EXPIRA_MS) {
      ubicaciones.delete(alias);
      continue;
    }
    resultado.push({
      colaboradorAlias: alias,
      latitud: difuminar(u.lat),
      longitud: difuminar(u.lng),
    });
  }
  return resultado;
}

module.exports = { actualizarUbicacion, quitarUbicacion, colaboradoresCercanos };
