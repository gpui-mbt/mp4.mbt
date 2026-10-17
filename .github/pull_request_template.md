## Summary

<!-- 何を変更したか。上流追従の場合は旧/新 SHA を書く。 -->

## Upstream / baseline

- Old upstream SHA:
- New upstream SHA:
- Source diff (audit.py output):
- Contract delta (added/removed public items):
- Oracle run ID / command:
- Fixture / golden hash changes:
- Reason for golden change:
- Review approval (golden updates only):

## Verification

- [ ] `moon check --target native`
- [ ] `moon check --target js`
- [ ] `moon test --target native`
- [ ] `moon test --target js`
- [ ] `moon fmt --check`
- [ ] `moon info` + `.mbti` diff reviewed
- [ ] Rust oracle (`cargo test`, `regenerate_fixtures.mbtx -- --check`)
- [ ] Unrun checks are recorded as NOT_RUN / UNVERIFIED (not PASS)

## Notes / limitations
