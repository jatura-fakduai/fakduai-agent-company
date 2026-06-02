# Artifact Metadata Schema

เป้าหมายของ schema นี้คือทำให้หลักฐานงาน (artifact/evidence/output) ถูกผูกกับงาน, owner, และที่มาของคำสั่งได้ชัดเจน เพื่อให้:
- ตรวจย้อนหลังได้
- แยก current vs archive ได้
- filter ตาม work item/card/owner ได้
- มนุษย์ audit ได้ทุกขั้น

## Core principle
ห้ามเก็บ artifact แบบมีแค่ `owner + path`
ขั้นต่ำต้องรู้ว่า:
- มาจากงานไหน
- ผูกกับ card ไหน
- ใครขอ / ใครเป็น owner
- เป็น artifact ประเภทอะไร
- ยัง current อยู่ไหม

## Required fields
```json
{
  "id": "artifact-qa-cr3191-login-retest-20260424-113000",
  "owner": "qa",
  "ownerName": "QA",
  "role": "Quality Assurance",
  "workItem": "cr-3.1.9.1-login-flow",
  "cardId": "qa",
  "artifactType": "test-result",
  "title": "Login retest result",
  "path": "data/artifacts/qa/current/login-retest-result.md",
  "sourcePath": "/data/.openclaw/workspace-qa/reports/login-retest-result.md",
  "updatedAt": "2026-04-24T11:30:00+08:00",
  "status": "current",
  "requestedBy": "pm",
  "originType": "handoff",
  "originRef": "handoff-pm-qa-login-retest-20260424",
  "important": true
}
```

## Field definitions
- `id`
  - unique id ของ artifact ชิ้นนั้น
  - แนะนำ format: `<owner>-<workItem>-<artifactType>-<timestamp>`

- `owner`
  - role owner แบบ machine-readable เช่น `qa`, `backend`, `sa`

- `ownerName`
  - human-readable name เช่น `QA`, `Backend`

- `role`
  - display role เช่น `Quality Assurance`

- `workItem`
  - งานหลักที่ artifact นี้ผูกอยู่ เช่น `cr-3.1.9.1-login-flow`
  - ห้ามเว้น ถ้ารู้ว่าเป็น artifact ของงานใด

- `cardId`
  - card/owner ที่ artifact นี้ควรไปโผล่ใน dashboard
  - ปกติจะตรงกับ role owner แต่ไม่จำเป็นเสมอ

- `artifactType`
  - ประเภทหลักของ artifact เช่น:
    - `requirement`
    - `acceptance-criteria`
    - `system-spec`
    - `implementation-status`
    - `technical-note`
    - `test-case`
    - `test-result`
    - `evidence-image`
    - `evidence-video`
    - `decision-summary`
    - `review-summary`

- `title`
  - ชื่อที่มนุษย์อ่านแล้วเข้าใจได้ทันที

- `path`
  - path สำหรับ dashboard เปิดดู

- `sourcePath`
  - path ต้นทางจริงใน workspace

- `updatedAt`
  - เวลาล่าสุดของ artifact

- `status`
  - `current` | `archive`
  - current = ใช้กับงานปัจจุบัน
  - archive = เก่าแต่ยังเก็บตรวจย้อนหลัง

- `requestedBy`
  - ใครเป็น requester ของ artifact นี้ เช่น `pm`, `ceo`, `techlead`

- `originType`
  - ที่มาของงาน เช่น `handoff`, `status`, `report`, `manual`, `review`

- `originRef`
  - reference กลับไปยัง handoff / status / report / decision note ถ้ามี

- `important`
  - ใช้กรองว่าควรแสดงใน Evidence current view หรือไม่

## Recommended optional fields
```json
{
  "mimeType": "text/markdown",
  "tags": ["login", "retest", "evidence"],
  "summary": "Observed redirect mismatch after login submit",
  "expectedOutputRef": "handoff-pm-qa-login-retest-20260424",
  "producedFromStatus": "working",
  "phase": "verification",
  "sequence": 3
}
```

## Required conventions by role
### QA
ควรมี:
- `workItem`
- `artifactType` = `test-case` / `test-result` / `evidence-image` / `evidence-video`
- `requestedBy`
- `originType`
- `originRef`

### BA
ควรมี:
- `workItem`
- `artifactType` = `requirement` / `acceptance-criteria`
- `requestedBy`

### SA
ควรมี:
- `workItem`
- `artifactType` = `system-spec` / `analysis`
- `requestedBy`

### Frontend / Backend
ควรมี:
- `workItem`
- `artifactType` = `implementation-status` / `technical-note`
- `requestedBy`
- ถ้ามี PR/commit ให้เก็บใน `summary` หรือ `originRef`

### PM / CEO / Solution Architecture / Tech Lead
ควรมี:
- `workItem`
- `artifactType` = `decision-summary` / `review-summary` / `execution-plan`
- `requestedBy` อาจเป็น role อื่นหรือมนุษย์

## Current vs archive rule
- current = artifact ล่าสุดที่ยังใช้ขับงานรอบนี้อยู่
- archive = artifact เก่าที่เก็บไว้ตรวจย้อนหลัง
- เมื่อมี artifact ใหม่ของ `workItem + owner + artifactType` เดียวกัน ให้พิจารณา mark ตัวเก่าเป็น `archive`

## Minimal generator behavior
ตัว generator ควร:
1. พยายามอ่าน metadata จาก source โดยตรงก่อน
2. ถ้าไม่เจอ ให้ fallback จาก filename/path convention
3. ถ้ายังไม่รู้ `workItem` จริง ให้ใช้ `unknown` ชั่วคราว แต่ต้องถือว่า incomplete
4. ห้ามแสดงใน Evidence current view ถ้า `important=false`

## UI usage expectation
### Work modal
- แสดงเฉพาะ `important=true` และ `status=current`
- ไม่ควรกวาดทุก artifact มาแสดงรวมกัน

### History view
- ใช้ `status=archive` + `updatedAt` + `originRef` สำหรับ audit ย้อนหลัง

## Anti-patterns
- ไฟล์อยู่ใน dashboard แต่ไม่รู้ว่าของงานไหน
- รูป/video จำนวนมากแต่ไม่มี `workItem`
- requirement/spec/test-result ปนกันโดยไม่มี `artifactType`
- ไม่มี `requestedBy` จน audit ไม่ออกว่าใครสั่ง/ใครรอผล
