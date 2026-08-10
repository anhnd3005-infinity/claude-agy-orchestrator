# .agents/ orchestration — quy ước

Pattern này dựng theo cùng convention đã dùng ở
`~/teamwork_projects/senior_product_designer_agent/.agents/`: một orchestrator
điều phối một nhóm agent bằng file, không cần API/state ẩn.

## Vai trò trong team này

- **orchestrator** — Claude Code (tôi), chạy trực tiếp trong phiên chat này.
  Đọc `ORIGINAL_REQUEST.md`, chia task, viết `DISPATCH.md` cho từng agent,
  tổng hợp `handoff.md` của tất cả agent vào `orchestrator/plan.md` +
  `orchestrator/GATE_STATUS.md`.
- **worker_agy_*** — một phiên **agy** (Antigravity CLI) chạy headless
  (`agy --print ... --output-format json`), đóng vai trò thực thi/coder.
  Được orchestrator gọi qua Bash, không có state nội bộ nào ngoài những gì
  ghi lại trong thư mục của nó.
- **reviewer_*** — một Claude subagent (qua Agent tool), đóng vai trò kiểm
  tra độc lập kết quả của worker. Không tự sửa code — chỉ chấm & báo cáo.
- **challenger_*** (thêm khi cần) — Claude subagent cố tình tìm cách bẻ/phản
  biện kết quả trước khi orchestrator chốt.

## Quy ước file trong mỗi thư mục agent

| File           | Ai viết       | Nội dung                                              |
|----------------|---------------|--------------------------------------------------------|
| `BRIEFING.md`  | orchestrator  | Vai trò, ngữ cảnh, ràng buộc — viết trước khi dispatch |
| `DISPATCH.md`  | orchestrator  | Lệnh/prompt chính xác đã dùng để launch agent, timestamp |
| `progress.md`  | agent đó      | Log tiến trình khi agent chạy (worker_agy: log agy trả về) |
| `handoff.md`   | agent đó      | Tóm tắt kết quả cuối, để orchestrator đọc và quyết định bước kế |

`workspace/` (ngoài `.agents/`) là nơi worker thực sự tạo/sửa file sản phẩm —
`.agents/` chỉ chứa hồ sơ điều phối, không chứa code thật.

## Cách dispatch một worker_agy

```bash
cd /Users/ducanh/Project/Infinity/agy-orchestrator-demo/workspace
agy --print "<task>" --output-format json --print-timeout 5m > \
  ../.agents/worker_agy_N/agy_raw_output.json
```

Orchestrator đọc JSON đó (`status`, `response`, `structured_output`), rồi tự
viết `progress.md` / `handoff.md` diễn giải lại cho người đọc.

## Ghi chú độ tin cậy (từ research 2026-08-10)

`agy` là CLI rất mới (Antigravity CLI, Google, ra mắt ~05/2026), tài liệu
chính thức còn thiếu/mâu thuẫn ở vài điểm (ví dụ `agy plugin import claude`
không thấy trong docs chính thức, chỉ có `import gemini`). Có báo cáo lỗi
cộng đồng rằng `agy --print` đôi khi không in gì ra stdout khi chạy qua
pipe/subprocess trên một số bản/platform (GitHub issue #76) — trên máy này
đã test và **hoạt động bình thường**, nhưng nếu sau này thấy output rỗng thì
đây là nguyên nhân đã biết, không phải do orchestrator.
