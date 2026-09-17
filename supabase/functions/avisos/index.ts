// Vacía la cola de envíos (tabla envio): correos y avisos al celular. También borra del almacén las
// fotos de identificación que ya cumplieron su plazo (P-14).
//
// La despierta la base cada vez que encola algo (pg_net) y cada 5 minutos (pg_cron). Se publica sin
// exigir sesión: llamarla de más no hace daño, solo manda lo que ya estaba en la cola.
//
// Secretos de la función (Supabase → Edge Functions → Secrets):
//   RESEND_API_KEY  o  BREVO_API_KEY     para correos
//   CORREO_REMITENTE                     ej. "Laboratorio Maker <laboratorio@tudominio.mx>"
//   FIREBASE_CUENTA_SERVICIO             JSON de la cuenta de servicio de Firebase, para avisos al celular
// Si falta alguno, ese canal se queda en la cola hasta que se configure.
import { clienteAdmin, CORS, respuesta } from "../_compartido/comun.ts";
import { enviarCorreo, hayCorreo } from "./correo.ts";
import { enviarPush, hayPush, type ResultadoPush } from "./fcm.ts";

interface Envio {
  id: number;
  canal: "CORREO" | "PUSH";
  destino: string;
  asunto: string;
  cuerpo: string;
  datos: Record<string, unknown>;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const admin = clienteAdmin();
  const canales = [...(hayCorreo() ? ["CORREO"] : []), ...(hayPush() ? ["PUSH"] : [])];
  const resumen = { enviados: 0, fallidos: 0, identificaciones_borradas: 0, canales };

  if (canales.length > 0) {
    // Varias vueltas por si la cola es larga; cada vuelta toma hasta 20.
    for (let vuelta = 0; vuelta < 5; vuelta++) {
      const { data, error } = await admin.rpc("envios_tomar", { p_canales: canales, p_limite: 20 });
      if (error) {
        console.error("envios_tomar", error);
        break;
      }
      const lote = (data ?? []) as Envio[];
      if (lote.length === 0) break;
      for (const e of lote) {
        let ok = false;
        let detalle: string | null = null;
        let tokenInvalido = false;
        try {
          if (e.canal === "CORREO") {
            await enviarCorreo(e.destino, e.asunto, e.cuerpo);
            ok = true;
          } else {
            const r: ResultadoPush = await enviarPush(e.destino, e.asunto, e.cuerpo, e.datos);
            ok = r.ok;
            detalle = r.error ?? null;
            tokenInvalido = r.tokenInvalido;
          }
        } catch (err) {
          detalle = err instanceof Error ? err.message : String(err);
        }
        ok ? resumen.enviados++ : resumen.fallidos++;
        const { error: e2 } = await admin.rpc("envio_resultado", {
          p_id: e.id,
          p_ok: ok,
          p_error: detalle,
          p_token_invalido: tokenInvalido,
        });
        if (e2) console.error("envio_resultado", e2);
      }
    }
  }

  const { data: rutas, error: e3 } = await admin.rpc("identificaciones_por_borrar", { p_limite: 100 });
  if (e3) {
    console.error("identificaciones_por_borrar", e3);
  } else if (rutas && rutas.length > 0) {
    const lista = (rutas as { ruta: string }[]).map((r) => r.ruta);
    const { error: e4 } = await admin.storage.from("privado").remove(lista);
    if (e4) {
      console.error("borrar identificaciones", e4);
    } else {
      await admin.rpc("identificaciones_borradas", { p_rutas: lista });
      resumen.identificaciones_borradas = lista.length;
    }
  }

  return respuesta({ ok: true, ...resumen });
});
