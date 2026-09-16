// Acceso con PIN (F-02). Se publica sin exigir sesión: es justo la que la abre.
//
// 1. La base verifica el PIN, cuenta intentos y bloquea (public.pin_verificar).
// 2. Si es correcto, se abre una sesión de Supabase para esa cuenta con un enlace de un solo uso
//    que nunca sale del servidor. La sesión queda marcada como "otp", no como "password",
//    y por eso la base solo le permite acciones de nivel docente.
import { clienteAdmin, CORS, rechazo, respuesta } from "../_compartido/comun.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return respuesta({ ok: false, mensaje: "Método no permitido" }, 405);

  let datos: { usuario_id?: string; pin?: string };
  try {
    datos = await req.json();
  } catch {
    return respuesta({ ok: false, mensaje: "Solicitud inválida" }, 400);
  }
  const { usuario_id, pin } = datos;
  if (!usuario_id || !UUID.test(usuario_id) || !pin || !/^\d{4,6}$/.test(pin)) {
    return rechazo("Elige tu nombre y escribe tu PIN de 4 a 6 números.");
  }

  const admin = clienteAdmin();
  const { data: v, error: e1 } = await admin.rpc("pin_verificar", { p_usuario: usuario_id, p_pin: pin });
  if (e1) {
    console.error("pin_verificar", e1);
    return respuesta({ ok: false, mensaje: "No se pudo verificar el PIN. Intenta de nuevo." }, 500);
  }
  if (!v.ok) return rechazo(v.mensaje, { motivo: v.motivo, restantes: v.restantes ?? null });

  const { data: enlace, error: e2 } = await admin.auth.admin.generateLink({ type: "magiclink", email: v.correo });
  if (e2 || !enlace?.properties?.hashed_token) {
    console.error("generateLink", e2);
    return respuesta({ ok: false, mensaje: "No se pudo abrir la sesión. Intenta de nuevo." }, 500);
  }
  const { data: s, error: e3 } = await clienteAdmin().auth.verifyOtp({
    type: "magiclink",
    token_hash: enlace.properties.hashed_token,
  });
  if (e3 || !s.session) {
    console.error("verifyOtp", e3);
    return respuesta({ ok: false, mensaje: "No se pudo abrir la sesión. Intenta de nuevo." }, 500);
  }

  return respuesta({ ok: true, refresh_token: s.session.refresh_token, access_token: s.session.access_token });
});
