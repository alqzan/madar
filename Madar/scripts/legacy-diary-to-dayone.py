"""Convert the old Madar backup's journalEntries into a Day One-shaped ZIP for the app's own importer.

Writes only into the output path given. Prints counts, never entry text.
Each entry keeps the old app's stored date in `madarLegacyDay` (MIGRATION.md: the old date is never recomputed).
"""
import datetime
import json
import sys
import zipfile

src, out = sys.argv[1], sys.argv[2]
data = json.load(open(src, encoding="utf-8"))
entries = []
skipped = {"no id": 0}
photo_refs = 0
for e in data["journalEntries"]:
    uuid = e.get("dayOneUUID") or e.get("id")
    if not uuid:
        skipped["no id"] += 1
        continue
    zone = e.get("timeZone") or "Asia/Riyadh"
    if e.get("capturedAt"):
        created = e["capturedAt"]
    else:
        hh, mm = (e.get("time") or "12:00").split(":")[:2]
        local = datetime.datetime.fromisoformat(f"{e['date']}T{hh}:{mm}:00+03:00")
        created = local.astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    text = e.get("content") or ""
    if e.get("title"):
        text = "# " + e["title"] + ("\n\n" + text if text else "")
    item = {"uuid": uuid,
            "creationDate": created, "timeZone": zone, "text": text,
            "starred": bool(e.get("starred")), "madarLegacyDay": e["date"]}
    if e.get("modifiedAt"):
        item["modifiedDate"] = e["modifiedAt"]
    loc = e.get("location")
    if isinstance(loc, dict) and loc.get("lat") is not None:
        item["location"] = {"latitude": loc["lat"], "longitude": loc["lng"], "placeName": loc.get("place") or ""}
    refs = e.get("photoRefs") or []
    if refs:
        photo_refs += len(refs)
        item["photos"] = [{"identifier": r, "md5": r, "type": "jpeg", "orderInEntry": i} for i, r in enumerate(refs)]
    entries.append(item)

with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    z.writestr("Journal.json", json.dumps({"metadata": {"version": "1.0"}, "entries": entries}, ensure_ascii=False))
print(json.dumps({"entries": len(entries), "skipped": skipped, "photoRefsWithoutFiles": photo_refs}))
