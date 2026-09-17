// Solicitudes sin cuenta (F-04, F-05). Se publica sin exigir sesión: la usan alumnos y maestros.
//
// La base hace todas las reglas (public.solicitud_publica_enviar). Esta función existe porque solo
// aquí se conoce la red desde la que se pide, para el freno contra abusos; la base guarda solo su huella.
import { clienteAdmin, CORS, rechazo, respuesta } from "../_compartido/comun.ts";

function red(req: Request): string {
  const reenviada = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  return reenviada || req.headers.get("cf-connecting-ip") || req.headers.get("x-real-ip") || "desconocida";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return respuesta({ ok: false, mensaje: "Método no permitido" }, 405);

  let s: { accion?: string; datos?: Record<string, unknown>; dispositivo?: string; folio?: string; matricula?: string };
  try {
    s = await req.json();
  } catch {
    return respuesta({ ok: false, mensaje: "Solicitud inválida" }, 400);
  }
  const dispositivo = typeof s.dispositivo === "string" ? s.dispositivo.slice(0, 64) : "";
  const admin = clienteAdmin();

  if (s.accion === "enviar") {
    if (!s.datos || typeof s.datos !== "object") return rechazo("Faltan los datos de la solicitud.");
    const { data, error } = await admin.rpc("solicitud_publica_enviar", {
      p_datos: s.datos,
      p_ip: red(req),
      p_dispositivo: dispositivo,
    });
    // Los errores de regla (P0001) traen un mensaje pensado para quien pide.
    if (error) {
      if (error.code === "P0001") return rechazo(error.message);
      console.error("solicitud_publica_enviar", error);
      return respuesta({ ok: false, mensaje: "No se pudo enviar la solicitud. Intenta de nuevo." }, 500);
    }
    return respuesta({ ok: true, ...data });
  }

  if (s.accion === "recuperar") {
    if (!s.folio || !s.matricula) return rechazo("Escribe el folio y tu matrícula.");
    const { error } = await admin.rpc("solicitud_publica_recuperar", {
      p_folio: s.folio,
      p_matricula: s.matricula,
      p_ip: red(req),
      p_dispositivo: dispositivo,
    });
    if (error) {
      console.error("solicitud_publica_recuperar", error);
      return respuesta({ ok: false, mensaje: "No se pudo completar. Intenta de nuevo." }, 500);
    }
    // Siempre la misma respuesta: no revela si el folio y la matrícula existen.
    return respuesta({ ok: true, mensaje: "Si los datos coinciden, te enviamos el enlace a tu correo. Revisa también la carpeta de correo no deseado (spam)." });
  }

  return rechazo("Acción desconocida.");
});
