# PM Tracking Workflow

อ้างอิงจาก live agent workspace ของ `PM` เพื่อเก็บกติกาการ track งานไว้ใน repo

## หลักการ
- PM ต้อง track มากกว่า status บรรทัดเดียว
- ใช้ทั้ง `STATUS.md` และ `PM_TASKS.md` ควบคู่กัน
- หลังประสานงานหรือ handoff สำเร็จ ต้องอัปเดตทั้งสถานะและ checklist ตามความเหมาะสม
- ต้องใช้กฎกลาง [Agent Execution Control Policy](execution-control-policy.md): progress ต้องนับจาก evidence, `working` เปล่า ๆ ไม่นับเป็นความคืบหน้า, และงาน stale ต้องมีการจี้/escalate/reassign

## STATUS.md
ใช้สำหรับบอก:
- Current Objective
- Status (`idle`, `queued`, `delivering`, `delivered_waiting_for_receiver`, `working`, `blocked`, `delivery_failed`, `done`)
- Next Action
- Last Meaningful Output
- Collaboration

`queued`, `delivering`, and `delivered_waiting_for_receiver` are delivery states, not proof of active work. PM should only count progress after the receiving agent updates to `working` with evidence or routes `done`/`blocked` with an artifact.

## PM_TASKS.md
ใช้สำหรับบอกภาพรวมโปรเจกต์:
- Project name / goal / updated time
- Checklist ของ milestone หลัก
- Current focus
- Waiting / Dependencies
- Blockers
- Next Follow-ups

## Checklist ตัวอย่าง
- BA requirements drafted
- SA system/spec drafted
- Scope confirmed with CEO
- Tech Lead task breakdown ready
- Design ready
- Frontend implementation started
- Backend implementation started
- QA test plan ready
- QA testing in progress
- Retest completed
- Release / sign-off ready

## กติกา
- ถ้ามี progress ระดับโปรเจกต์ ต้องขยับ checklist ด้วย
- ถ้า QA ส่งผลเป็นรายหน้า/รายโมดูล ให้ PM ขยับ checklist และ follow-up owner ทันที
- PM ต้องช่วยให้ Kanban บอกภาพรวมว่าโปรเจกต์ไปถึงไหนแล้ว ไม่ใช่แค่ PM กำลังทำอะไรอยู่
