#!/usr/bin/env python3
"""Copy bank SMS from this Mac's Messages database into Madar/Private/bank-messages/ (owner, 18 Oct, RM6).

Run it yourself:  python3 Madar/scripts/export-bank-messages.py
- Reads ~/Library/Messages/chat.db read-only. The terminal app needs Full Disk Access.
- Keeps only messages from named senders (banks, not phone numbers or emails) that mention an amount.
- Drops every verification-code message (OTP). Writes one JSON line per message, per sender.
- The output folder is git-ignored and stays on this Mac.
"""
import json, os, re, sqlite3, sys
from datetime import datetime, timedelta, timezone

DB = os.path.expanduser("~/Library/Messages/chat.db")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Private", "bank-messages")
AMOUNT = re.compile(r"(SAR|ر\.?س|ريال|مبلغ|بمبلغ|شراء|Purchase|Amount|خصم|إيداع|ايداع|حوالة|سداد|استرداد|رصيد)", re.I)
OTP = re.compile(r"(OTP|رمز|كلمة المرور|كلمة السر|verification|code|تحقق|التحقق|password)", re.I)
APPLE_EPOCH = datetime(2001, 1, 1, tzinfo=timezone.utc)

def body(text, attributed):
    if text:
        return text
    if not attributed:
        return None
    # Newer macOS keeps the text only in attributedBody (typedstream): the string follows «NSString».
    blob = bytes(attributed)
    i = blob.find(b"NSString")
    if i < 0:
        return None
    i = blob.find(b"+", i) + 1
    if i <= 0 or i >= len(blob):
        return None
    n = blob[i]; i += 1
    if n == 0x81:
        n = int.from_bytes(blob[i:i + 2], "little"); i += 2
    elif n == 0x82:
        n = int.from_bytes(blob[i:i + 4], "little"); i += 4
    return blob[i:i + n].decode("utf-8", "ignore") or None

def when(raw):
    seconds = raw / 1e9 if raw > 1e12 else raw
    return (APPLE_EPOCH + timedelta(seconds=seconds)).isoformat()

def main():
    try:
        db = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
        rows = db.execute("""select h.id, m.date, m.text, m.attributedBody from message m
                             join handle h on m.handle_id = h.ROWID where m.is_from_me = 0 order by m.date""").fetchall()
    except sqlite3.Error as error:
        sys.exit(f"Cannot read {DB}: {error}\nGive your terminal Full Disk Access (System Settings › Privacy & Security), then run again.")
    os.makedirs(OUT, exist_ok=True)
    kept, otp, by_sender = 0, 0, {}
    for sender, date, text, attributed in rows:
        if sender.startswith("+") or sender.isdigit() or "@" in sender:
            continue  # people, not banks
        message = body(text, attributed)
        if not message or not AMOUNT.search(message):
            continue
        if OTP.search(message):
            otp += 1
            continue
        by_sender.setdefault(sender, []).append({"sender": sender, "date": when(date), "text": message})
        kept += 1
    for sender, messages in by_sender.items():
        name = re.sub(r"[^\w.-]", "_", sender)
        with open(os.path.join(OUT, name + ".jsonl"), "w", encoding="utf-8") as f:
            for m in messages:
                f.write(json.dumps(m, ensure_ascii=False) + "\n")
    print(f"Saved {kept} messages from {len(by_sender)} senders; skipped {otp} verification-code messages.")
    for sender, messages in sorted(by_sender.items(), key=lambda s: -len(s[1])):
        print(f"  {sender}: {len(messages)}")
    print("Folder:", os.path.normpath(OUT))

if __name__ == "__main__":
    main()
