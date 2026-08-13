# .agents/ orchestration — quy ước

Pattern này dựng theo cùng convention đã dùng ở
`~/teamwork_projects/senior_product_designer_agent/.agents/`: một orchestrator
điều phối một nhóm agent bằng file, không cần API/state ẩn.

## Vai trò trong team này

- **orchestrator** — Claude Code (tôi), chạy trực tiếp trong phiên chat này,
  bên trong một phiên **Herdr** (yêu cầu `HERDR_ENV=1`). Đọc
  `ORIGINAL_REQUEST.md`, chia task, viết `DISPATCH.md` cho từng agent, tổng
  hợp `handoff.md` của tất cả agent vào `orchestrator/plan.md` +
  `orchestrator/GATE_STATUS.md`.
- **worker_agy_*** — một agent **agy** (Antigravity CLI) chạy tương tác bên
  trong 1 pane do **Herdr** quản lý, đóng vai trò thực thi/coder. Được
  orchestrator điều khiển qua `herdr agent start/prompt/read/send-keys/wait`
  (không còn headless `agy --print` một lần rồi thoát) — pane sống nên có
  thể theo dõi trạng thái (`idle`/`working`/`blocked`/`done`) và gửi tiếp
  prompt mà không cần relaunch.
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
skills/dispatching-to-agy-workers/scripts/dispatch-agy-worker.sh \
  /Users/ducanh/Project/Infinity/agy-orchestrator-demo/workspace \
  .agents/worker_agy_N \
  "<task>" \
  worker_agy_N \
  300000
```

Script tự chạy `herdr pane split` → `herdr agent start --kind agy -- --add-dir
<workspace>` → `herdr agent prompt --wait`, rồi ghi `DISPATCH.md`,
`progress.md`, các `herdr_*.json` raw response, và `agent_output.txt` (snapshot
terminal qua `herdr agent read`). Exit code `2` = worker `blocked`, cần
orchestrator tự xử qua `herdr agent read/send-keys/prompt` — script không tự
giải quyết được bước này. Orchestrator đọc các file đó rồi tự viết
`handoff.md` diễn giải lại cho người đọc, không được tin riêng status string.

## Ghi chú độ tin cậy (từ research 2026-08-10)

`agy` là CLI rất mới (Antigravity CLI, Google, ra mắt ~05/2026), tài liệu
chính thức còn thiếu/mâu thuẫn ở vài điểm (ví dụ `agy plugin import claude`
không thấy trong docs chính thức, chỉ có `import gemini`). Có báo cáo lỗi
cộng đồng rằng `agy --print` đôi khi không in gì ra stdout khi chạy qua
pipe/subprocess trên một số bản/platform (GitHub issue #76) — trên máy này
đã test và **hoạt động bình thường**, nhưng nếu sau này thấy output rỗng thì
đây là nguyên nhân đã biết, không phải do orchestrator.
