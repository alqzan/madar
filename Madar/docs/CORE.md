# MadarCore — M0

Pure Swift value engines; no SwiftUI, SwiftData, notifications framework or user store access. Swift tools 6.2, iOS 26/macOS 26 minimum. Built and tested locally with Swift 6.4 on macOS 27; OS framework/device delivery gates are separate.

## Contracts

- `GregorianDay` validates real Gregorian dates; `ActivePlace` validates coordinates and IANA timezone on initialization and decoding.
- `MadarDay.resolve` supports fajr (default), maghrib and midnight. `StoredDayKey` is immutable and includes the original active timezone, boundary and Hijri date; callers persist once. `prayerDay` always uses fajr. Missing/polar prayer windows throw rather than guessing.
- `HijriCalendar` uses Foundation Umm Al-Qura; sighting offset applies only to `.sighting`, clamped to −2…2. `DualDate` obeys calendar ordering; diary-night Hijri advancement is presentation only.
- `PrayerTimesEngine.calculate` uses pinned Adhan for Fajr/sunrise/Dhuhr/Asr/Maghrib; Madar always computes Isha itself as Maghrib+90 or +120 in Ramadan according to uncorrected Umm Al-Qura. Polar times return nil. Sanctity is immutable 30 minutes, Maghrib 20.
- `MadarNumberFormatter` localizes Hindi digits (default), Arabic grouping/decimal/percent and encloses signed minor-unit amounts in FSI/PDI. Minor units avoid rounding and support Int64 minimum safely.
- `NotificationArbiter` implements working handoff §8.8/J10. Room reminders are limited to 48h; prayer asks to 96h. Prayer asks are budget exempt and outside sanctity. Room candidates are sanctity-shifted, quiet-filtered, internally capped, then ranked. Notes ceiling configurable 0…2; category-cycle keys prevent repeated 80% reminders. Budget B includes digest and nudge; overflow with digest keeps B−1 and one digest. Digest is Isha+60 (30 sanctity+30), or quietFrom−15 if earlier, then sanctity-checked. `nudge.<dayKey>` is stable, budgeted, at the 48h horizon. A device-off policy plans no requests. `disabledIDs` drops off types supplied by the owning adapter. Plans cap at 60 minus other existing pending slots, trimming farthest prayer asks first. A final delivery-day pass protects actual day budgets when late Isha shifts a digest across midnight/fajr; an unallocated digest drops its overflow members. `submittedBudgetByDay` and `submittedNotesByDay` consume prior durable submitted ledger budget outside the replacement set, preventing a reopen from resetting daily allowance.
- Notification budget day keys use the configured Madar boundary and active prayer-place windows, not device clock timezone. Supply prayer days covering the four-day horizon and timezone of the last known place. Existing pending count means requests outside the current replacement set, not every previously scheduled Madar request. This engine plans requests, it does not claim OS delivery or immediate cancellation on another device.
- `FeatureAvailability.m0` exposes only `.core`; no lobby/rooms before their stage. `DayEventBus` registers ownership and publishes no synthesized rows in M0.
- `RouteRegistry.parse` strictly validates paths/query keys/types, rejects duplicates, invalid dates, UUIDs, pages, amounts, prayer status/heart and unknown settings. Routes are only read/prefill; no URL writes. Future feature routes fail in M0. `requiresUnlock` must be honored before fetching or exposing titles. Fetch/tombstone fallback, tab presentation and dirty-sheet suspension are app responsibilities.

## Commands and durability

`CommandBus(adapter:)` accepts app-only M0 `settings.set`, `settings.applyPreset`, `preset.save`, `core.completeOnboarding` and `system.undo`; external sources receive needsApp. Internal `prayer.log` blind upsert plumbing supports the M0 app/Intent concurrent-write gate with four stored statuses and typed heart, without exposing a Prayer room. Payload schemas reject extra keys. `CommandStoreAdapter.transact` is the serialized atomic boundary: consult durable receipts and natural state, run `request.decision`, apply writes plus inverse and receipt, then commit once. The app adapter must validate settings ownership/preset eligibility and ensure no settings/layout/receipt partial writes.

`CoreCommandReceipt` retention is seven days. Undo is available immediately after successful application: presets 60 seconds, ordinary operations 600 seconds; receipt expiry is independent. Exact commandID replay returns the stored outcome without another write. Equal upsert natural values do not update timestamps. Append equal name+canonical SHA-256 payload across surfaces within ten seconds is duplicate. Durable adapter tests belong to app/data integration; Core parser/decision tests alone do not prove disk durability.

## Dependency provenance

Adhan Swift version/tag 1.5.0, remote exact revision `a6fa2deee80c5abb0b9ad04466f8ab12b53144e7`, source https://github.com/batoulapps/adhan-swift. Both local reference HEAD and tag 1.5.0 resolve to this SHA; SwiftPM checkout and Package.resolved match. MIT license copied intact to `Packages/MadarCore/Licenses/Adhan-MIT.txt`, SHA-256 `60ff1bbadcc093e0d224364b6ed1a439e9b8f8f05a4dd59c45c91d340b728136`. Upstream code is unmodified.

## Verification

Run `swift test --package-path Packages/MadarCore` from Madar. Twenty Swift Testing tests cover the named behaviors, with independent handoff clock expectations; no golden expected values are recorded from Core output.

Prayer fixture v1 is copied verbatim from audit `evidence/prayer-times-results.json`, SHA-256 `cc56fc97bfa17598f425ff78bb5831593818b4155b0d47ae82d7ac7344bc460c`. Provenance inside the fixture preserves assumed Jeddah coordinates and distinguishes specification probing from religious timetable certification. Three golden dates agree within one minute; Hijri 9 October 2026 agrees with 28 Rabi al-Akhir 1448.

J10 fixture v1 `notification-j10-v1.json` contains seven hand-authored scenarios: ordinary overflow, late Isha with quiet cutoff, early Isha, last-known travel place, second device off, one type off, notes internal cap. Additional tests cover pending slot trimming, stable nudge, prayer exemption, sanctity, number isolates, immutable keys/timezone changes, strict routes, canonical hashes and undo deadlines. Rollover fixture v1 hand-authors a late-Isha midnight crossing with a full next-day budget; returning-after-gap tests consume durable budget and notes caps.

Not verified here: physical-device notification submission/delivery/background/location constraints, per-device synchronization/cancellation, CloudKit, locking before app data fetch, widget execution, or OS-cap behavior. These remain integration/device gates.
