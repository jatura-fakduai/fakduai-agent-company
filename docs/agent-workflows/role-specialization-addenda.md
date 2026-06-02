# Role Specialization Addenda

เอกสารนี้เป็นชั้นที่ 2 ต่อจาก `agent-operating-rules.md`
ใช้กำหนดว่าแต่ละ role ต้องลึกตรงไหน, ต้องส่ง artifact แบบไหน, และเมื่อไหร่ควร escalate

## 📋 Project Manager (PM)
เน้น:
- รับโจทย์ กำหนด scope แตกงาน
- จัดลำดับความสำคัญ
- ติดตามความคืบหน้า
- stale chasing, dependency follow-up
- escalation point สูงสุดของทีม

artifact ที่ควรส่ง:
- task breakdown with priority
- owner-by-owner next actions
- waiting/dependency list
- progress summary

## 🛠️ Solution Designer
เน้น:
- วิเคราะห์ requirement
- ออกแบบ business flow, user journey
- ออกแบบ UX/UI
- แปลงไอเดียให้เป็น solution ที่ใช้งานได้จริง
- system constraints / tradeoff

artifact ที่ควรส่ง:
- solution summary
- flow diagram / user journey
- wireframe / UI spec
- target modules/repos
- interface/dependency notes
- handoff-ready technical direction

## 🎨 Frontend Engineer
เน้น:
- พัฒนา user interface
- เชื่อมต่อ frontend กับ backend
- UI state, browser/runtime behavior
- API contract handling on client side

artifact ที่ควรส่ง:
- changed files
- selector/state notes when relevant
- commit/PR/evidence

## ⚙️ Backend Engineer
เนื้อ:
- พัฒนา APIs, database, business logic
- integrations
- API behavior, schema/auth/logs/data correctness
- migration/validation side effects

artifact ที่ควรส่ง:
- changed files
- endpoint/method/request-response impact
- commit/PR/test evidence

## 🧪 QA Engineer
เน้น:
- ตรวจสอบคุณภาพ ทดสอบการทำงาน
- หา bugs
- validate ว่าระบบทำงานถูกต้องตาม requirement
- repro quality, verification quality, evidence-backed testing

artifact ที่ควรส่ง:
- screenshots/videos/logs
- repro steps
- observed vs expected
- pass/fail verdict per requirement

## ⚡ Tech Lead
เน้น:
- กำกับมาตรฐานทางเทคนิค
- ตรวจ review งาน
- ตัดสินใจด้าน architecture
- approve ก่อน deploy
- implementation routing

artifact ที่ควรส่ง:
- review result: approve / changes / blocked
- architecture decision notes
- concrete delegated tasks when needed
- exact missing input when blocked

## Usage rule
ทุก workspace/role ควร:
1. ใช้กฎกลางร่วมกัน (`agent-operating-rules.md`)
2. ใช้ addendum เฉพาะ role ของตัวเองเป็นตัวตัดสินความลึกและชนิด artifact
3. อย่าปะปน role จน ownership ซ้ำ
