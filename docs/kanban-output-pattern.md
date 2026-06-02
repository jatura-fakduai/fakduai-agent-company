# Kanban Output Pattern

ใช้ pattern นี้กับทุก agent เพื่อให้ `STATUS.md` และ Kanban อ่านง่าย, สั้น, และ actionable

## หลักกลาง

### Current Objective
- 1 บรรทัด
- บอกงานหลักตอนนี้ให้ชัด
- ห้ามกว้างเกินไป เช่น `Working on project`

### Status
ใช้แค่:
- `idle`
- `working`
- `blocked`
- `done`

### Next Action
- บอก action ถัดไปทันที
- ถ้ารอคนอื่น ให้ระบุชื่อ role

### Last Meaningful Output
- ต้องเป็นผลลัพธ์จริงที่เพิ่งเกิดขึ้น
- เช่น file, report, decision, task split, blocker
- ห้ามใช้ข้อความลอยๆ เช่น `Investigating`, `Working on it`

### Collaboration
- ระบุ role ที่กำลังประสานอยู่

### Optional detail sections for richer Kanban cards
ถ้าต้องการให้ modal การ์ดมีรายละเอียดมากขึ้น สามารถเพิ่ม section เหล่านี้ใน `STATUS.md` ได้:
- `## Deliverables`
- `## Acceptance Criteria`
- `## Blockers`
- `## Owner Notes`

ตัวอย่าง:
```md
## Deliverables
- Login security impact note
- Updated acceptance criteria

## Acceptance Criteria
- No pre-filled production credentials
- Login flow still works after fix

## Blockers
- Waiting for source repo path from CTO

## Owner Notes
- Interim analysis sent before full QA pass completes
```

## Role patterns

### CEO
- Objective: งาน/initiative ที่กำลังคุม
- Output: เพิ่ง delegate อะไรให้ใครบ้าง
- Next: จะ follow up ใคร / รอผลจากใคร

ตัวอย่าง:
- Current Objective: Oversee dashboard QA and fix coordination
- Last Meaningful Output: Delegated dashboard review follow-up to Solution Architecture and PM
- Next Action: Wait for QA findings, then assign BA/SA/Tech Lead

### CTO
- Objective: technical issue / architecture decision ที่กำลังคุม
- Output: priority, technical direction, delegated task
- Next: ส่งต่อให้ SA/Tech Lead/Dev ใคร

### PM
- Objective: phase หรือ milestone ปัจจุบัน
- Output: checklist ที่ขยับ, owner ที่ follow up แล้ว
- Next: ต้องตามใครต่อ

### BA
- Objective: requirement/impact area ที่กำลังวิเคราะห์
- Output: business impact, acceptance gap, updated criteria
- Next: sync กับ PM/CEO/SA

### SA
- Objective: flow/spec/dependency issue ที่กำลังออกแบบ
- Output: system impact, dependency map, technical recommendation
- Next: sync กับ CTO/Tech Lead

### Tech Lead
- Objective: implementation stream ที่กำลังแตกงาน
- Output: task breakdown, owner split, blocker
- Next: push task to Frontend/Backend/QA/DevOps

### Frontend
- Objective: UI/page/component ที่กำลังแก้
- Output: implemented/fixed UI part, PR/commit/file touched
- Next: test, handoff, or wait for API

### Backend
- Objective: API/service/logic ที่กำลังแก้
- Output: endpoint/fix/query/schema completed
- Next: test, deploy, or sync FE/QA

### QA
- Objective: page/module ที่กำลังตรวจ
- Output: screenshot/report/bug list ที่เพิ่งได้
- Next: ตรวจหน้าถัดไป หรือ handoff findings ให้ CEO/CTO

### DevOps
- Objective: infra/env/deploy issue ที่กำลังทำ
- Output: env ready, deployment result, infra blocker
- Next: verify, monitor, or unblock team

### Designer
- Objective: screen/flow/design asset ที่กำลังทำ
- Output: mockup/spec/component decision
- Next: handoff PM/FE

### Data
- Objective: tracking/report/data model ที่กำลังทำ
- Output: metric definition, query, dashboard/tracking note
- Next: sync PM/Backend

## Bad vs good examples

Bad:
- Current Objective: Working on stuff
- Last Meaningful Output: Investigating
- Next Action: Continue working

Good:
- Current Objective: Inspect Dashboard page after login
- Last Meaningful Output: Captured `dashboard-page.png` and noted missing KPI widgets
- Next Action: Send findings to CEO and CTO, then inspect Jobs page
