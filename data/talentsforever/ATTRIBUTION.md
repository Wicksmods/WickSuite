# talentsforever.com data

Source: https://talentsforever.com/data.json
License: CC BY 4.0
Attribution: Data from talentsforever.com (https://talentsforever.com), by Chris Baldwin.

Fan-made WoW Forever talent calculator. Everything in the export was read off
BlizzCon 2026 demo footage or Blizzard's own slides, so numbers can lag the live
game. Higher talent ranks are often estimated from rank 1 (see the `complete`
flag per talent and `confirmed` rank lists). The author plans a full rebuild
from beta client data after 2026-09-17; re-fetch after that.

No spell IDs in this export. Bind names to IDs in game via GetTalentInfo and
GetSpellInfo, or from the Wick's Probe harvester.

Snapshots are dated: `data-YYYY-MM-DD.json`. Refresh with:

    curl -sL -o data-$(date +%F).json https://talentsforever.com/data.json

Any shipped Wick addon that carries this data must include the attribution line
above in its README and CurseForge description.
