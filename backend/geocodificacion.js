// Buscador de lugares de Bogotá (dirección, conjunto, edificio...) sobre
// datos de OpenStreetMap, sin costo.
//
// Todas las apps pasan por este servidor en vez de llamar directo a los
// servicios gratuitos (Photon y Nominatim). Así:
//  - se guarda un caché: la misma búsqueda no se repite hacia afuera;
//  - se respeta el uso justo de esos servicios (límite de velocidad);
//  - se puede cambiar de proveedor sin recompilar la app.

const CONTACTO = process.env.CONTACTO_GEOCODIFICACION || 'desarrollador.inspector@servialco.com';
const USER_AGENT = `InspectorApp/1.0 (${CONTACTO})`;

// Caja que encierra Bogotá.
const MIN_LON = -74.26, MIN_LAT = 4.45, MAX_LON = -73.98, MAX_LAT = 4.85;

const TTL_MS = 7 * 24 * 60 * 60 * 1000; // una semana
const MAX_ENTRADAS = 3000;
const cache = new Map(); // clave -> { expira, valor }

function leerCache(clave) {
  const e = cache.get(clave);
  if (!e) return null;
  if (e.expira < Date.now()) {
    cache.delete(clave);
    return null;
  }
  // refresca el orden (LRU simple)
  cache.delete(clave);
  cache.set(clave, e);
  return e.valor;
}

function guardarCache(clave, valor) {
  if (cache.size >= MAX_ENTRADAS) cache.delete(cache.keys().next().value);
  cache.set(clave, { expira: Date.now() + TTL_MS, valor });
}

// Límite de velocidad por proveedor: una petición a la vez, con un
// mínimo de tiempo entre una y otra.
function crearLimitador(intervaloMs) {
  let cola = Promise.resolve();
  let ultima = 0;
  return (tarea) => {
    const r = cola.then(async () => {
      const espera = ultima + intervaloMs - Date.now();
      if (espera > 0) await new Promise((res) => setTimeout(res, espera));
      try {
        return await tarea();
      } finally {
        ultima = Date.now();
      }
    });
    cola = r.catch(() => {});
    return r;
  };
}
const limitarPhoton = crearLimitador(250);
const limitarNominatim = crearLimitador(1100); // política de Nominatim: 1 req/s

function dentroDeBogota(lat, lon) {
  return lat >= MIN_LAT && lat <= MAX_LAT && lon >= MIN_LON && lon <= MAX_LON;
}

async function obtenerJson(url) {
  const resp = await fetch(url, {
    headers: { 'User-Agent': USER_AGENT, Accept: 'application/json' },
    signal: AbortSignal.timeout(8000),
  });
  if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
  return resp.json();
}

async function buscarPhoton(q, cerca) {
  const params = new URLSearchParams({
    q,
    limit: '8',
    bbox: `${MIN_LON},${MIN_LAT},${MAX_LON},${MAX_LAT}`,
  });
  if (cerca) {
    params.set('lat', String(cerca.lat));
    params.set('lon', String(cerca.lon));
  }
  const data = await limitarPhoton(() => obtenerJson(`https://photon.komoot.io/api/?${params}`));
  const lugares = [];
  for (const f of data.features || []) {
    const p = f.properties || {};
    const [lon, lat] = (f.geometry && f.geometry.coordinates) || [];
    if (typeof lat !== 'number' || typeof lon !== 'number') continue;
    if (!dentroDeBogota(lat, lon)) continue;

    const calle = [p.street, p.housenumber].filter(Boolean).join(' ');
    const nombre = (p.name && String(p.name).trim()) || calle || 'Lugar sin nombre';
    const detalle = [
      p.name && calle ? calle : null,
      p.district,
      p.locality,
      p.city,
    ].filter((s) => s && s !== nombre);
    lugares.push({
      nombre,
      detalle: [...new Set(detalle)].join(', '),
      latitud: lat,
      longitud: lon,
      aproximado: false,
    });
  }
  return lugares;
}

async function buscarNominatim(q) {
  const params = new URLSearchParams({
    q: `${q}, Bogotá, Colombia`,
    format: 'jsonv2',
    limit: '8',
    countrycodes: 'co',
    viewbox: `${MIN_LON},${MAX_LAT},${MAX_LON},${MIN_LAT}`,
    bounded: '1',
  });
  const lista = await limitarNominatim(() =>
    obtenerJson(`https://nominatim.openstreetmap.org/search?${params}`));
  const lugares = [];
  for (const r of lista) {
    const lat = parseFloat(r.lat);
    const lon = parseFloat(r.lon);
    if (Number.isNaN(lat) || Number.isNaN(lon)) continue;
    const partes = String(r.display_name || '').split(', ');
    const nombre = r.name || partes[0] || 'Lugar sin nombre';
    lugares.push({
      nombre,
      detalle: partes.slice(1).filter((s) => s !== nombre).slice(0, 3).join(', '),
      latitud: lat,
      longitud: lon,
      aproximado: false,
    });
  }
  return lugares;
}

// ---- Direcciones con nomenclatura colombiana ("Cl 80 # 69-20") ----

const REGEX_VIA = new RegExp(
  '^(calle|carrera|avenida calle|avenida carrera|avenida|diagonal|transversal|'
  + 'cll|cra|cl|cr|kr|av|dg|tv)\\.?\\s*(\\d+)\\s*([a-z])?(\\s*bis)?(\\s*(sur|este|norte))?',
  'i'
);
const ABREVIATURAS = {
  cll: 'Calle', cl: 'Calle', cra: 'Carrera', cr: 'Carrera', kr: 'Carrera',
  av: 'Avenida', dg: 'Diagonal', tv: 'Transversal',
};
const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);

/** "Cl 80 69 20" → "Calle 80"; null si no trae número de puerta. */
function viaDeDireccion(q) {
  const m = REGEX_VIA.exec(q);
  if (!m) return null;
  if (!/\d/.test(q.slice(m[0].length))) return null;
  const tipo = m[1].toLowerCase();
  const nombreTipo = ABREVIATURAS[tipo] || tipo.split(' ').map(cap).join(' ');
  return `${nombreTipo} ${m[2]}${(m[3] || '').toUpperCase()}${m[4] ? ' Bis' : ''}`
    + `${m[6] ? ' ' + cap(m[6].toLowerCase()) : ''}`;
}

function normalizarConsulta(texto) {
  return String(texto || '')
    .replace(/(#|№|\bno\.?\s|\bnro\.?\s)/gi, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Busca lugares. `cerca` ({lat, lon}) da prioridad a lo más cercano.
 * Devuelve una lista de { nombre, detalle, latitud, longitud, aproximado }.
 */
async function buscar(consulta, cerca) {
  const q = normalizarConsulta(consulta);
  if (q.length < 3 || q.length > 120) return [];

  const clave = `${q.toLowerCase()}|${cerca ? `${cerca.lat.toFixed(2)},${cerca.lon.toFixed(2)}` : ''}`;
  const enCache = leerCache(clave);
  if (enCache) return enCache;

  let resultados = [];
  try {
    resultados = await buscarPhoton(q, cerca);
    if (resultados.length === 0 && !/bogot/i.test(q)) {
      resultados = await buscarPhoton(`${q} Bogotá`, cerca);
    }
  } catch (err) {
    console.warn('[geocodificación] Photon falló:', err.message);
  }
  if (resultados.length === 0) {
    try {
      resultados = await buscarNominatim(q);
    } catch (err) {
      console.warn('[geocodificación] Nominatim falló:', err.message);
    }
  }

  // Dirección con número de puerta: OSM casi nunca lo tiene, así que
  // también se ubica la vía y se ofrece como punto aproximado.
  const via = viaDeDireccion(q);
  if (via) {
    try {
      const vias = await buscarPhoton(`${via} Bogotá`, cerca);
      for (const v of vias.slice(0, 2)) {
        resultados.push({ ...v, nombre: q, aproximado: true });
      }
    } catch (_) { /* sin vía aproximada */ }
  }

  // Solo se guarda en caché si hubo respuesta útil (un fallo temporal
  // de red no debe quedar "recordado" una semana).
  if (resultados.length > 0) guardarCache(clave, resultados);
  return resultados;
}

module.exports = { buscar };
