# Dispatch — worker_agy_1

## Attempt 1 (thất bại về vị trí file, nội dung task đúng)
- **Command:** `agy --print "<task>" --output-format json --print-timeout 3m --dangerously-skip-permissions` (cwd = workspace/, KHÔNG có `--add-dir`)
- **Kết quả:** `status: SUCCESS` nhưng agy tạo `hello.py` trong
  `~/.gemini/antigravity-cli/scratch/` (scratch riêng của nó), **không**
  trong `workspace/` — dù cwd của process con đã là workspace/.
- **Bài học:** cwd của shell KHÔNG ràng agy vào thư mục đó. Phải dùng
  `--add-dir <path-tuyệt-đối>` để đăng ký thư mục vào workspace của agy,
  và nói rõ đường dẫn tuyệt đối trong prompt.

## Attempt 2 (thành công)
- **Timestamp:** 2026-08-10T02:53:23Z
- **Command:**
```
agy --print "Trong thư mục /Users/ducanh/Project/Infinity/agy-orchestrator-demo/workspace, tạo file hello.py in ra chuỗi \"Hello from agy worker\" (dùng đường dẫn tuyệt đối này, không dùng thư mục scratch riêng của bạn), sau đó chạy file đó bằng python3 và cho biết chính xác output." \
  --add-dir "/Users/ducanh/Project/Infinity/agy-orchestrator-demo/workspace" --output-format json --print-timeout 3m --dangerously-skip-permissions
```
- **Exit code:** 0
- **agy status:** SUCCESS
- **File thật tạo ra:** `workspace/hello.py` ✅ (đã verify độc lập bằng
  `python3 hello.py` → in đúng `Hello from agy worker`)
