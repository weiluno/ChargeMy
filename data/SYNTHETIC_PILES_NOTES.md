# ChargeMY synthetic charging-pile datasets

## Demo first

- `demo_mevnet_stations.csv` contains 20 sourced MEVnet stations: 10 in Kuala Lumpur, 6 in Selangor, and 4 in Perak. Each has at least one existing charger count in MEVnet.
- `demo_synthetic_piles.csv` contains only synthetic **existing** piles for those demo stations, so every row uses an app-supported operational state. Use this first for the assignment demonstration.

## Full version

- `mevnet_stations.csv` remains the full source-attributed station dataset.
- `full_synthetic_piles.csv` contains one synthetic pile row for every sourced existing and proposed charger count.

## Important attribution rule

MEVnet is the source of the station location and the aggregate charger counts only. The following fields in both synthetic-pile files are deliberately made up for the ChargeMY assignment prototype and must be described as simulated: `connector_type`, `power_kw`, `price_per_kwh`, and `operational_state`.

`deployment_stage=planned` is for a MEVnet proposed charger. Before importing those rows into the current app, either exclude them or change them to a supported operational state only after the station is actually commissioned.

Run `powershell -ExecutionPolicy Bypass -File tools\generate_synthetic_piles.ps1` to rebuild both synthetic datasets after refreshing MEVnet data.
