# Gasto de campañas: Google Ads, Meta Ads y Bing Ads

> **Guía de integración para la Fase C.** Cómo traer el coste diario por campaña de
> cada plataforma de anuncios al warehouse, reutilizando el patrón de extracción que ya
> existe, y cómo se une después a los leads que el CRM ya atribuye.
>
> Escrita el 2026-09-14. Empezamos por Google Ads; Meta y Bing siguen el mismo molde.
> El orden y las reglas de "Adding a new source" de `CLAUDE.md` mandan sobre este
> documento donde difieran.

---

## 0. La respuesta corta a "¿ya existe un sistema de extracción para esto?"

**No para Ads. Sí el molde.** No hay ningún cliente ni recurso dlt de Google Ads, Meta o
Bing en el repo. Lo que hay es un patrón probado durante meses con SmartMoving, y cada
plataforma de anuncios es una copia disciplinada de ese patrón:

| Pieza | Dónde vive hoy (SmartMoving) | Qué hace | Copia para Ads |
|---|---|---|---|
| **Cliente con ledger y presupuesto** | `pipeline/sm_pipeline/client.py` | Lee `.env`, registra **cada** llamada en `scripts/api_call_log.jsonl`, corta al llegar al `budget` | `pipeline/ads_pipeline/google_ads.py` |
| **Recurso dlt** | `pipeline/sm_pipeline/source.py` | Define qué se extrae, con **PK compuesta** y `write_disposition="merge"` (idempotente) | `pipeline/ads_pipeline/source.py` |
| **CLI que lo ejecuta** | `pipeline/run.py --job ... --dest postgres` | Crea el pipeline dlt y aterriza en `raw_<source>` | un `--job google_ads` nuevo |
| **Programación** | n8n (`dlt_*` workflows) | Corre el CLI en el droplet a una hora | un workflow `ads_google_daily` |
| **Tipado** | `dbt/models/staging/stg_smartmoving__*.sql` | Dinero a `numeric` en esta frontera, nunca antes | `stg_google_ads__campaign_daily.sql` |
| **Contrato de frescura** | `crm_sync_contract.md` §8 | Qué mecanismo, qué cadencia, qué coste, qué NO puede hacer | una fila por plataforma |

**Y hay un segundo carril que no requiere API:** `report_ingest`. Un CSV que llega por
correo a un alias `*reporting@` aterriza solo, se verifica por conteo y reconstruye dbt.
Para una plataforma sin API — o mientras no tengas credenciales — programas el export
en su UI hacia ese alias y añades una entrada al mapa `REPORTS` del nodo
`Resolve Report Metadata`. Cero infraestructura nueva. Ver §5.

---

## 1. La forma de destino, común a las tres plataformas

Decidirla antes de escribir un solo cliente, para que las tres aterricen igual y un
único modelo de gasto las lea. Una tabla por plataforma, mismo esquema:

```
raw_<platform>.campaign_daily
```

| Columna | Tipo en raw | Nota |
|---|---|---|
| `platform` | text | `google_ads` / `meta_ads` / `bing_ads` |
| `account_id` | text | Customer ID, `act_<id>`, Account Id. **Nunca desnudo** (regla 7): la PK lo incluye |
| `campaign_id` | text | El id de la plataforma. **Esta es la llave del mapeo**, no el nombre |
| `campaign_name` | text | Como lo emite la plataforma hoy. Se renombra; se guarda para leerlo, no para unir |
| `campaign_status` | text | |
| `date` | date | Día de la plataforma, en la zona de la cuenta |
| `cost` | como llegue | Micros, string, float — **tal cual**. A `numeric` en staging |
| `currency` | text | |
| `impressions`, `clicks`, `conversions` | como lleguen | |
| `_extracted_at` | timestamptz | |
| `_payload` | jsonb | La fila entera de la respuesta, por si mañana hace falta una columna que hoy no se promovió |

**PK: `(platform, account_id, campaign_id, date)`. `write_disposition="merge"`.**
Re-ejecutar el mismo día sobreescribe la fila, no la duplica — y eso importa porque
**las plataformas reescriben el coste de los últimos días** (Google 2-3 días por
ajustes; las conversiones hasta 30). La ventana de extracción tiene que solapar.

De ahí hacia arriba, idéntico para las tres:

```
raw_<platform>.campaign_daily
   -> staging.stg_<platform>__campaign_daily      (cost -> numeric, date typed)
   -> marts.fct_campaign_spend_daily              (une las tres + dim_ad_campaign_map
                                                    + fct_campaign_daily, aplica el reparto)
   -> serving.campaign_daily_v1                   (cuando haya consumidor)
```

---

## 2. Google Ads — por dónde empezamos

### 2.1 Credenciales: lo que hay montado (2026-09-14)

Se eligió **cuenta de servicio de Google Cloud + Manager Account (MCC)**, no el flujo
OAuth de escritorio con refresh token que describía la primera versión de esta guía. La
razón: una cuenta de servicio no depende de la sesión de ninguna persona, no caduca a
los 6 meses sin uso, y Google Ads acepta añadirla **directamente como usuario del
Manager** (sin delegación de dominio). Un solo acceso en el Manager cubre todas las
child accounts presentes y futuras.

| Pieza | Dónde vive | Estado |
|---|---|---|
| **Developer token** | API Center del Manager `2797921560` | Obtenido. ⚠️ Nivel **"test accounts only"** hasta que Google apruebe *Explorer/Basic access* - ver abajo |
| **Cuenta de servicio** | Proyecto GCP `ecomovers-datawarehouse`, email `datawarehouse-dev-tem@…iam.gserviceaccount.com` | Añadida como usuario del Manager. `ListAccessibleCustomers` la ve |
| **Clave JSON de la cuenta de servicio** | `.env`, **base64 en una sola línea** (`GOOGLE_ADS_SERVICE_ACCOUNT_JSON_B64`) | El fichero `.json` original se eliminó del repo; `.gitignore` bloquea cualquier clave GCP futura |
| **Login customer id** | `.env` → `GOOGLE_ADS_LOGIN_CUSTOMER_ID=2797921560` (el Manager) | Fijo |

```
GOOGLE_ADS_DEVELOPER_TOKEN=
GOOGLE_ADS_LOGIN_CUSTOMER_ID=2797921560
GOOGLE_ADS_SERVICE_ACCOUNT_JSON_B64=
```

`deploy/sync_droplet.py` copia las tres al `.env` del droplet (chmod 600) en cada sync.
El cliente decodifica el JSON **en memoria**; nunca lo escribe a disco. Librería:
`google-ads>=32` en `pipeline/requirements.txt`; el sync la instala.

**El único bloqueo, y es de Google — y desde el 2026-09-09 se resuelve en Cloud
Console, NO en el API Center del Manager.** Ese día Google retiró el developer token
como unidad de acceso: se sigue enviando en la cabecera pero la API lo ignora, y el
nivel (Test / Explorer / Basic / Standard) **se concede al proyecto de Google Cloud**.
El nuestro es `ecomovers-datawarehouse`, el que posee la cuenta de servicio, y nace en
nivel Test - de ahí `CLOUD_PROJECT_NOT_APPROVED_FOR_PRODUCTION` en cada lectura real.
Un "Explorer" concedido en el API Center del Manager no cambia nada (medido: 30 min de
sondeo tras verlo en la UI, mismo error).

Cómo se sube de nivel (documentación oficial, `developers.google.com/google-ads/api/docs/access-levels`):

1. Cloud Console, proyecto `ecomovers-datawarehouse` → confirmar *Google Ads API*
   habilitada (eso da Test).
2. `console.cloud.google.com/google/ads-apis/overview` → "Upgrade access level" →
   **Apply for access**. **Explorer**: sin verificación de marca, minutos; 2.880
   operaciones/día en producción. Nuestra corrida diaria usa ~2; sobra.
3. **Basic** (15.000/día) exige antes *brand verification* del proyecto; revisión
   automática en minutos. Solo si algún día hace falta.
4. Una cuenta de facturación en prueba gratuita o suspendida bloquea la aprobación.

Ya no hace falta Manager para usar la API; el nuestro se conserva porque es la forma
de leer todas las children con un solo acceso. El cliente OAuth "web" (client_secret)
NO es necesario para el flujo de cuenta de servicio.

### 2.1a Manager y child accounts: cómo se identifica cada fila

- Toda petición lleva `login-customer-id = Manager` y `customer_id = child`.
- **Las child accounts se descubren en cada corrida** (`SELECT … FROM customer_client`
  bajo el Manager). Añadir una cuenta en Google Ads basta para que se extraiga al día
  siguiente. **No hay lista de cuentas en código ni en `.env`.**
- Cada fila de `raw_google_ads.campaign_daily` lleva `account_id` (el Customer ID de la
  child), `account_name` y `account_time_zone`. La PK es
  `(platform, account_id, campaign_id, date)`: un Campaign ID repetido entre cuentas
  nunca colisiona.
- `raw_google_ads.accounts` guarda el árbol completo (Manager nivel 0, children nivel 1)
  para que "¿de qué cuentas estamos leyendo?" sea una consulta y no un recuerdo.
- Lo único que necesita una cuenta nueva es **un backfill histórico de una vez**:
  `run_ads.py --platform google_ads --dest postgres --account <id> --from 2023-01-01`,
  porque la ventana diaria solo alcanza 30 días atrás.

### 2.2 La consulta: GAQL, una sola llamada por día extraído

Google Ads no tiene endpoints REST por recurso; tiene un lenguaje de consulta. La
consulta que da exactamente la tabla de §1:

```sql
SELECT
  segments.date,
  campaign.id,
  campaign.name,
  campaign.status,
  campaign.advertising_channel_type,
  metrics.cost_micros,
  metrics.impressions,
  metrics.clicks,
  metrics.conversions,
  customer.currency_code
FROM campaign
WHERE segments.date BETWEEN '2026-08-15' AND '2026-09-14'
  AND campaign.status != 'REMOVED'
```

Se ejecuta con `GoogleAdsService.search_stream`. Devuelve una fila por
(campaña, día). **`cost_micros` es el coste × 1.000.000** — se guarda tal cual en raw
y staging divide: `cost_micros / 1000000.0`.

`advertising_channel_type` (SEARCH, DISPLAY, VIDEO, PERFORMANCE_MAX, LOCAL_SERVICES…)
merece promoverse: distingue Google Ads de **Local Services Ads** (Google Guarantee),
que en el CRM ya son familias distintas (`Google Ads` vs `Google LSA`).

### 2.3 El cliente: `pipeline/ads_pipeline/google_ads.py`

Espejo de `sm_pipeline/client.py`. Las obligaciones que hereda, sin excepción:

- **`load_env()`** lee el `.env`; las credenciales nunca se pasan por línea de comandos.
- **Cada llamada se registra** en `scripts/api_call_log.jsonl` con `source: "google_ads"`,
  la consulta (sin credenciales), filas devueltas, ms y estado. El ledger es uno solo para
  todas las fuentes; es lo que permite saber quién gasta qué.
- **`budget`** por sesión. Google Ads es gratuito y una extracción diaria cuesta ~1
  llamada, así que aquí el presupuesto es un seguro contra un bucle, no contra la cuota.
- **Retry con backoff** ante `RESOURCE_EXHAUSTED` y errores transitorios; nunca ante
  `AUTHENTICATION_ERROR` (un token caducado no se arregla reintentando).

### 2.4 El recurso dlt: `pipeline/ads_pipeline/source.py`

```python
@dlt.resource(
    name="campaign_daily",
    primary_key=("platform", "account_id", "campaign_id", "date"),
    write_disposition="merge",
)
def google_ads_campaign_daily(date_from: str, date_to: str):
    ...
```

**Ventana por defecto: los últimos 30 días, siempre.** No "desde la última corrida".
Google reescribe el coste de los 2-3 días anteriores y las conversiones hasta 30 días
atrás; con `merge` y una ventana solapada, la fila de un día se corrige sola en cada
corrida. Es la misma lógica por la que el sweep de SmartMoving usa una ventana y no un
cursor. Un `--from/--to` explícito para el backfill histórico.

`dataset_name="raw_google_ads"`, `pipeline_name="google_ads_raw"`.

### 2.5 CLI y programación

- **CLI propia**: `pipeline/run_ads.py --platform google_ads --dest postgres`
  (últimos 30 días, todas las children). `--from/--to` para backfill (troceado en
  tramos de 92 días), `--account <id>` repetible para acotar, `--list-accounts` para
  ver el árbol sin cargar nada. No es un `--job` de `run.py`: ese CLI itera instancias
  SmartMoving y acepta `--quotes/--ids/--sweep-only`, banderas sin sentido aquí.
- n8n: **`ads_google_daily`** (id `fy77bRPxYnCI1uc4`, carpeta Datawarehouse), 06:00 PT,
  nodo SSH → `flock` → `run_ads.py` → `Assert Exit Code` → `errorWorkflow`
  `datawarehouse_error_handler`. **Creado inactivo**: publicar tras la primera corrida
  manual correcta (§2.7). Un cron que falla cada día con el mismo error de acceso es
  ruido, no vigilancia.
- Tras la primera carga real: añadir `google_ads` a `pipeline_heartbeat.py` como
  mecanismo, `max(_extracted_at) from raw_google_ads.campaign_daily`, umbral 30 h.
  Antes no: alertaría a diario sobre una tabla vacía.

### 2.6 Cuota

Distinta de SmartMoving y **no es una restricción**: Basic access da 15.000 operaciones
por día; una extracción diaria cuesta 1 llamada al árbol + 1 por child account. Se registra en el ledger
igual, porque la regla es "toda llamada se registra", no "las caras se registran".

### 2.7 La prueba de que funciona

Ejecutada el 2026-09-14 (resultados en §8). Dos gotchas de la librería v25 que costaron
la primera corrida y ya están resueltas en el cliente: con `use_proto_plus=False` (el
default) los mensajes son protobuf puro — los enums llegan como **int** (se resuelven
por `DESCRIPTOR`) y la fila no tiene `._pb` (`MessageToDict(row)` directo).

1. Una corrida manual de **1 día** con `--budget 2`. Comparar `sum(cost)` de ese día
   contra la cifra que muestra la UI de Google Ads para el mismo día y cuenta. Deben
   coincidir al centavo (misma zona horaria de cuenta).
2. Correr el mismo día **dos veces**. `count(*)` en raw no cambia. Si cambia, la PK está
   mal.
3. Entonces, y solo entonces, el backfill **desde 2023-01-01** (decisión de Nicolas,
   2026-09-14: el histórico completo de la cuenta, si tiene campañas desde entonces).
   `run_ads.py` lo trocea solo en tramos de 92 días. Luego publicar `ads_google_daily`.

---

## 3. Meta Ads (Facebook + Instagram)

Mismo molde; lo que cambia es la autenticación y la forma de la respuesta.

**Credenciales.** Una app en *Meta for Developers* (App ID + secret) con el producto
*Marketing API*; y — esto es lo importante — un **System User** creado en *Business
Manager* con permiso `ads_read` sobre la cuenta publicitaria. Su token es **de larga
duración y no caduca**, a diferencia del token de usuario que caduca en 60 días. El Ad
Account ID va con prefijo: `act_1234567890`.

```
META_APP_ID=
META_APP_SECRET=
META_SYSTEM_USER_TOKEN=
META_AD_ACCOUNT_ID=act_1234567890
```

**La llamada.** Graph API, endpoint de *insights* a nivel campaña, un día por fila:

```
GET https://graph.facebook.com/<versión>/act_<id>/insights
    ?level=campaign
    &fields=campaign_id,campaign_name,spend,impressions,clicks,actions,account_currency
    &time_increment=1
    &time_range={"since":"2026-08-15","until":"2026-09-14"}
    &limit=500
```

Paginación por `paging.next` (un cursor; seguirlo hasta que no venga). Límite de tasa
por cuenta, expuesto en la cabecera `x-business-use-case-usage`; el cliente la lee y
frena antes del 429.

**Dos trampas que Google no tiene:**
- **`spend` llega como string** (`"123.45"`). Tal cual a raw; `numeric` en staging.
- **`actions` es un array** de `{action_type, value}`. "Conversiones" no es un número,
  es *cuál* action_type cuentas — para leads suele ser `lead` u
  `offsite_conversion.fb_pixel_lead`. Se guarda el array entero en `_payload` y staging
  extrae el tipo elegido. Esa elección es negocio, no código: dejarla documentada en el
  modelo.

**Ventana**: 30 días solapados, misma razón. Meta también reescribe.

---

## 4. Bing Ads (Microsoft Advertising)

Mismo molde, pero **el coste no sale de una consulta: sale de un reporte asíncrono**, y
eso cambia la forma del cliente.

**Credenciales.** Developer token (Microsoft Advertising → *Developer Token*), una app
en *Microsoft Entra* para OAuth (client ID, secret, refresh token — mismo baile que
Google), y dos ids: **Customer ID** (la organización) y **Account ID** (la cuenta).

```
BING_ADS_DEVELOPER_TOKEN=
BING_ADS_CLIENT_ID=
BING_ADS_CLIENT_SECRET=
BING_ADS_REFRESH_TOKEN=
BING_ADS_CUSTOMER_ID=
BING_ADS_ACCOUNT_ID=
```

Librería: `pip install bingads` (SDK oficial, expone los servicios SOAP).

**El flujo.** Con el *Reporting Service*:

1. `SubmitGenerateReport` con un `CampaignPerformanceReportRequest`:
   `Aggregation = Daily`, columnas `TimePeriod, AccountId, CampaignId, CampaignName,
   CampaignStatus, Spend, Impressions, Clicks, Conversions`, rango de fechas.
2. `PollGenerateReport` hasta `Status = Success` (segundos a minutos).
3. Descargar la URL: un **ZIP con un CSV**. Descomprimir, parsear, aterrizar.

Tres llamadas y una descarga por corrida. El cliente registra las tres. El CSV, en raw
igual que las otras dos — misma tabla, mismo esquema de §1.

Es exactamente el flujo que `report_bot` + `report_ingest` ya hacen con SmartMoving
(pedir un reporte, esperar, descargar, aterrizar), solo que aquí la API lo permite sin
bot. Si el SDK da problemas, **el plan B es el carril de correo de §5**: Microsoft
Advertising sí permite programar este mismo reporte por email.

---

## 5. Plataformas sin API (o sin credenciales todavía): el carril de correo

Ya existe y está endurecido por tres caídas. Para cualquier plataforma que pueda
**programar un export CSV por correo**:

1. En la UI de la plataforma, programar el reporte diario de rendimiento por campaña
   hacia `reporting@ecomoversmoving.com` (o un alias nuevo `ads.reporting@`).
2. Añadir al mapa `REPORTS` en `deploy/n8n_report_ingest_resolve_node.js` una entrada
   con el patrón del nombre de archivo, la tabla destino `raw_<platform>.campaign_daily`
   y la columna de llave natural (`Campaign ID` + `Date`).
3. `report_ingest` hace el resto: aterriza, verifica por conteo, papelera, rebuild.

**Vale para Yelp Ads** (su API de anunciantes está restringida a partners), para
Nextdoor, Thumbtack, Angi, y para empezar con Google/Meta/Bing **antes** de tener el
token aprobado. El dato llega igual; lo que se pierde es la reescritura automática de
días pasados, así que la ventana del export debe ser también de 30 días para que el
`ON CONFLICT` la corrija.

---

## 6. La unión: `dim_ad_campaign_map`

El punto difícil de la fase, y no es técnico. La plataforma dirá
`[Search] Moving - Snohomish - Exact`; el CRM dice `Google Ads Snohomish`. **No
coinciden y no van a coincidir solos.**

Seed en `dbt/seeds/dim_ad_campaign_map.csv`:

| columna | qué es |
|---|---|
| `platform` | `google_ads` / `meta_ads` / `bing_ads` |
| `account_id` | la cuenta, para que el id de campaña nunca vaya desnudo |
| `platform_campaign_id` | **la llave**. Los nombres se renombran; los ids no |
| `platform_campaign_name` | solo para leer al editar el CSV |
| `campaign` | = `dim_referral_source.source_clean`, ej. `Google Ads — Snohomish` |
| `valid_from`, `valid_to` | por si una campaña de plataforma cambia de destino en el CRM |
| `notes` | |

Reglas:
- **Una campaña de plataforma que no esté en el seed deja su gasto sin atribuir.**
  Visible en `marts.mart_unmapped_ad_spend`, nunca perdido, nunca repartido a ciegas.
  Ese mart es la cola de revisión, igual que `mart_unmatched_report_rows` lo es para
  los reportes.
- **Varias campañas de plataforma pueden apuntar a una misma `campaign` del CRM.**
  Google suele tener Search + Performance Max para la misma geografía; en el CRM son una
  sola fuente. El seed lo permite; el gasto se suma.
- **Test**: `platform_campaign_id` único por plataforma y cuenta; `campaign` debe existir
  en `dim_referral_source.source_clean` (un `relationships` test).

---

## 7. De gasto a KPI: `fct_campaign_spend_daily`

Ya está preparado del lado de los leads. `marts.fct_campaign_daily` lleva en cada fila
`leads_received` y `campaign_day_leads_total`, así que la atribución por línea de
negocio — la regla de Nicolas, por lead y no por línea nominal, sumando ambas
instancias — es una multiplicación:

```
coste_atribuido = gasto_campaña_día × leads_received / campaign_day_leads_total
```

y suma de vuelta al gasto exacto. De ahí:

| KPI | Fórmula | Denominador |
|---|---|---|
| **CPL** — coste por lead | gasto / `leads_received` | todos los leads, incluidos bad leads: el clic se pagó igual |
| **CPA** — coste por adquisición | gasto / `booked_leads` | reservados |
| **Spend** | gasto, por familia / campaña / línea / periodo | — |
| **CER** — Cost Efficiency Ratio | gasto / `invoiced_value` | ingreso facturado atribuido a esos leads |

⚠️ **CER y CPA sufren el mismo sesgo de madurez que la conversión**: un lead de la
semana pasada aún no ha facturado, así que el CER de los últimos 60 días leerá alto.
`open_leads` viaja en cada fila para hacerlo visible. Excluir la cola reciente de
cualquier comparación entre campañas.

⚠️ **Comercial se lee por su fila de campaña**, ignorando el reparto por línea. Es una
decisión de reporte, no está en el modelo.

---

## 8. Orden de trabajo — checklist

Empezar por Google Ads. No pasar al siguiente punto sin cerrar el anterior.

- [x] Credenciales en `.env` (laptop y droplet vía sync), JSON eliminado del repo, `.gitignore` ampliado. *(2026-09-14)*
- [x] `google-ads>=32` en `pipeline/requirements.txt`; el sync lo instala en el droplet.
- [x] `pipeline/ads_pipeline/google_ads.py` — cliente con ledger, presupuesto, retry, descubrimiento de children.
- [x] `pipeline/ads_pipeline/source.py` — `accounts` + `campaign_daily`, PK compuesta, merge, ventana 30 días, backfill en tramos.
- [x] `pipeline/run_ads.py` — CLI. Probado con fila sintética en DuckDB: tipos correctos, doble corrida sin duplicar.
- [x] `sql/40_raw_google_ads.sql` — esquema raw pre-creado con la forma exacta de dlt; aplicado en el droplet.
- [x] `stg_google_ads__accounts` + `stg_google_ads__campaign_daily` con tests; construyen (vacíos) en el droplet.
- [x] Workflow n8n `ads_google_daily` creado, **inactivo**.
- [x] Fila en `crm_sync_contract.md` §6.
- [x] Explorer access concedido al proyecto de Cloud `ecomovers-datawarehouse` *(2026-09-14, Nicolas)*.
- [x] `--list-accounts`: Manager `NicolasCortesGoogleAds` (2797921560) → child **`PNW Moving` (1776272460)**, `America/Los_Angeles`, USD.
- [x] Prueba §2.7: 1 día (2026-09-13) → 1 fila, $37.01, doble corrida sin duplicar. **Pendiente de Nicolas: confirmar $37.01 / 2 clics / 33 impresiones contra la UI ese día.**
- [x] Backfill desde 2023-01-01: **413 campaign-days, $39.181, 6 campañas, 2024-08-16 → hoy**. Nada en 2023 ni en 2024 H1: la cuenta no tenía campañas. Corrida diaria encima del backfill: 413 = 413 llaves, merge verificado en Postgres.
- [x] `ads_google_daily` publicado (06:00 PT). `google_ads` en el heartbeat, umbral 30 h, verde.
- [ ] Añadir las otras tres child accounts al Manager → aparecen solas; backfill de cada una con `--account <id> --from 2023-01-01`.
- [ ] `dim_ad_campaign_map.csv` — **con `(platform, account_id, campaign_id)` reales** (Nicolas). Con los datos ya en raw, `select distinct account_id, account_name, campaign_id, campaign_name from staging.stg_google_ads__campaign_daily` es la lista de partida.
- [ ] `marts.fct_campaign_spend_daily` + `mart_unmapped_ad_spend`.
- [ ] Repetir §3 (Meta) y §4 (Bing) sobre el mismo `ads_pipeline/` — cada uno es un
      cliente y un recurso más, no una arquitectura más.

---

## 9. Lo que NO hacer

- **No un segundo ledger.** Todas las fuentes escriben en `scripts/api_call_log.jsonl`.
- **No dividir el coste en el pipeline.** El reparto es lógica de negocio y vive en dbt.
  Raw guarda lo que la plataforma dijo.
- **No unir por nombre de campaña.** Por id, con el seed. Un nombre renombrado en la
  plataforma partiría la serie histórica en dos.
- **No un cursor incremental.** Ventana solapada + merge. Las plataformas reescriben.
- **No adoptar un conector de terceros** (Fivetran, Airbyte) para tres tablas. Es un
  servicio más que operar, y el molde que ya existe cuesta menos que aprenderlo.
