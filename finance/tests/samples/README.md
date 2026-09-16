# Sample statement rows

Anonymized fixtures the parser tests run against. A few rows each, real shape,
fake numbers and merchants — safe to commit.

`.gitignore` blocks `*.csv` repo-wide and then un-blocks this folder, so the
fixtures are versioned while real statements never can be.

Per institution, keep the file small and make each row earn its place:

- a plain purchase
- a refund or credit (proves sign handling)
- a payment/transfer (proves it isn't counted as spending)
- anything odd about that bank's format — an embedded comma, a quoted
  description, a running-balance column, a date format that isn't ISO

Name them `<institution>-sample.csv`, matching the parser id in CLAUDE.md.
