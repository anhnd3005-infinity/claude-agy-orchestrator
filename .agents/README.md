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
- **worker_&lt;kind&gt;_*** (VD `worker_agy_1`, `worker_codex_2`) — một agent
  CLI kind bất kỳ Herdr hỗ trợ (agy, codex, ...) chạy tương tác bên trong 1
  pane do **Herdr** quản lý, đóng vai trò thực thi/coder. Được orchestrator
  điều khiển qua `herdr agent start/prompt/read/send-keys/wait` (không còn
  headless `agy --print` một lần rồi thoát) — pane sống nên có thể theo dõi
  trạng thái (`idle`/`working`/`blocked`/`done`) và gửi tiếp prompt mà không
  cần relaunch.
- **reviewer_*** — một Claude subagent (qua Agent tool), đóng vai trò kiểm
  tra độc lập kết quả của worker. Không tự sửa code — chỉ chấm & báo cáo.
- **challenger_*** (thêm khi cần) — Claude subagent cố tình tìm cách bẻ/phản
  biện kết quả trước khi orchestrator chốt.

## Quy ước file trong mỗi thư mục agent

| File           | Ai viết       | Nội dung                                              |
|----------------|---------------|--------------------------------------------------------|
| `BRIEFING.md`  | orchestrator  | Vai trò, ngữ cảnh, ràng buộc — viết trước khi dispatch |
| `DISPATCH.md`  | orchestrator  | Lệnh/prompt chính xác đã dùng để launch agent, timestamp |
| `progress.md`  | agent đó      | Log tiến trình khi agent chạy (worker_&lt;kind&gt;: log worker trả về) |
| `handoff.md`   | agent đó      | Tóm tắt kết quả cuối, để orchestrator đọc và quyết định bước kế |

`workspace/` (ngoài `.agents/`) là nơi worker thực sự tạo/sửa file sản phẩm —
`.agents/` chỉ chứa hồ sơ điều phối, không chứa code thật.

## Cách dispatch một worker

```bash
skills/dispatching-to-herdr-workers/scripts/dispatch-herdr-worker.sh \
  /Users/ducanh/Project/Infinity/agy-orchestrator-demo/workspace \
  .agents/worker_agy_N \
  "<task>" \
  worker_agy_N \
  agy \
  300000
```

(Đổi `agy` thành `codex` hoặc kind khác ở tham số thứ 5 nếu cần — script tự
tra bảng quirks riêng theo kind, VD agy cần thêm `--add-dir <workspace>`,
codex thì không cần gì thêm.)

Script tự chạy `herdr pane split` → `herdr agent start --kind <kind> --
<native args theo kind>` → `herdr agent prompt --wait` (tự retry khi gặp
`agent_pane_busy`/`agent_prompt_stalled`, tự verify qua pane transcript
trước khi tin status), rồi ghi `DISPATCH.md`, `progress.md`, các
`herdr_*.json` raw response, và `agent_output.txt` (snapshot terminal qua
`herdr agent read`). Exit code `2` = worker `blocked`, `1` = không xác nhận
được đã gửi (`no_delivery_confirmed`) hoặc lỗi khác — cả hai cần
orchestrator tự xử/kiểm tra thủ công, script không tự giải quyết được.
Orchestrator đọc các file đó rồi tự viết `handoff.md` diễn giải lại cho
người đọc, không được tin riêng status string.

## Ghi chú độ tin cậy

`agy` là CLI rất mới (Antigravity CLI, Google, ra mắt ~05/2026), tài liệu
chính thức còn thiếu/mâu thuẫn ở vài điểm (ví dụ `agy plugin import claude`
không thấy trong docs chính thức, chỉ có `import gemini`). Có báo cáo lỗi
cộng đồng rằng `agy --print` đôi khi không in gì ra stdout khi chạy qua
pipe/subprocess trên một số bản/platform (GitHub issue #76) — không còn áp
dụng từ khi chuyển sang Herdr pane tương tác (agy có TTY thật, không qua
pipe nữa).

Ngoài ra, từ smoke test 2026-08-13 (xem
`skills/dispatching-to-herdr-workers/SKILL.md` phần Lessons): pane vừa
split xong gọi `agent start` ngay có thể gặp `agent_pane_busy`; prompt đầu
tiên có thể báo `agent_prompt_stalled` dù thực ra đã gửi thành công. Cả hai
đã fix bằng retry + kiểm tra transcript thật trong script — nhưng đó là
đặc tính của **Herdr**, không riêng agy, nên `codex`/kind khác nhiều khả
năng cũng gặp, chỉ chưa test thật để xác nhận.
