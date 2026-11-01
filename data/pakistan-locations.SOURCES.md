# Pakistan location dataset attribution

The generated `pakistan-locations.json` is derived from the GeoNames Pakistan
country extract (`PK.zip` / `PK.txt`) downloaded from:

- https://download.geonames.org/export/dump/PK.zip
- Dataset documentation: https://download.geonames.org/export/dump/readme.txt
- Feature codes: https://www.geonames.org/export/codes.html

GeoNames data is licensed under the Creative Commons Attribution 4.0 License:
https://creativecommons.org/licenses/by/4.0/

Attribution: © GeoNames contributors, https://www.geonames.org/

Reviewed source download used for this generated file:

- Downloaded: 2026-08-18
- `PK.zip` size: 6,235,517 bytes
- SHA-256: `98749231AA7FD689CACA4175B4942D17098BA1BAE5A0DEC251CD4E98BC915722`

GeoNames describes the data as provided “as is” without a warranty of accuracy,
timeliness, or completeness. The repository transformer includes current,
non-historical administrative divisions and populated-place feature codes. It
excludes abandoned, destroyed, and historical populated places.

## UT Software type mapping

- `ADM1` → `province`
- `ADM2` → `district`
- `ADM3` → `tehsil`
- `ADM4` → `locality`
- `PPLC`, `PPLA`, `PPLA2`, or population ≥ 100,000 → `city`
- `PPLA3`, `PPLA4`, `PPLA5`, or population ≥ 10,000 → `town`
- `PPLL`, `PPLS`, `PPLX` → `locality`
- Other current populated-place codes included by the transformer → `village`

GeoNames does not provide a consistently separate Pakistan `division` level in
the country extract, so the transformer does not relabel districts as divisions.
