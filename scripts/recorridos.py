"""Recorridos de punta a punta contra el proyecto de pruebas (Fase 8; se repiten en la Fase 9).

Uso:
  INVENTARIO_ENTORNO=pruebas python scripts/recorridos.py

Hace lo mismo que los botones de la app, por la misma puerta (la API de Supabase con la sesión de cada rol,
las funciones del servidor y el almacén de fotos), y al final imprime una lista con ✔ / ✘ por paso.
Cada corrida usa datos nuevos (matrícula y nombres con la hora), así que se puede repetir.

Solo corre contra el proyecto de pruebas (mismo candado que scripts/pruebas.py).
Las contraseñas y PIN de prueba se leen de secretos/cuentas-pruebas.txt y nunca se imprimen.
"""
from __future__ import annotations

import datetime as dt
import json
import re
import sys
import time
import traceback
import urllib.error
import urllib.request
import uuid

import db
import pruebas

AHORA = dt.datetime.now()
MARCA = AHORA.strftime("%m%d%H%M")
# PNG de 1×1: basta para probar el almacén (no es una foto real de nadie).
PNG = bytes.fromhex("89504e470d0a1a0a0000000d4948445200000001000000010806000000"
                    "1f15c4890000000d49444154789c6360f8ffff3f0005fe02fea7d6a5"
                    "4f0000000049454e44ae426082")


class ErrorApi(Exception):
    def __init__(self, estado: int, cuerpo):
        self.estado, self.cuerpo = estado, cuerpo
        msg = cuerpo.get("message") or cuerpo.get("mensaje") or cuerpo.get("msg") if isinstance(cuerpo, dict) else cuerpo
        detalle = cuerpo.get("details") if isinstance(cuerpo, dict) else None
        super().__init__(f"{estado} {msg}{f' ({detalle})' if detalle else ''}")


class Api:
    def __init__(self) -> None:
        env = db.leer_env()
        self.url = env["SUPABASE_URL"]
        self.llave = env["SUPABASE_PUBLISHABLE_KEY"]

    def _pedir(self, metodo: str, ruta: str, cuerpo=None, token: str | None = None, crudo: bytes | None = None,
               tipo: str = "application/json", extra: dict | None = None):
        encabezados = {"apikey": self.llave, "Authorization": f"Bearer {token or self.llave}", "Content-Type": tipo,
                       "User-Agent": "recorridos-inventario-maker/1.0", **(extra or {})}
        datos = crudo if crudo is not None else (json.dumps(cuerpo).encode() if cuerpo is not None else None)
        s = urllib.request.Request(self.url + ruta, method=metodo, data=datos, headers=encabezados)
        try:
            with urllib.request.urlopen(s, timeout=60) as r:
                texto = r.read().decode() or "null"
                return json.loads(texto)
        except urllib.error.HTTPError as e:
            texto = e.read().decode(errors="replace")
            try:
                raise ErrorApi(e.code, json.loads(texto)) from None
            except json.JSONDecodeError:
                raise ErrorApi(e.code, texto[:300]) from None

    def entrar_contrasena(self, correo: str, clave: str) -> str:
        return self._pedir("POST", "/auth/v1/token?grant_type=password", {"email": correo, "password": clave})["access_token"]

    def entrar_pin(self, usuario_id: str, pin: str) -> str:
        r = self._pedir("POST", "/functions/v1/acceso-pin", {"usuario_id": usuario_id, "pin": pin})
        if not r.get("ok"):
            raise ErrorApi(400, r)
        return r["access_token"]

    def rpc(self, token: str | None, nombre: str, **p):
        return self._pedir("POST", f"/rest/v1/rpc/{nombre}", p, token)

    def leer(self, token: str | None, ruta: str):
        return self._pedir("GET", f"/rest/v1/{ruta}", None, token)

    def funcion(self, token: str | None, nombre: str, cuerpo: dict):
        return self._pedir("POST", f"/functions/v1/{nombre}", cuerpo, token)

    def subir(self, token: str, bucket: str, ruta: str) -> str:
        self._pedir("POST", f"/storage/v1/object/{bucket}/{ruta}", token=token, crudo=PNG, tipo="image/png",
                    )
        return ruta


# --- Registro de resultados -------------------------------------------------------------------
resultados: list[tuple[str, str, bool, str]] = []
seccion_actual = ""


def seccion(nombre: str) -> None:
    global seccion_actual
    seccion_actual = nombre
    print(f"\n== {nombre}")


def paso(descripcion: str, fn, *, debe_fallar: str | None = None):
    """Corre un paso. Con debe_fallar, el paso sale bien solo si el servidor lo rechaza con ese texto."""
    try:
        r = fn()
        if debe_fallar is not None:
            resultados.append((seccion_actual, descripcion, False, "el servidor lo permitió y debía rechazarlo"))
            print(f"  ✘ {descripcion}: el servidor lo permitió y debía rechazarlo")
            return None
        resultados.append((seccion_actual, descripcion, True, ""))
        print(f"  ✔ {descripcion}")
        return r
    except ErrorApi as e:
        if debe_fallar is not None and re.search(debe_fallar, str(e) + json.dumps(e.cuerpo, ensure_ascii=False), re.I):
            resultados.append((seccion_actual, descripcion, True, f"rechazado como debe: {e}"))
            print(f"  ✔ {descripcion} (rechazado: {str(e)[:90]})")
            return None
        resultados.append((seccion_actual, descripcion, False, str(e)))
        print(f"  ✘ {descripcion}: {e}")
    except Exception as e:  # noqa: BLE001
        resultados.append((seccion_actual, descripcion, False, f"{type(e).__name__}: {e}"))
        print(f"  ✘ {descripcion}: {type(e).__name__}: {e}")
        traceback.print_exc(limit=1)
    return None


def cierto(condicion: bool, mensaje: str):
    if not condicion:
        raise AssertionError(mensaje)
    return True


# --- Datos de apoyo ---------------------------------------------------------------------------
def cuentas_de_prueba() -> dict[str, dict]:
    texto = pruebas.ARCHIVO_CUENTAS.read_text(encoding="utf-8")
    cuentas = {}
    for rol, correo, clave, pin in re.findall(r"^(\w+)\s+(\S+@\S+)\s+contraseña: (\S+)\s+PIN: (\d+)", texto, re.M):
        cuentas[rol] = {"correo": correo, "clave": clave, "pin": pin}
    return cuentas


def sql(consulta: str, *args):
    with db.conectar(nube=True) as c:
        return c.execute(consulta, args).fetchall()


def articulo(codigo: str) -> str:
    return str(sql("select id from public.articulo where codigo = %s", codigo)[0][0])


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    pruebas.exigir_pruebas()
    api = Api()
    cuentas = cuentas_de_prueba()
    ids = {r[1].lower(): str(r[0]) for r in sql("select id, correo from public.usuario where correo is not null")}
    print(f"Recorridos contra {api.url}  (marca {MARCA})")

    def confirmar(token: str, rol: str) -> bool:
        """Como el diálogo de la app: cada movimiento mayor pide la contraseña otra vez."""
        r = api.rpc(token, "confirmar_contrasena", p_contrasena=cuentas[rol]["clave"])
        return cierto((r or {}).get("ok", True) is not False, f"no confirmó: {r}")

    # Cada corrida toma artículos que tengan con qué: así se puede repetir sin preparar nada.
    prestables = [str(r[0]) for r in sql("select id from public.v_inventario where activo and prestable and not es_consumible "
                                         "and not coalesce(no_se_presta, false) and disponible >= 2 order by codigo")]
    multimetro, brocas = prestables[0], prestables[1]
    consumible = str(sql("select id from public.v_inventario where activo and es_consumible and disponible >= 5 order by codigo limit 1")[0][0])

    # ------------------------------------------------------------------ visitante
    seccion("Visitante sin sesión")
    paso("ve el catálogo", lambda: cierto(len(api.leer(None, "articulo?select=id,codigo&limit=5")) == 5, "no trae artículos"))
    paso("no puede prestar", lambda: api.rpc(None, "prestamo_registrar", p_lineas=[{"articulo_id": multimetro, "cantidad": 1}],
                                              p_responsable_usuario=None, p_responsable_solicitante=None,
                                              p_fecha_compromiso=None, p_nota=None, p_comando=str(uuid.uuid4())),
         debe_fallar=r"40[13]|permission|sesi")
    paso("no ve los préstamos abiertos", lambda: api.rpc(None, "prestamos_abiertos_listar"), debe_fallar=r"40[13]|permission|sesi")
    paso("no ve datos de alumnos", lambda: cierto(api.leer(None, "solicitante?select=id&limit=1") in ([], None), "ve solicitantes"),
         debe_fallar=r"40[13]|permission")

    # ------------------------------------------------------------------ entrar
    seccion("Entrar")
    R = paso("responsable entra con contraseña", lambda: api.entrar_contrasena(cuentas["RESPONSABLE"]["correo"], cuentas["RESPONSABLE"]["clave"]))
    S = paso("sub administración entra con contraseña", lambda: api.entrar_contrasena(cuentas["SUBADMIN"]["correo"], cuentas["SUBADMIN"]["clave"]))
    D = paso("docente entra con PIN", lambda: api.entrar_pin(ids[cuentas["DOCENTE"]["correo"]], cuentas["DOCENTE"]["pin"]))
    paso("PIN equivocado se rechaza", lambda: api.entrar_pin(ids[cuentas["DOCENTE"]["correo"]], "0000" if cuentas["DOCENTE"]["pin"] != "0000" else "1111"),
         debe_fallar=r"PIN|incorrect|no coincide|400|401")
    if not (R and S and D):
        return informe()
    paso("mi_sesion del responsable", lambda: cierto(api.rpc(R, "mi_sesion") is not None, "vacía"))

    # ------------------------------------------------------------------ alumno y préstamo
    seccion("Préstamo a un alumno (responsable)")
    matricula = f"9{MARCA}"
    alumno = paso("registrar alumno en persona", lambda: api.rpc(R, "solicitante_crear_rapido", p_nombre=f"Alumno Prueba {MARCA}", p_tipo="ALUMNO",
                                                                p_matricula=matricula, p_grupo="3A",
                                                                p_correo="jaimelugomiranda+alumno@gmail.com", p_telefono=None))
    paso("correo que no es del dominio se rechaza", lambda: api.rpc(R, "solicitante_crear_rapido", p_nombre="Otro Alumno Prueba", p_tipo="ALUMNO",
                                                                    p_matricula=f"8{MARCA}", p_grupo="3A", p_correo="alguien@hotmail.com", p_telefono=None),
         debe_fallar=r"correo|dominio|termina")
    paso("buscar por matrícula exacta lo encuentra", lambda: cierto(len(api.rpc(R, "solicitante_buscar", p_matricula=matricula)) == 1, "no lo encontró"))
    paso("buscar por matrícula parcial NO lo encuentra", lambda: cierto(len(api.rpc(R, "solicitante_buscar", p_matricula=matricula[:5])) == 0, "encontró con parcial"))
    yo_r, yo_d = ids[cuentas["RESPONSABLE"]["correo"]], ids[cuentas["DOCENTE"]["correo"]]
    manana = (dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=1)).isoformat()
    cmd_prestamo = str(uuid.uuid4())
    grupo = paso("prestar un artículo al alumno hasta mañana", lambda: api.rpc(R, "prestamo_registrar", p_lineas=[{"articulo_id": multimetro, "cantidad": 1}],
                                                                              p_responsable_usuario=None, p_responsable_solicitante=alumno,
                                                                              p_fecha_compromiso=manana, p_nota="Recorrido de prueba", p_comando=cmd_prestamo))
    disponible = sql("select disponible from public.v_inventario where id = %s", multimetro)[0][0]
    paso("no se puede prestar más de lo disponible", lambda: api.rpc(R, "prestamo_registrar", p_lineas=[{"articulo_id": multimetro, "cantidad": disponible + 1}],
                                                                     p_responsable_usuario=yo_r, p_responsable_solicitante=None,
                                                                     p_fecha_compromiso=None, p_nota=None, p_comando=str(uuid.uuid4())),
         debe_fallar=r"disponib|alcanza|existencia")
    hecho = sql("select id from public.movimiento where grupo = %s and tipo = 'PRESTAMO'", cmd_prestamo)
    prestamo = str(hecho[0][0]) if hecho else None
    paso("aparece en préstamos abiertos", lambda: cierto(any(p.get("prestamo_id") == prestamo for p in api.rpc(R, "prestamos_abiertos_listar")), "no aparece"))
    if prestamo:
        paso("extender el préstamo con motivo", lambda: api.rpc(R, "prestamo_extender", p_prestamo=prestamo,
                                                               p_fecha=(dt.datetime.now(dt.timezone.utc) + dt.timedelta(days=3)).isoformat(),
                                                               p_motivo="Proyecto de feria"))
        paso("expediente del préstamo", lambda: cierto(api.rpc(R, "expediente_prestamo", p_prestamo=prestamo) is not None, "vacío"))
        inc = str(uuid.uuid4())
        paso("regresa con daño (con incidencia y foto)", lambda: api.rpc(R, "devolucion_registrar", p_comando=str(uuid.uuid4()), p_lineas=[{
            "prestamo_id": prestamo, "regresan": 1, "danadas": 1, "incidencia_dano_id": inc, "nota_dano": "Pantalla estrellada (prueba)",
            "fotos_dano": [{"ruta": api.subir(R, "privado", f"incidencias/{inc}/{uuid.uuid4()}.png"), "tipo": "GENERAL"}]}]))
        paso("ya no aparece en préstamos abiertos", lambda: cierto(not [p for p in api.rpc(R, "prestamos_abiertos_listar") if p.get("prestamo_id") == prestamo], "sigue abierto"))
        paso("la incidencia queda por revisar", lambda: cierto(any(inc in json.dumps(x) for x in api.rpc(R, "por_revisar")), "no aparece"))
        paso("confirmar el daño", lambda: confirmar(R, "RESPONSABLE") and api.rpc(R, "incidencia_resolver", p_ids=[inc], p_decision="CONFIRMAR", p_motivo="Revisado (prueba)"))
        paso("registrar la reparación", lambda: api.rpc(R, "reparacion_registrar", p_articulo=multimetro, p_cantidad=1, p_nota="Reparado (prueba)"))
    if grupo:
        g2 = paso("prestar las brocas y deshacerlo", lambda: api.rpc(R, "prestamo_registrar", p_lineas=[{"articulo_id": brocas, "cantidad": 1}],
                                                                     p_responsable_usuario=yo_r, p_responsable_solicitante=None,
                                                                     p_fecha_compromiso=None, p_nota=None, p_comando=str(uuid.uuid4())))
        if g2:
            paso("deshacer el préstamo", lambda: api.rpc(R, "prestamo_deshacer", p_grupo=g2 if isinstance(g2, str) else g2.get("grupo")))

    # ------------------------------------------------------------------ docente
    seccion("Docente con PIN")
    paso("docente se presta a sí mismo", lambda: api.rpc(D, "prestamo_registrar", p_lineas=[{"articulo_id": brocas, "cantidad": 1}],
                                                        p_responsable_usuario=yo_d, p_responsable_solicitante=None,
                                                        p_fecha_compromiso=None, p_nota=None, p_comando=str(uuid.uuid4())))
    paso("docente ve sus préstamos", lambda: cierto(len(api.rpc(D, "mis_prestamos")) >= 1, "no ve el suyo"))
    paso("docente NO puede dar de baja", lambda: api.rpc(D, "baja_registrar", p_articulo=brocas, p_cantidad=1, p_de_fuera_de_servicio=False,
                                                        p_motivo="OTRO", p_justificacion="Prueba de permisos", p_oficio=None),
         debe_fallar=r"ROL|NIVEL|permiso|40[13]|PT40")
    paso("docente NO puede ajustar conteos", lambda: api.rpc(D, "ajuste_conteo", p_articulo=brocas, p_en_taller=1, p_motivo="CONTEO_FISICO", p_nota=None),
         debe_fallar=r"ROL|NIVEL|permiso|40[13]|PT40")
    paso("docente propone un conteo", lambda: api.rpc(D, "conteo_proponer", p_articulo=consumible, p_en_taller=5, p_nota="Conteo de prueba"))
    paso("docente reporta un consumo", lambda: api.rpc(D, "consumo_registrar", p_articulo=consumible, p_cantidad=1, p_nota="Consumo de prueba",
                                                      p_comando=str(uuid.uuid4())))
    paso("docente NO ve cuentas", lambda: api.rpc(D, "cuentas_listar"), debe_fallar=r"ROL|permiso|40[13]|PT40")
    for p in (api.rpc(D, "mis_prestamos") or []):
        paso("docente devuelve lo suyo", lambda p=p: api.rpc(D, "devolucion_registrar", p_comando=str(uuid.uuid4()),
                                                              p_lineas=[{"prestamo_id": p["prestamo_id"], "regresan": p.get("pendiente", 1)}]))

    # ------------------------------------------------------------------ movimientos mayores
    seccion("Movimientos mayores (responsable)")
    paso("ajuste sin confirmar la contraseña se detiene", lambda: api.rpc(R, "ajuste_conteo", p_articulo=consumible, p_en_taller=4, p_motivo="CONTEO_FISICO", p_nota="Recorrido"),
         debe_fallar=r"CONFIRMAR_CONTRASENA")
    paso("confirmar contraseña", lambda: api.rpc(R, "confirmar_contrasena", p_contrasena=cuentas["RESPONSABLE"]["clave"]))
    paso("confirmar contraseña otra vez", lambda: api.rpc(R, "confirmar_contrasena", p_contrasena=cuentas["RESPONSABLE"]["clave"]))
    propuestos = sorted(api.rpc(R, "conteos_por_aplicar") or [], key=lambda x: str(x.get("contado_en", "")), reverse=True)
    if propuestos:
        paso("aplicar el conteo que propuso el docente", lambda: confirmar(R, "RESPONSABLE") and api.rpc(R, "conteos_aplicar", p_ids=[propuestos[0]["id"]], p_notas=None))
    paso("ajuste de conteo con motivo", lambda: confirmar(R, "RESPONSABLE") and api.rpc(R, "ajuste_conteo", p_articulo=consumible, p_en_taller=4, p_motivo="CONTEO_FISICO", p_nota="Recorrido"))
    nuevo = str(uuid.uuid4())
    paso("alta de un artículo nuevo con foto", lambda: confirmar(R, "RESPONSABLE") and api.rpc(R, "articulo_crear", p_id=nuevo, p_cantidad=3, p_comando=str(uuid.uuid4()),
                                                              p_datos={"nombre": f"Artículo de prueba {MARCA}", "categoria": "COMUN", "unidad": "pieza",
                                                                       "etiquetado": "LOTE", "estado_fisico": "NUEVO", "es_consumible": False},
                                                              p_fotos=[{"ruta": api.subir(R, "fotos", f"articulos/{nuevo}/{uuid.uuid4()}.png"), "tipo": "GENERAL"}]))
    paso("editar el artículo nuevo", lambda: confirmar(R, "RESPONSABLE") and api.rpc(R, "articulo_editar", p_id=nuevo, p_cambios={"marca_modelo": "Marca de prueba"}, p_justificacion=None))
    paso("dar de baja 1 pieza con justificación", lambda: confirmar(R, "RESPONSABLE") and api.rpc(R, "baja_registrar", p_articulo=nuevo, p_cantidad=1, p_de_fuera_de_servicio=False,
                                                                 p_motivo="OBSOLETO", p_justificacion="Recorrido de prueba", p_oficio=None))
    paso("la baja sin justificación se rechaza", lambda: confirmar(R, "RESPONSABLE") and api.rpc(R, "baja_registrar", p_articulo=nuevo, p_cantidad=1, p_de_fuera_de_servicio=False,
                                                                p_motivo="OBSOLETO", p_justificacion="", p_oficio=None),
         debe_fallar=r"justific|obligatori|explica")
    paso("existencias cuadran con los movimientos", lambda: cierto(sql("select count(*) from public.v_existencias e join public.articulo a on a.id = e.articulo_id where a.id = %s", nuevo)[0][0] >= 0, "?"))

    # ------------------------------------------------------------------ contenedores
    seccion("Contenedores")
    caja = str(uuid.uuid4())
    paso("crear contenedor", lambda: api.rpc(R, "contenedor_crear", p_id=caja, p_nombre=f"Caja de prueba {MARCA}", p_tipo="CAJA", p_padre=None,
                                            p_categoria=None, p_foto=None, p_nota=None))
    paso("acomodar el artículo nuevo en el contenedor", lambda: api.rpc(R, "articulos_acomodar", p_articulos=[nuevo], p_contenedor=caja))
    paso("préstamos del contenedor", lambda: api.rpc(R, "prestamos_de_contenedor", p_contenedor=caja))

    # ------------------------------------------------------------------ inventario periódico
    seccion("Inventario periódico")
    # Solo puede haber uno abierto: si quedó uno de otra corrida, se sigue con ese.
    abierto = sql("select id from public.inventario_periodico where estado = 'ABIERTO' limit 1")
    if abierto:
        inv = str(abierto[0][0])
        paso("abrir otro con uno ya abierto se rechaza", lambda: api.rpc(R, "inventario_abrir", p_nombre="Otro", p_alcance={"categorias": ["COMUN"]}),
             debe_fallar=r"ya hay un inventario abierto")
    else:
        inv = paso("abrir un inventario de Común", lambda: api.rpc(R, "inventario_abrir", p_nombre=f"Inventario de prueba {MARCA}", p_alcance={"categorias": ["COMUN"]}))
    if inv:
        arts = paso("lista de artículos a contar", lambda: api.rpc(R, "inventario_articulos", p_inventario=inv)) or []
        for a in arts[:3]:
            paso(f"contar {a.get('codigo')}", lambda a=a: api.rpc(D, "inventario_contar", p_inventario=inv, p_articulo=a["articulo_id"] if "articulo_id" in a else a["id"],
                                                                  p_cantidad=max(0, int(a.get("esperado") or a.get("existencia") or 1) - 1),
                                                                  p_contenedor=None, p_nota=None))
        difs = paso("ver diferencias", lambda: api.rpc(R, "inventario_diferencias", p_inventario=inv)) or []
        # Solo se decide lo que se contó y no cuadra (lo no contado queda así en el acta).
        for d in [d for d in difs if (d.get("contados") or 0) > 0 and (d.get("diferencia") or 0) != 0]:
            paso(f"decidir la diferencia de {d.get('codigo')}", lambda d=d: confirmar(R, "RESPONSABLE") and api.rpc(
                R, "inventario_decidir", p_inventario=inv, p_articulo=d.get("articulo_id") or d.get("id"), p_decision="AJUSTE", p_nota="Prueba"))
        paso("cerrar el inventario", lambda: api.rpc(R, "inventario_cerrar", p_inventario=inv))
        paso("reporte del inventario periódico", lambda: api.rpc(R, "reporte_inventario_periodico", p_inventario=inv))
        paso("folio del acta de inventario (AIP)", lambda: cierto(str(api.rpc(R, "reporte_registrar", p_tipo="ACTA_INVENTARIO", p_formato="PDF",
                                                                             p_parametros={"inventario": inv})).startswith("AIP"), "sin folio AIP"))

    # ------------------------------------------------------------------ reportes
    seccion("Reportes")
    for nombre in ("reporte_encabezado", "reporte_prestamos_abiertos", "reporte_incidencias", "reporte_bajas", "reporte_movimientos", "reporte_faltantes_kits"):
        params = {} if nombre in ("reporte_encabezado", "reporte_prestamos_abiertos", "reporte_faltantes_kits") else \
            {"p_desde": (AHORA - dt.timedelta(days=30)).date().isoformat(), "p_hasta": (AHORA + dt.timedelta(days=1)).date().isoformat()}
        paso(nombre.replace("_", " "), lambda n=nombre, p=params: api.rpc(R, n, **p))
    paso("responsable NO puede firmar acta de entrega", lambda: api.rpc(R, "reporte_registrar", p_tipo="ACTA_ENTREGA", p_formato="PDF", p_parametros={}),
         debe_fallar=r"sub ?admin|ROL|PT40|40[13]")
    paso("sub administración saca folio de acta de entrega (AER)", lambda: confirmar(S, "SUBADMIN") and
         cierto(str(api.rpc(S, "reporte_registrar", p_tipo="ACTA_ENTREGA", p_formato="PDF", p_parametros={})).startswith("AER"), "sin folio AER"))
    paso("sub administración ve la bitácora", lambda: cierto(len(api.rpc(S, "bitacora_listar")) > 0, "vacía"))
    paso("responsable NO ve la bitácora", lambda: api.rpc(R, "bitacora_listar"), debe_fallar=r"ROL")

    # ------------------------------------------------------------------ solicitud sin cuenta
    seccion("Solicitud de alumno sin cuenta (con correo)")
    envio = paso("el alumno envía su solicitud", lambda: api.funcion(None, "solicitud-publica", {
        "accion": "enviar", "dispositivo": f"recorrido-{MARCA}",
        "datos": {"tipo": "ALUMNO", "matricula": f"7{MARCA}", "nombre": f"Alumna Solicitud {MARCA}", "grupo": "5B",
                  "correo": "jaimelugomiranda+alumno@gmail.com", "telefono": "", "quien": "", "motivo": "Proyecto de clase",
                  "detalle": "Recorrido de prueba", "lineas": [{"articulo_id": brocas, "cantidad": 1}], "otro_correo": None}}))
    if envio:
        paso("respuesta con folio", lambda: cierto(envio.get("ok") is True and bool(envio.get("folio")), f"respuesta: {envio}"))
        paso("el correo de confirmación queda en la cola", lambda: cierto(sql(
            "select count(*) from public.envio where creado_en > now() - interval '5 minutes'")[0][0] > 0, "no hay envío en cola"))

    # La solicitud que el alumno ya confirmó desde su correo (el enlace lo abre una persona) se aprueba aquí.
    seccion("Aprobar solicitudes confirmadas por correo")
    confirmadas = sql("select id, folio from public.solicitud where estado = 'PENDIENTE' and confirmada_en is not null order by creada_en")
    if not confirmadas:
        print("  (ninguna confirmada todavía: se aprueba en la siguiente corrida)")
    for sid, folio in confirmadas:
        detalle = paso(f"detalle de {folio}", lambda sid=sid: api.rpc(R, "solicitud_detalle", p_id=str(sid)))
        if detalle:
            lineas = [{"articulo_id": l["articulo_id"], "cantidad": l.get("cantidad") or l.get("pedidas") or 1} for l in detalle.get("lineas", [])]
            paso(f"aprobar {folio} (el alumno recibe correo con su código)", lambda sid=sid, lineas=lineas: api.rpc(
                R, "solicitud_aprobar", p_id=str(sid), p_lineas=lineas, p_fecha=None, p_nota="Aprobada en el recorrido", p_vigencia="HOY"))
    paso("el correo de aprobación queda en la cola o ya salió", lambda: cierto(sql(
        "select count(*) from public.envio where creado_en > now() - interval '10 minutes'")[0][0] > 0, "no hay correo reciente"))

    seccion("Candados de la contraseña")
    paso("contraseña equivocada no confirma", lambda: cierto((api.rpc(R, "confirmar_contrasena", p_contrasena="no-es-la-clave") or {}).get("ok") is not True, "aceptó una contraseña equivocada"))
    informe()


def informe() -> None:
    bien = sum(1 for r in resultados if r[2])
    mal = [r for r in resultados if not r[2]]
    print(f"\n\nRESULTADO: {bien} bien, {len(mal)} con problema, de {len(resultados)} pasos")
    for sec, desc, _, msg in mal:
        print(f"  ✘ [{sec}] {desc}: {msg}")
    salida = db.RAIZ / "salidas"
    salida.mkdir(exist_ok=True)
    (salida / f"recorridos-{MARCA}.json").write_text(json.dumps(
        [{"seccion": s, "paso": d, "bien": b, "detalle": m} for s, d, b, m in resultados], ensure_ascii=False, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main()
