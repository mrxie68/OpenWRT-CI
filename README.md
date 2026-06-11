# OpenWRT-CI
云编译 OpenWrt / ImmortalWrt 固件。

官方版：
https://github.com/immortalwrt/immortalwrt.git

高通版：
https://github.com/VIKINGYFY/immortalwrt.git

## 固件简要说明

固件默认通过 GitHub Actions 编译。自动任务由 `Auto-Clean` 触发，手动任务可在 Actions 页面选择对应工作流运行。

固件信息里的时间为编译开始的时间，方便核对上游源码提交时间。

保留配置：

- `X86`
- `IPQ60XX-WIFI-YES`

## 工作流说明

- `Auto-Clean.yml`：清理旧 Release、Tag 和 Actions 运行记录。
- `OWRT-ALL.yml`：常规平台编译入口。
- `QCA-ALL.yml`：高通平台编译入口。
- `WRT-TEST.yml`：手动测试入口，仅保留 X86 和 IPQ60XX 配置，默认只生成配置，不完整编译固件。
- `WRT-CORE.yml`：复用编译核心，被其他工作流调用。

## 目录说明

- `.github/workflows`：自定义 CI 配置。
- `Scripts`：自定义编译脚本。
- `Config`：设备和通用 `.config` 配置片段。

## 手动测试建议

优化配置或脚本后，建议先运行 `WRT-TEST`，保持 `TEST=true`，确认配置生成和自定义脚本没有问题，再运行完整编译任务。
