-- Fase 11: el rol de la selección de robótica.
--
-- Va en su propia migración porque Postgres no deja usar un valor de enum recién creado
-- dentro de la misma transacción; el resto de la fase va en la migración siguiente.

alter type public.rol_usuario add value if not exists 'SELECCION';
