// Utilidades compartidas por las funciones del servidor.
// Las carpetas que empiezan con "_" no se publican como función.
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

export const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// Los resultados esperados (PIN incorrecto, rol insuficiente...) responden 200 con ok:false,
// para que la app los muestre como mensaje. Los códigos 4xx/5xx quedan para fallas técnicas.
export function respuesta(cuerpo: Record<string, unknown>, estado = 200): Response {
  return new Response(JSON.stringify(cuerpo), {
    status: estado,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

export function rechazo(mensaje: string, extra: Record<string, unknown> = {}): Response {
  return respuesta({ ok: false, mensaje, ...extra });
}

// Supabase inyecta las llaves con nombres distintos según la antigüedad del proyecto.
function llave(directa: string, varias: string, legado: string): string {
  const d = Deno.env.get(directa);
  if (d) return d;
  const v = Deno.env.get(varias);
  if (v) {
    try {
      const o = JSON.parse(v);
      const k = o.default ?? Object.values(o)[0];
      if (typeof k === "string") return k;
    } catch {
      // formato inesperado: se intenta con la llave de legado
    }
  }
  const l = Deno.env.get(legado);
  if (l) return l;
  throw new Error(`Falta ${directa} en el entorno de la función`);
}

export const URL_SUPABASE = Deno.env.get("SUPABASE_URL")!;
const opciones = { auth: { persistSession: false, autoRefreshToken: false } };

/** Cliente con la llave secreta: puede todo. Usar solo después de autorizar. */
export function clienteAdmin(): SupabaseClient {
  return createClient(URL_SUPABASE, llave("SUPABASE_SECRET_KEY", "SUPABASE_SECRET_KEYS", "SUPABASE_SERVICE_ROLE_KEY"), opciones);
}

/** Cliente con los permisos de quien hizo la solicitud (su token de sesión). */
export function clienteDeUsuario(autorizacion: string): SupabaseClient {
  return createClient(URL_SUPABASE, llave("SUPABASE_PUBLISHABLE_KEY", "SUPABASE_PUBLISHABLE_KEYS", "SUPABASE_ANON_KEY"), {
    ...opciones,
    global: { headers: { Authorization: autorizacion } },
  });
}
