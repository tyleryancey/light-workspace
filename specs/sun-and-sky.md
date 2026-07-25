# CLAUDE.md — Sun & Sky (Light Phone 3 tool)

Sunrise/sunset, golden hour, blue hour, moon phase, and tonight's visible planets — offline astronomy math against a saved position. Complements the LP3's 50 MP camera (golden hour is a photographer's question) and the go-outside ethos. Small, zero category risk, charming.

**One pivot from the original pitch:** "against GPS position" is not possible in this SDK snapshot — no location access path exists for tool code (00-ASSESSMENT.md §1.2). v1 uses the weather example's typed-location pattern: geocode once, store lat/lon, then be **pure offline forever**. When the SDK ships a location surface, add "use my position" as a one-line upgrade.

**Division of labor:** this doc is the plan of record; Claude Code owns compile–run–debug. SDK source outranks this doc.

## Verified SDK facts this tool is built on

- Typed-location pattern, whole cloth from `examples/weather`: `LightTextInputEditor` for input, Ktor(OkHttp) client → open-meteo geocoding (`https://geocoding-api.open-meteo.com/v1/search?name=…&count=5`), lat/lon + display name persisted in the shared `DataStore` (`DEFAULT_DATASTORE`), `onScreenShow` refresh hook. Copy its ViewModel state-machine shape (Loading / Content / LocationInput modes, cancelable re-entry).
- Ktor + OkHttp + kotlinx-serialization allowlisted; INTERNET permission allowlisted. Network is used **only** during location setup.
- Sandbox recap: no Context/getSystemService/etc.; `java.time` yes, `kotlinx-datetime` no; deps allowlist per 00-ASSESSMENT.md §1.1.
- Timezone: `java.time.ZoneId.systemDefault()` — the phone's zone. If the saved location is far from the phone's zone the times shown are still *in the phone's zone*; print the zone abbreviation once in the header rather than solving remote-timezone math in v1.

## lighttool.toml

```toml
[tool]
id          = "dev.tyler.sunandsky"
label       = "Sun & Sky"
versionCode = 1
versionName = "0.1.0"
permissions = ["android.permission.INTERNET"]   # geocoding at setup only
serverPackage = "com.thelightphone.sdk.emulator"   # "com.lightos" on the LP3
```

## Architecture

```
tool/src/main/kotlin/dev/tyler/sunandsky/
  ToolEntryPoint.kt            empty hooks
  astro/                       ← pure JVM, zero Android imports, the heart of the tool
    Julian.kt                  civil ↔ Julian day, Julian centuries T
    Sun.kt                     solar position + event solver
    Moon.kt                    phase, illumination, (M3) low-precision position
    Planets.kt                 (M3) Schlyter low-precision positions
    Events.kt                  altitude-crossing search shared by sun/moon
  geo/GeocodeApi.kt            open-meteo search (weather-example clone, trimmed)
  data/Prefs.kt                DataStore keys: lat, lon, name
  ui/
    HomeScreen.kt              @InitialScreen — today's card
    LocationScreen.kt          typed search → pick → save
tool/src/test/kotlin/.../astro/  AstroTest.kt   ← pure-JVM gate with pinned vectors
```

## Astronomy spec (`astro/` — all doubles, all UTC internally)

**Solar position** per the NOAA solar calculator equations (Meeus-derived). From Julian centuries T: geometric mean longitude L₀, mean anomaly M, equation of center C, true → apparent longitude λ (aberration + nutation-in-longitude approx), mean obliquity ε with the standard correction; declination `δ = asin(sin ε · sin λ)`; equation of time. Solar noon from EoT + longitude; event times from the hour angle `cos H = (sin h₀ − sin φ sin δ) / (cos φ cos δ)`, iterating once with the recomputed δ at the estimated time (NOAA's refinement step) for ±1 min accuracy.

**Event altitudes h₀ (definitions to hardcode and document in-app):**
- Sunrise/sunset: −0.833° (refraction + semidiameter)
- Civil twilight: −6°
- **Blue hour: sun altitude in [−6°, −4°]** · **Golden hour: [−4°, +6°]** — compute the four crossing times morning and evening from the same solver.
- `cos H` out of [−1, 1] → polar day/night; render "Sun does not set/rise today" (test this branch; a Tromsø user will exist).

**Moon phase (M1):** synodic month 29.530588853 d from epoch new moon 2000-01-06 18:14 UTC. `age = (now − epoch) mod synodic`; illumination `≈ (1 − cos(2π·age/synodic))/2`; 8 named buckets (New at age < 1.0 or > 28.5, etc. — pick boundaries, pin them in tests). Render the phase as a **drawn glyph** (Canvas: two arcs) — monochrome-native, no emoji.

**Moonrise/set + planets (M3, not M1):** implement Paul Schlyter's low-precision method (stjarnhimlen.se/comp/ppcomp.html) — Keplerian elements → ecliptic → equatorial → topocentric alt/az. Moon events via `Events.kt` crossing search at h₀ = −0.566° over the local day in 10-min steps + bisection. "Visible tonight" for Mercury/Venus/Mars/Jupiter/Saturn: altitude > 10° at any point between (sunset + 30 min) and (sunrise − 30 min), and solar elongation > 15°. Accuracy target ±1–2° / ±10 min — plenty for "look up tonight."

**ISS passes: explicitly OUT of v1.** Requires live TLEs (Celestrak fetch, weekly `@LightJob`) plus an SGP4 propagator port and sunlit-satellite/dark-observer logic — a project of its own. Leave `astro/Iss.kt` as a documented stub; revisit after the vetting window.

## Test gate (M1 — no UI before green)

Pin vectors **generated fresh from authoritative sources** (do not trust numbers from memory — mine included):
1. NOAA solar calculator (gml.noaa.gov/grad/solcalc): sunrise/sunset/solar-noon for St. Louis (38.627, −90.199) on 2026-06-21, 2026-12-21, 2026-03-20 → assert ±3 min.
2. One high-latitude polar-day case (Tromsø, June) → the no-event branch.
3. Civil-twilight vectors from the same calculator → ±3 min; golden/blue hour internally consistent (ordering, containment).
4. Moon: the four principal phase dates nearest to July 2026 from a published almanac → age model within ±0.7 d; illumination at quarters ≈ 0.5 ± 0.05.
5. (M3) Planet alt/az spot-checks vs Stellarium/JPL Horizons for two datetimes → ±2°.

Record every vector's source + retrieval date in a comment block at the top of `AstroTest.kt`.

## UI spec

Monochrome enforced in-app (`LightTheme`/`LightThemeTokens`, dual palette, no color literals). Typography does the design work.

- **Home (the whole product):** location name + zone · a vertical **timeline of today**: Blue hour → Sunrise → Golden hour end / Golden hour start → Sunset → Blue hour end, each as time + label, with a subtle "now" marker between rows. Below: day length ("14 h 51 m, +1 m vs yesterday" — the delta is the charming line; compute yesterday too). Below: moon glyph + phase name + illumination %. (M3 adds: moonrise/set, "Tonight: Venus W, Jupiter SE".) Everything fits one screen; no scrolling to see tonight.
- **Location:** top-bar pencil → typed search (weather-example flow) → result list → save → recompute. First launch goes straight here (`canCancel = false` pattern).
- Settings: none in v1. No notifications, no widgets — you open it when you wonder.

## Milestones · definitions of done

- **M0** — repo builds on AVD; PAT property names confirmed; `minSdk` confirmed.
- **M1 Astro core (pure JVM)** — sun events + twilight bands + moon phase, `:tool:test` green on pinned vectors. **Gate.**
- **M2 UI** — setup flow + Home timeline on AVD; relaunch offline (airplane-mode AVD) renders instantly from stored lat/lon.
- **M3 Moon events + planets** — same gate discipline (vectors first), then two lines added to Home.
- **M4 Polish + submission** — day-length delta, polar edge copy, README, license, defense paragraph.

## Vetting defense (seed)

Sun & Sky touches the network exactly once — to turn a typed place name into coordinates at setup — and is thereafter a pure offline calculator. It has no feed, no refresh loop, no notifications, and a single screen whose entire purpose is to send the user outside at the right moment. It extends the phone's own camera and go-outside ethos with mathematics, not content.

## Sharp edges

- Do all math in UTC; convert at the display edge only. Off-by-one-day bugs live at the local-midnight boundary — test a date where a UTC event lands on the neighboring local day.
- `asin/acos` domain: clamp inputs to [−1, 1] before calling (floating-point drift at extremes).
- Cache the day's computed events in the ViewModel; recompute on `onScreenShow` only when the date or location changed — the LP3's SoC is modest and the math is cheap, but don't recompute per recomposition.
- Geocoding failure/no-network at setup: weather example's error-modal pattern; never block the app if a location is already stored.
