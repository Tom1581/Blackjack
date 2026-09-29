#!/bin/sh
# Re-download the reference charts. Run from this directory; then
#   python3 -c "import parse_bji" ... (see README) and export_fixture.py.
mkdir -p html
for d in 2 6 8; do for s17 in h17 s17; do for das in yes no; do for dbl in all d9 d10; do for surr in ns ls; do
  if [ "$das" = "no" ] && [ "$dbl" != "all" ]; then continue; fi
  f="html/d${d}_${s17}_das${das}_${dbl}_${surr}.html"
  curl -sL -A "Mozilla/5.0" "https://www.blackjackinfo.com/blackjack-basic-strategy-engine/?numdecks=$d&soft17=$s17&dbl=$dbl&das=$das&surr=$surr&peek=yes" -o "$f"
  sleep 1
done; done; done; done; done
