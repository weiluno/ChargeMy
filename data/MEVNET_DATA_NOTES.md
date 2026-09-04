# MEVnet public data export

`mevnet_stations.csv` and `mevnet_charger_groups.csv` are generated from the public PLANMalaysia MEVnet ArcGIS Dashboard. The dashboard identifies its EVCB-location view as data **as at 31 March 2025**; retain the `data_as` and `retrieved_at_utc` fields when using it.

Source dashboard: https://portaldev.planmalaysia.gov.my/portal/apps/dashboards/bba366dc3d144510bfd7cda771795f3d

The public layer publishes station location, state, local authority, existing/proposed counts, AC/DC totals, indoor/outdoor category, status, and network totals. It does **not** publish physical pile-level connector type, power, price, or live operational state. `mevnet_charger_groups.csv` is therefore a network-level aggregate—not an individual-pile data file.

Before a public release or commercial use, verify the current licence/terms with PLANMalaysia. For this assignment prototype, preserve the source URL and attribution in the application and presentation.
