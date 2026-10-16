#!/usr/bin/env python3
"""Build the synthetic Day One JSON-export ZIP used by M3-V09 tests.

Everything here is invented: no owner diary or real Day One export is read. Layout follows Day One's
JSON export (one <Journal>.json per journal, media named by md5 under photos/ audios/ videos/ pdfs/,
inline `dayone-moment://` references). The archive is written to a non-seekable stream, so every member
carries a data descriptor (flag bit 3) like streamed exports, and text members are deflated.

Usage: python3 Madar/scripts/make-dayone-fixture.py <output.zip>
"""
import io, json, os, subprocess, sys, tempfile, zipfile

def tool_media(workdir):
    """Real JPEG/M4A bytes from macOS tools, so the app can render them."""
    png = os.path.join(workdir, "p.png"); jpg = os.path.join(workdir, "p.jpg")
    # 8x8 solid PNG, hand-encoded.
    import struct, zlib
    raw = b"".join(b"\x00" + bytes([200, 170, 120]) * 8 for _ in range(8))
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
    with open(png, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 8, 8, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
    subprocess.run(["sips", "-s", "format", "jpeg", png, "--out", jpg], check=True, capture_output=True)
    wav = os.path.join(workdir, "a.wav"); m4a = os.path.join(workdir, "a.m4a")
    import wave
    with wave.open(wav, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(8000); w.writeframes(b"\x00\x00" * 8000)
    subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", wav, m4a], check=True, capture_output=True)
    pdf = (b"%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n"
           b"3 0 obj<</Type/Page/Parent 2 0 R/MediaBox[0 0 200 200]>>endobj\ntrailer<</Root 1 0 R>>\n%%EOF\n")
    return open(jpg, "rb").read(), open(m4a, "rb").read(), pdf

def entries():
    journal = [
        {   # Written 23:30 in London (BST): must land on the London day. Edited later; inline photo then audio.
            "uuid": "A1000000000000000000000000000001", "creationDate": "2025-07-14T22:30:00Z", "modifiedDate": "2025-07-20T09:00:00Z",
            "timeZone": "Europe/London", "starred": True, "tags": ["سفر", "عائلة", " سفر "],
            "text": "# مساء في لندن\n\nمشينا **طويلًا** حتى النهر\\.\n\n![](dayone-moment://P1)\n\nصوت المطر:\n\n![](dayone-moment:/audio/AU1)",
            "location": {"placeName": "Hyde Park", "localityName": "London", "country": "United Kingdom", "latitude": 51.5073, "longitude": -0.1657,
                         "region": {"center": {"latitude": 51.5073, "longitude": -0.1657}, "radius": 75}},
            "weather": {"conditionsDescription": "Rain", "temperatureCelsius": 16},
            "photos": [{"identifier": "P1", "md5": "1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f", "type": "jpeg", "orderInEntry": 0, "width": 8, "height": 8}],
            "audios": [{"identifier": "AU1", "md5": "2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a", "format": "m4a", "duration": 1.0}],
            "editingTime": 120, "creationDevice": "Synthetic Phone", "futureField": {"kept": True},
        },
        {   # 04:10 Riyadh, before Fajr, no coordinates, home zone: previous prayer day under core.dayStart = fajr.
            "uuid": "B2000000000000000000000000000002", "creationDate": "2025-03-02T01:10:00Z", "modifiedDate": "2025-03-02T01:10:00Z",
            "timeZone": "Asia/Riyadh", "text": "قبل الفجر كتبت هذا السطر.",
            "videos": [{"identifier": "V1", "md5": "3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c", "type": "mov", "duration": 4}],
            "pdfAttachments": [{"identifier": "D1", "md5": "4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d", "type": "pdf", "pdfName": "ticket.pdf"}],
        },
        {   # All-day entry: local 00:00:00 keeps its own date.
            "uuid": "C3000000000000000000000000000003", "creationDate": "2025-01-10T21:00:00Z", "timeZone": "Asia/Riyadh",
            "isAllDay": True, "text": "يوم كامل بلا وقت.", "tags": ["بيت"],
        },
        {   # Tokyo, UTC date differs from local date; no coordinates outside home zone: civil date there.
            "uuid": "D4000000000000000000000000000004", "creationDate": "2025-05-01T20:00:00Z", "timeZone": "Asia/Tokyo",
            "text": "صباح في طوكيو.",
        },
        {"uuid": "E5000000000000000000000000000005", "creationDate": "2025-02-01T10:00:00Z", "timeZone": "Asia/Riyadh", "text": "   "},
        {"creationDate": "2025-02-02T10:00:00Z", "timeZone": "Asia/Riyadh", "text": "بلا معرّف"},
    ]
    travel = [
        {   # Second journal reuses the London photo file; inline reference only.
            "uuid": "F6000000000000000000000000000006", "creationDate": "2025-07-15T08:00:00Z", "timeZone": "Europe/London",
            "text": "الصورة نفسها مرة أخرى.\n\n![](dayone-moment://P1B)", "tags": ["سفر"],
            "photos": [{"identifier": "P1B", "md5": "1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f", "type": "jpeg"}],
        },
        {"uuid": "B2000000000000000000000000000002", "creationDate": "2025-03-02T01:10:00Z", "timeZone": "Asia/Riyadh", "text": "نسخة مكررة"},
    ]
    return journal, travel

class Unseekable(io.RawIOBase):
    def __init__(self): self.buffer = bytearray()
    def writable(self): return True
    def write(self, b): self.buffer += b; return len(b)

def main(out):
    with tempfile.TemporaryDirectory() as work:
        jpeg, m4a, pdf = tool_media(work)
    journal, travel = entries()
    stream = Unseekable()
    with zipfile.ZipFile(stream, "w") as z:
        def add(name, data, method):
            info = zipfile.ZipInfo(name, date_time=(2025, 7, 20, 9, 0, 0)); info.compress_type = method
            z.writestr(info, data)
        add("Journal.json", json.dumps({"metadata": {"version": "1.0"}, "entries": journal}, ensure_ascii=False, indent=2).encode(), zipfile.ZIP_DEFLATED)
        add("رحلات.json", json.dumps({"metadata": {"version": "1.0"}, "entries": travel}, ensure_ascii=False, indent=2).encode(), zipfile.ZIP_DEFLATED)
        add("photos/1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f1f.jpeg", jpeg, zipfile.ZIP_STORED)
        add("audios/2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a2a.m4a", m4a, zipfile.ZIP_DEFLATED)
        add("pdfs/4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d.pdf", pdf, zipfile.ZIP_DEFLATED)
        add("__MACOSX/._Journal.json", b"\x00\x05\x16\x07", zipfile.ZIP_STORED)
        # videos/3c3c....mov is deliberately absent: the batch must be partial with one missing video.
    with open(out, "wb") as f: f.write(bytes(stream.buffer))

if __name__ == "__main__":
    main(sys.argv[1])
