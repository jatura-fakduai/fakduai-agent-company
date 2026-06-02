# Adding Custom Roles

## เพิ่ม agent ใหม่ใน config/office.json

เพิ่ม entry ใน `agents` array:

```json
{
  "id": "devops",
  "name": "DevOps",
  "emoji": "🔧",
  "role": "CI/CD & Infrastructure",
  "color": "#FF6348",
  "hair": "neat",
  "hairColor": "#1a1a1a",
  "shirt": "#FF6348",
  "pants": "#2a2a4a",
  "shoes": "#1a1a2a"
}
```

## ต้องเพิ่มด้วย

### 1. ห้อง (rooms)
```json
{
  "id": "devops-room",
  "label": "🔧 DevOps",
  "x": 13, "y": 15, "w": 5, "h": 4,
  "color": "rgba(255,99,72,0.08)"
}
```

### 2. Home position (agentHomes)
```json
"devops": {"x": 15.5, "y": 17}
```

### 3. รัน bootstrap ใหม่
```bash
./scripts/bootstrap.sh
```

## Hair Styles ที่รองรับ
| Style | ลักษณะ |
|-------|---------|
| `short` | ผมสั้นเรียบ |
| `messy` | ผมยุ่ง |
| `ponytail` | ผมยาว+หางม้า (โยนตามเวลาเดิน) |
| `neat` | ผมเรียบแปล้ |
| `bun` | มวยผม |
| `cap` | ใส่แก๊ป |

## Accessory
เพิ่ม `"accessory": "glasses"` ใน agent config เพื่อใส่แว่น
