# 10 MEVnet locations per Malaysian state/territory

`mevnet_10_per_state_import.csv` contains 160 rows: 10 PLANMalaysia MEVnet
station locations for each of Malaysia's 13 states plus Kuala Lumpur, Labuan,
and Putrajaya. The selection prioritises MEVnet records with an existing
charger count. Where MEVnet has fewer than 10 existing locations (notably
Perlis and Labuan), proposed locations are included so the assignment can
demonstrate nationwide discovery.

The station name, coordinates, local authority, charger counts, status, source
record ID, and `data_as` value are sourced from the checked-in MEVnet export.
MEVnet does **not** publish individual pile connector, power, price, or live
state records. The single `Bay 01` row attached to each station is therefore
explicitly simulated (`data_type=simulated_pile_assignment_prototype`) and is
set to `available` for demo testing. It must not be presented as live CPO
telemetry.

Source: [PLANMalaysia MEVnet](https://portaldev.planmalaysia.gov.my/portal/apps/dashboards/bba366dc3d144510bfd7cda771795f3d)

## Import

Sign in as an administrator, open **Admin → Import**, and select
`mevnet_10_per_state_import.csv`. The file has 160 rows, below the app's 500
row import limit. Existing records are updated by `station_id`; it does not
delete older demo stations. The app also normalises non-breaking spaces and
legacy UTF-8 mojibake when displaying older records.

The same upsert can be repeated from an authenticated project workspace with:

```powershell
node tools/import_mevnet_10_per_state_supabase.cjs --commit
```
