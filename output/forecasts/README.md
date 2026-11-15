# Registered forecasts

`forecasts_registered_2026-11-01_recorded_2026-11-02.csv` holds forecasts made
from the models estimated on data frozen on **1 November 2026**. The file was
recorded on **2 November 2026**, and its MD5 checksum is in the `.md5` file
beside it:

```
79b462f579cb61046a139cc3d99a2efb
```

The forecasts refer to survey waves that had not been released at the freeze:

| Target | Date |
| --- | --- |
| Real-Time Population Survey tracker, United States, ages 18–64 | November 2026, February 2027, May 2027 |
| Ofcom Adults' Media Literacy Tracker, United Kingdom, ages 16–64 | autumn 2026 wave |
| Deloitte Digital Consumer Trends, United Kingdom, ages 16–75 | 2027 survey |
| Latent share of working-age adults who have ever used generative AI | December 2027 and December 2030, both countries |

Columns: `model`, `id`, `country`, `series`, `date`, `description`, posterior
`mean`, 80% interval (`lo80`, `hi80`), 95% interval (`lo95`, `hi95`),
`latent_F_mean` (latent adopted share at that date), `freeze_date` and
`recorded_on`. Values are percentages. Survey targets are forecasts of the
published estimate, including the scale factor and level shift of the series.

## Rules

- The file is never edited. `python/check_forecast_checksum.py` (also run by
  `make check` and on every push) fails if its contents change.
- When a target is released, its outcome is added to a separate file,
  `outcomes.csv`, with the source and the date of access. The forecast file
  stays as it is.
- New forecasts, if any, go into a new file with a new freeze date.

Git stores the file byte for byte (see `.gitattributes`), so the checksum also
holds after a checkout on Windows.
