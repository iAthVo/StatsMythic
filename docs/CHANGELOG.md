# Historial de cambios — StatsMythic

Versionado `X.Y.Z`: X = cambios grandes, Y = nuevas capacidades o ajustes
visuales, Z = correcciones menores.

## 1.13.5

Repo de GitHub recreado desde cero después de varias vueltas de prueba y
error con el disparador de releases por tag. Confirmado que el workflow en
sí funciona de punta a punta (permisos, API key de CurseForge, packager)
vía disparo manual. Versión limpia para el primer tag real de este repo.

## 1.13.4

Encontrada la causa real de que el workflow no disparara: los permisos de
Actions del repositorio estaban restringidos (no en "Allow all actions and
reusable workflows"). Corregido — este es el primer tag con el que se
espera que la release automática funcione de verdad.

## 1.13.3

Primer tag de release real (el intento anterior, v1.13.2, no disparó el
workflow de GitHub Actions por una razón no identificada — se borró y se
volvió a intentar limpio).

## 1.13.2

Agregado `X-Curse-Project-ID` al `.toc` — necesario para que el workflow
de GitHub Actions pueda subir los releases a CurseForge.

## 1.13.1

Preparación del repositorio para publicación: comentarios de código
bilingües (inglés/español), licencia MIT, `CREDITS.md`, changelog e
historial de desarrollo movidos a `docs/` (las notas internas quedan solo
en la PC del autor, nunca se publican), y `.gitignore`/`.pkgmeta` listos
para GitHub/CurseForge. Sin cambios de comportamiento para el jugador.

## 1.13.0

- Tooltip de comparación simplificado: solo escala y porcentaje (ej.
  "Lock: +14.6%"), sin el puntaje en bruto.
- Leech y Avoidance ahora también se muestran como barra (estática,
  siempre llena) en modo "Barras de poder".
- Nuevo toggle **"Mostrar en tooltip"** por escala guardada — permite ver
  la comparación de varias escalas a la vez en el tooltip de un objeto,
  sin tener que cambiar cuál está activa.

## 1.10.0 – 1.12.2

- **Item Level como barra de poder**, con relleno real (ilvl equipado ÷
  máximo de temporada) y color degradado dinámico (blanco → azul →
  morado → naranja, usando los colores de calidad reales del juego)
  según la racha de mejora correspondiente.
- **Primary Stat** también se muestra como barra estática cuando "Barras
  de poder" está activo.
- Nuevos controles independientes para las barras: alto, espacio entre
  barras, espacio entre la etiqueta y la barra, y la opción de dibujar
  el texto encima de la barra en vez de en su propia fila.
- Orden de filas del panel ajustado (Item Level antes de Primary Stat).
- Nuevo comando `/stm debugseason`, para apoyar una futura detección
  automática de temporada.

## 1.9.0

- Las etiquetas de las barras de poder se separan en dos partes
  independientes: el lado "Personaje" sigue la opción de alineación de
  texto; el lado "Recomendado" sigue el ancho real de la barra.

## 1.8.0

- **Barras de poder**: nuevo modo de visualización opcional para
  Crit/Haste/Mastery/Versatility — se muestran como una barra que se
  llena según Personaje ÷ Recomendado, con destello animado en el borde
  de avance y una franja que marca cuando se supera el 100%.

## 1.7.0

- Corregido: el valor "Esperado" ya no cambia al equipar un objeto
  distinto — el total que se reparte entre los 4 stats secundarios se
  congela y solo se recalcula al cambiar de escala, o a mano con
  `/stm recalc`.

## 1.4.0 – 1.6.1

- Corregido un bug real de perfiles compartidos entre personajes
  (posición y apariencia del panel se pisaban entre personajes).
- Agregada la pestaña "Perfiles" a `/stm config`.
- Nuevo comando `/stm errors` para copiar los últimos errores de Lua.
- Corregido un crash al abrir la configuración, causado por una función
  de la API removida en un parche de WoW.

## 1.0.0 – 1.3.2

- Primera versión estable tras una ronda larga de ajustes de layout en
  la pestaña Panel.
- Agregados Leech y Avoidance (sin "Recomendado", son tiradas extra
  opcionales).
- Escalas de pesos por personaje, con lista visible de todas las
  guardadas, renombrado, y pegado directo del resultado de SimC/Raidbots
  (con o sin nombre).

## 0.1.0 – 0.9.4

Primera versión funcional:

- Panel de stats en vivo (Personaje/Recomendado) y comparación de equipo
  en el tooltip de objetos, usando la API moderna de Blizzard
  (`C_Item.GetItemStats`).
- Soporte para Weapon DPS / Off Hand Weapon DPS, leídos del tooltip del
  arma (sin función de API directa para esto).
- Compatibilidad con GW2_UI en el panel de personaje nativo.
- Personalización completa del panel (tamaño, fuente, colores, formato,
  posición) vía perfiles de AceDB.
- `/stm config` organizado en pestañas.
