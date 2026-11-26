# Kaggle Notebook 定时运行（GitHub Actions）

定时向 Kaggle 推送目标 Notebook 的新版本，从而触发一次运行。

- 目标：`https://www.kaggle.com/code/yongyongwuvip/gemma-4-26b-a4b-it-qat-ud-q4-k-xl-dat`
- 模型：`gemma-4-26B-A4B-it-qat-UD-Q4_K_XL.gguf`
- 调度：北京时间周一至周五 09:00（GitHub cron 使用 UTC，对应 `0 1 * * 1-5`）
- 原理：`kaggle kernels pull` 拉取最新代码 → `kaggle kernels push` 上传并触发执行 → 记录状态/日志/输出文件

## 文件

| 文件 | 作用 |
| --- | --- |
| `.github/workflows/rerun-kaggle-kernel.yml` | 定时任务、鉴权、运行、上传报告 |
| `scripts/rerun_kaggle_kernel.sh` | 拉取 → 校验 → 推送 → 状态轮询 → 日志/输出下载 |
| `requirements.txt` | Kaggle CLI 依赖 |
| `.env.example` | 本地运行参数模板 |
| `.gitignore` | 排除密钥、产物、虚拟环境 |

## 部署

1. 在 GitHub 新建仓库，把本目录内容推上去（含隐藏目录 `.github`）。
2. Kaggle → Account → Create New API Token，得到 `kaggle.json`。
3. 仓库 Settings → Secrets and variables → Actions → New repository secret：

   | Secret | 值 | 必填 |
   | --- | --- | --- |
   | `KAGGLE_USERNAME` | `kaggle.json` 中的 `username` | 二选一 |
   | `KAGGLE_KEY` | `kaggle.json` 中的 `key` | 二选一 |
   | `KAGGLE_API_TOKEN` | Kaggle API token | 二选一，优先级更高 |

   推荐 `KAGGLE_USERNAME` + `KAGGLE_KEY`。不要提交 `kaggle.json`。

4. 进入 Actions 页，启用工作流。点击 **Run workflow** 手动测试一次（可勾选 `dry_run` 只校验不运行）。
5. 检查 Actions 日志中的 `Metadata OK`、`Pushing notebook` 和 Kaggle 状态输出，并下载 `kaggle-run-*` artifact。

## 参数

在 workflow 的 `env` 中修改，本地可通过 `.env` 或导出环境变量覆盖：

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `KERNEL_SLUG` | `yongyongwuvip/gemma-4-26b-a4b-it-qat-ud-q4-k-xl-dat` | Kaggle Notebook 标识 |
| `MODEL_FILE` | `gemma-4-26B-A4B-it-qat-UD-Q4_K_XL.gguf` | 期望 Notebook 加载的 GGUF 模型文件；写入运行记录，并在拉取后做一致性提示 |
| `KAGGLE_ACCELERATOR` | `NvidiaTeslaT4` | 加速器；改 CPU 时设为空字符串 |
| `KAGGLE_TIMEOUT` | `3600` | 单次运行超时（秒） |
| `STATUS_POLL_SECONDS` | `180` | 状态轮询窗口；隧道型 Notebook 常停留 `RUNNING`，属正常 |
| `OUTPUT_FILE_PATTERN` | `ollama_base_url.txt` | 要从 `/kaggle/working` 取回的文件正则；无该文件不影响成功 |
| `DRY_RUN` | `false` | `true` 时只拉取和校验 |

改时间：调整 `cron`，记住是 UTC。北京时间 `HH:MM` → UTC `(HH-8):MM`。

## 本地运行

```bash
python -m pip install -r requirements.txt
# 配置 ~/.kaggle/kaggle.json（权限 600）
set -a && . ./.env && set +a   # 可选
bash scripts/rerun_kaggle_kernel.sh
```

## 注意事项

- 每次 `push` 都会创建新版本并启动一次运行，占用 Kaggle GPU 配额。
- 隧道类 Notebook 可能长时间 `RUNNING` 直至 Kaggle 会话上限；轮询窗口结束不代表运行失败。
- GitHub 定时触发可能延迟数分钟；私有仓库长期无提交可能被暂停定时任务。
- 若 Kaggle 端 Notebook 改为私有或 slug 变更，同步修改 `KERNEL_SLUG`。
- 模型文件实际由 Kaggle Notebook 内部加载；本仓库的 `MODEL_FILE` 用于记录与拉取后的一致性提示。若 Notebook 中模型文件名变更，请同步修改该变量。
- 参考：Kaggle CLI `kernels pull / push / status / logs / output`（`kaggle kernels --help`）。
