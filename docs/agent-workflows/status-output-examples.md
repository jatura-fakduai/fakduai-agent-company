# STATUS.md Output Examples by Role

ใช้ตัวอย่างนี้เพื่อให้แต่ละ role อัปเดต `STATUS.md` แบบอ่านแล้วส่งต่องานได้จริง

## Shared minimum structure
```md
# STATUS.md

## Current Objective
<หนึ่งบรรทัดสรุปงานหลัก>

## Status
<idle | queued | delivering | delivered_waiting_for_receiver | working | blocked | delivery_failed | done>

## Work Item
<เช่น dashboard-refresh-flow>

## Card ID
<เช่น qa / backend / pm>

## Requested By
<เช่น pm / ceo / techlead>

## Artifact Focus
<artifact สำคัญที่คาดว่าจะผลิต เช่น test-result, requirement, technical-note>

## Next Action
<ขั้นถัดไป>

## Last Meaningful Output
<ผลลัพธ์ล่าสุด>

## Collaboration
<คุยกับใคร>
```

## Delivery state example
Use this before the receiving agent has acknowledged the handoff with evidence.

```md
## Current Objective
Receive backend implementation handoff for paper evaluation runner

## Status
delivered_waiting_for_receiver

## Work Item
paper-evaluation-runner

## Card ID
backend

## Requested By
pm

## Artifact Focus
backend-artifact, focused-test-log

## Next Action
Receiver must acknowledge handoff with first evidence/status update

## Last Meaningful Output
delivery succeeded: /path/to/handoff.md

## Collaboration
PM
```

Do not convert this state to `working` until the receiver has actually started a concrete action and can cite first evidence, such as a changed file, command being run, artifact path, or explicit blocker.

---

## CEO example
```md
## Current Objective
Clear team blocker around login retest and prepare next decision for human

## Status
working

## Work Item
dashboard-refresh-flow

## Card ID
ceo

## Requested By
human

## Artifact Focus
decision-summary

## Next Action
Follow up QA and Solution Architecture, then summarize blocker owner and next decision

## Last Meaningful Output
Delegated retest to QA and architecture clarification to Solution Architecture with expected outputs

## Collaboration
QA, Solution Architecture, PM
```

## PM example
```md
## Current Objective
Drive owner-by-owner follow-up for dashboard refresh execution

## Status
working

## Work Item
dashboard-refresh-flow

## Card ID
pm

## Requested By
ceo

## Artifact Focus
execution-plan, dependency-summary

## Next Action
Collect updated output from Backend and Tech Lead, then refresh dependency list

## Last Meaningful Output
Chased stale owners and updated dependency state in PM_TASKS.md

## Collaboration
Backend, Tech Lead, CEO
```

## Solution Architecture example
```md
## Current Objective
Turn auth contract change into handoff-ready technical direction

## Status
working

## Work Item
dashboard-refresh-flow

## Card ID
cto

## Requested By
ceo

## Artifact Focus
solution-summary, technical-note

## Next Action
Send concrete repo/path/module guidance to Tech Lead and Frontend

## Last Meaningful Output
Mapped new token response shape and identified affected client/server boundaries

## Collaboration
Tech Lead, Frontend, Backend
```

## Tech Lead example
```md
## Current Objective
Break down implementation work for frontend/backend based on clarified auth contract

## Status
working

## Work Item
dashboard-refresh-flow

## Card ID
techlead

## Requested By
cto

## Artifact Focus
review-summary, technical-note, evidence-video

## Next Action
Delegate frontend parsing update and backend review check, then wait for PR evidence

## Last Meaningful Output
Prepared actionable tasks with repo targets and review expectations for each dev role

## Collaboration
Solution Architecture, Frontend, Backend
```

## Frontend example
```md
## Current Objective
Patch client auth flow to use new token response contract

## Status
working

## Work Item
dashboard-refresh-flow

## Card ID
frontend

## Requested By
techlead

## Artifact Focus
implementation-status, technical-note

## Next Action
Update login store and verify redirect/storage behavior, then open PR

## Last Meaningful Output
Changed auth parsing in `src/...` and confirmed local flow reaches dashboard with new token path

## Collaboration
Backend, QA, Tech Lead
```

## Backend example
```md
## Current Objective
Validate auth API behavior and prepare backend evidence for QA/Frontend

## Status
working

## Work Item
dashboard-refresh-flow

## Card ID
backend

## Requested By
pm

## Artifact Focus
implementation-status, technical-note, test-result

## Next Action
Confirm response shape and attach endpoint notes/test evidence for downstream roles

## Last Meaningful Output
Verified `/auth/login` response contract and captured request/response impact for client integration

## Collaboration
Frontend, QA, Tech Lead
```

## QA example
```md
## Current Objective
Retest dashboard refresh with evidence-backed verification

## Status
working

## Work Item
dashboard-refresh-flow

## Card ID
qa

## Requested By
pm

## Artifact Focus
test-case, test-result, evidence-image, evidence-video

## Next Action
Run browser retest on dashboard refresh and capture exact symptom or pass evidence

## Last Meaningful Output
Saved browser evidence showing current refresh behavior after data update

## Collaboration
Frontend, Backend, CEO
```

## BA example
```md
## Current Objective
Clarify business rule and acceptance criteria for the current change

## Status
working

## Work Item
dashboard-refresh-flow

## Card ID
ba

## Requested By
pm

## Artifact Focus
requirement, acceptance-criteria

## Next Action
Finalize acceptance wording and send handoff-ready summary to PM/SA

## Last Meaningful Output
Resolved business ambiguity around required fields and submit/close behavior

## Collaboration
PM, SA
```

## SA example
```md
## Current Objective
Finalize system/spec contract for downstream implementation and QA

## Status
working

## Work Item
dashboard-refresh-flow

## Card ID
sa

## Requested By
pm

## Artifact Focus
system-spec, analysis

## Next Action
Publish field/type/validation mapping and call out integration touchpoints

## Last Meaningful Output
Prepared draft system flow and schema impact notes for dev and QA use

## Collaboration
BA, Solution Architecture, Tech Lead
```

## DevOps example
```md
## Current Objective
Support deploy/runtime path for current release candidate

## Status
working

## Work Item
dashboard-refresh-flow

## Card ID
devops

## Requested By
ceo

## Artifact Focus
runtime-status, technical-note

## Next Action
Check pipeline/runtime logs after merge or prepare environment notes if blocked

## Last Meaningful Output
Validated current deploy status and captured runtime/log findings for the team

## Collaboration
Backend, QA, Tech Lead
```

## Bad patterns to avoid
- `Last Meaningful Output: working on it`
- `Next Action: continue`
- `Status: active`
- `Collaboration: everyone`

ให้เขียนแบบอ่านแล้วรู้ทันทีว่า:
- ทำอะไรอยู่
- ได้อะไรแล้ว
- ขั้นถัดไปคืออะไร
- ใครต้องเกี่ยวข้อง
