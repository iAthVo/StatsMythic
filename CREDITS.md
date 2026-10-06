# StatsMythic Credits

StatsMythic is a World of Warcraft addon created by TavoD_Gus_KrG, released
under the MIT License.

## Bundled Libraries

StatsMythic bundles the following community libraries (all under `Libs/`),
each distributed under its own open license — see each library's own project
page for the exact terms:

- **Ace3** (AceAddon-3.0, AceEvent-3.0, AceConsole-3.0, AceDB-3.0,
  AceDBOptions-3.0, AceGUI-3.0, AceConfig-3.0) — the addon framework behind
  the `/stm config` panel, profiles, and slash commands.
- **LibStub** — the tiny library-loader every Ace3 library and most WoW
  addons build on.
- **CallbackHandler-1.0** — event dispatch used internally by Ace3.
- **LibSharedMedia-3.0** + **AceGUI-3.0-SharedMediaWidgets** — the font
  picker used in the Panel tab's "Font" dropdown.
- **LibDataBroker-1.1** + **LibDBIcon-1.0** — the minimap icon / addon
  launcher.

None of these are modified from their original source — StatsMythic only
calls their public APIs.

## Data

StatsMythic does not calculate stat weights, run simulations, or pull data
from any website or external database. All weights come from numbers the
player pastes in themselves, sourced from their own SimulationCraft or
Raidbots runs. Per-season item level reference numbers (used only for the
optional Item Level power bar) were checked against publicly available,
real game data at the time of writing — StatsMythic has no dependency on,
and bundles no code or data from, any other addon.

## Disclaimer

StatsMythic is an independent fan project with no affiliation with or
endorsement by Blizzard Entertainment. World of Warcraft and all related
trademarks are property of Blizzard Entertainment, Inc.
