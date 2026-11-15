# Raw data (not in version control)

This folder holds the raw inputs. Its contents are excluded from Git (see
`.gitignore`): some files are licensed and must not be redistributed, and the
others can be re-downloaded. Freeze date for all retrievals: **1 November 2026**.

## `fred/` — FRED series (created by `python/01_fetch_fred.py`)

| Series | Content | Citation required |
| --- | --- | --- |
| `RPSGENAIUSAGESHAREALL` | Generative AI adoption rate, any purpose, US adults 18–64 (Real-Time Population Survey) | Bick, Blandin & Deming (2026), *Management Science*, https://doi.org/10.1287/mnsc.2025.02523 |
| `RPSGENAIUSAGESHARENONWORK` | Same, outside work | as above |
| `ITNETUSERP2USA`, `ITNETUSERP2GBR` | Internet users per 100 people (World Bank WDI, ITU) | World Bank, World Development Indicators |

Get a free API key at https://fred.stlouisfed.org/docs/api/api_key.html and set
`FRED_API_KEY` before running the script. The script fixes the vintage at the
freeze date.

## `ofcom/` — Ofcom Adults' Media Literacy Tracker, respondent-level CSV files

Download from Ofcom's statistical release calendars and save with these names:

| File | Source page |
| --- | --- |
| `ofcom-adults-media-literacy-core-survey-2024-respondent-level-data.csv` | https://www.ofcom.org.uk/about-ofcom/our-research/statistical-release-calendar-2025 (Adults' Media Literacy Core Survey 2024 Respondent Level Data) |
| `ofcom-adults-media-literacy-2025-respondent-level-data.csv` | https://www.ofcom.org.uk/about-ofcom/our-research/statistical-release-calendar-2026 (Adults' Media Literacy 2025 Respondent Level Data) |

Keep the questionnaires and technical reports from the same pages: they define
the variables used (A6/A8 in 2024, A1/A2 and MODULEA in 2025, S3 age bands, S4
sex, weights WT2/WT).

## `pew/` — Pew Research Center, American Trends Panel (licensed)

Create a free Pew account, accept the data licence on each dataset page and
download waves **123, 131, 142, 152 and 164**:
https://www.pewresearch.org/dataset/american-trends-panel-wave-123/ (and the
same address with 131, 142, 152, 164). Unzip each file here; the scripts look
for `ATP W<wave>.sav` anywhere under this folder.

Licence conditions: research use only; do not redistribute the files; keep them
confidential; do not attempt to identify respondents; cite "Pew Research
Center's American Trends Panel" and include the disclaimer: *The opinions
expressed herein, including any implications for policy, are those of the
author and not of Pew Research Center.*
