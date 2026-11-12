# Private-device validation checklist

Keep personal screenshots, OCR dumps, and annotated samples **outside Git**. Use this checklist on a signed physical device; simulator results do not close the device gate.

## Device gate

- [ ] Signed build with team App Group and unique bundle IDs
- [ ] Share Extension handoff on lock screen / background return (success + retry + delete pending)
- [ ] Optional Face ID / passcode lock: cover on inactive, auth on launch and return, cancel leaves content covered, imports paused until unlocked
- [ ] Source-image retention cleanup and explicit stored-image deletion
- [ ] Accessibility: VoiceOver labels on Home totals, Review confirm, Backup restore confirmation
- [ ] Supported OS versions: iOS 18+ baseline; Foundation Models path only when the device reports availability
- [ ] TestFlight distribution notes verified for your team

## Accuracy samples (Korean / English)

Import private screenshots on the device and collect the app’s extracted rows before making corrections. Annotate the original rows independently. In the manifest, assign matching `row_id` values by visual row position or other evidence independent of date, amount, and type. Use distinct IDs for extra rows and repeated charges. Mark `needs_review` on each extracted row from its mandatory review state.

```json
{"samples":[{"id":"ko-card-01","language":"ko",
  "expected":[{"row_id":"row-1","date":"2026-01-02","amount":-12500,"type":"expense"}],
  "actual":[{"row_id":"row-1","date":"2026-01-02","amount":-12500,"type":"expense","needs_review":false}]}]}
```

Missing detections count against each field’s accuracy. The review rate uses all extracted rows. Keep the manifest with the originals outside Git.

Then run:

```bash
./ios/scripts/accuracy-report.sh ~/spending-validation/manifest.json > /tmp/accuracy-report.md
```

Report columns: sample id, language, date accuracy, amount accuracy, type accuracy, missed rows, extra rows, review-rate (rows that would need Review).

## Multi-currency demo (audit remediation)

1. Settings → Accounts: create synthetic USD and KRW accounts (do not auto-merge same labels).
2. Import or manually enter rows into each account; leave one unmapped.
3. Home: confirm separate currency totals, excluded unmapped count, and repair link.
4. Home → Export: share a desktop snapshot and CSV. Use Settings → Data safety → Backup & restore for the recovery test.
5. Enable app lock; background the app; confirm the privacy cover; cancel unlock and confirm content stays covered.
