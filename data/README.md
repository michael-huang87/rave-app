# Local data (not in git)

This folder stays on your machine. The show log, spend, and sheet export are gitignored.

```bash
mkdir -p data/source
curl -L -o data/source/rave-sheet.xlsx \
  "https://docs.google.com/spreadsheets/d/1-J4MFiVGu204R5ySidxWPogmTyiNU-v5XUUuIXAKq0w/export?format=xlsx"
pip install openpyxl
python3 scripts/clean_sheet.py
```

That writes `events.json`, `sets.json`, `recap.json`, `stats.json`, and `CLEANING.md` here. The backend seeds from those files when you start it. Re-run the script after you change the sheet; then restart the API or `POST /admin/reload-snapshot`.
