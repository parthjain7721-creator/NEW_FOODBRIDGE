# FoodBridge Eligibility and Rescue Window Rules

## Approved decisions

- Food age is calculated from `preparedAt`.
- The rescue window is measured in elapsed minutes from `preparedAt`.
- `pickupDeadline = donation creation time + remaining rescue-window minutes`.
- `urgent` applies when the remaining rescue window is 60 minutes or less.
- Damaged or leaking packaging is `not_eligible`.
- Unknown storage requires NGO manual review.
- Manual-review donations receive a pickup deadline calculated using the applicable fallback rule below.
- Hot-held food uses the exact storage value: `hot_held`.

## Approved rule table

| Food category | Storage method | Rescue window | Status rule |
|---|---|---:|---|
| Cooked meal | room_temperature | 4 hours | eligible; urgent at <= 60 minutes |
| Cooked meal | refrigerated | 24 hours | eligible; urgent at <= 60 minutes |
| Cooked meal | frozen | 48 hours | eligible; urgent at <= 60 minutes |
| Cooked meal | hot_held | [APPROVE] | [APPROVE] |
| Cooked meal | unknown | [APPROVE] | manual_review |
| Bakery | room_temperature | 24 hours | eligible; urgent at <= 60 minutes |
| Bakery | refrigerated | 24 hours | eligible; urgent at <= 60 minutes |
| Bakery | frozen | 48 hours | eligible; urgent at <= 60 minutes |
| Bakery | hot_held | [APPROVE] | [APPROVE] |
| Bakery | unknown | [APPROVE] | manual_review |
| Fruits and vegetables | room_temperature | 24 hours | eligible; urgent at <= 60 minutes |
| Fruits and vegetables | refrigerated | 24 hours | eligible; urgent at <= 60 minutes |
| Fruits and vegetables | frozen | 48 hours | eligible; urgent at <= 60 minutes |
| Fruits and vegetables | hot_held | [APPROVE] | [APPROVE] |
| Fruits and vegetables | unknown | [APPROVE] | manual_review |
| Packaged food | room_temperature | 72 hours | eligible; urgent at <= 60 minutes |
| Packaged food | refrigerated | 24 hours | eligible; urgent at <= 60 minutes |
| Packaged food | frozen | 48 hours | eligible; urgent at <= 60 minutes |
| Packaged food | hot_held | [APPROVE] | [APPROVE] |
| Packaged food | unknown | [APPROVE] | manual_review |