# QA Pro Iterative Workflow

อ้างอิงจาก live agent workspace ของ `QA` เพื่อเก็บ workflow สำคัญไว้ใน repo

## หลักการ
- QA ตรวจระบบแบบ iterative ทีละหน้า/ทีละโมดูล
- ไม่ต้องรอจบทั้งระบบก่อนค่อยรายงาน
- เมื่อจบแต่ละหน้า/โมดูล ให้สรุป bug, insight, automation candidates แล้ว handoff ทันที
- QA ส่งผลให้ `ceo` และ `cto` เป็นหลัก แล้วให้ CEO/CTO แตกงานต่อ

## Screenshot rule
ถ้าต้องการไฟล์ screenshot จริง ให้ใช้ QA pro path เท่านั้น:
- `bash /data/.openclaw/workspace-qa/qa-capture.sh <url> <output-name.png>`
- `bash /data/.openclaw/workspace-qa/qa-run-test.sh <url> [prefix]`

ห้าม:
- ใช้ browser screenshot flow แบบเดิมแล้วค่อย copy เอง
- ใช้ placeholder `.png`
- รายงานว่า capture สำเร็จ ถ้ายังไม่มีไฟล์จริงใน `screenshots/`

## Expected artifacts
- Screenshot จริงใน `/data/.openclaw/workspace-qa/screenshots/`
- Report ใน `/data/.openclaw/workspace-qa/reports/`
- STATUS.md ที่อัปเดตตามของจริงหลัง capture/report/handoff

## Handoff format ต่อหนึ่งโมดูล
- Summary
- Bugs found
- Business impact
- Technical impact
- Automation candidates
- Next owner

## STATUS discipline
หลังจบแต่ละ step สำคัญ เช่น capture สำเร็จ, report เสร็จ, handoff เสร็จ ต้องอัปเดต `STATUS.md` ทันที
หลังส่ง handoff แล้ว ห้ามค้างอยู่ที่ step เดิม ให้ขยับ `Next Action` ไปหน้าถัดไป/โมดูลถัดไปทันที
