# Cuttlefish 宿主环境准备

本次在 Ubuntu 22.04 x86_64 上完成了源码和工具下载，但安装需要本机 sudo 密码，不应在聊天中提供密码。

## 已准备的输入

- 外部源码目录：`/media/luskyle/DATA/android-lab/android-cuttlefish`
- 官方来源：<https://github.com/google/android-cuttlefish>
- 固定源码提交：`76d805ff7bb91c7ad2b7d15f342d3605aaa008b0`
- 官方 Bazelisk v1.29.0 amd64 Debian 包：`/media/luskyle/DATA/android-lab/downloads/bazelisk-v1.29.0-amd64.deb`
- SHA-256：`186d78a20e1a64f59ba08987791a989892d142c9d3a9f9cc0c5c35e201f53924`，已与 GitHub release asset digest 核对。

这些是宿主组件，不是 Android 系统镜像。源码留在数据盘，不进入 LiteDroid 仓库。

## 本机执行

在 LiteDroid 仓库中，以普通用户运行：

```sh
bash scripts/cuttlefish-host-setup --check
bash scripts/cuttlefish-host-setup --install
```

第二条命令会在终端请求 sudo 密码。脚本检查源码版本与下载哈希，安装所需依赖，以普通用户构建 Debian 包，只安装 `cuttlefish-base` 和 `cuttlefish-user`，并添加设备组。apt 安装保留交互确认；失败会停止，日志保存在数据盘的 `android-lab/logs/`。

上游 `tools/buildutils/build_packages.sh` 当前包含系统范围的 `apt upgrade`；这里不调用它，也不调用自动安装依赖的 `build_package.sh`，改为明确依赖安装及 `debuild`。不安装独立的 metrics 包。构建过程仍需下载 Bazel、编译工具和前端依赖；若网络、工具链或 Ubuntu 兼容性报错，需依据构建日志处理，不能认定宿主构建已经通过。

缓存放数据盘，`DEB_BUILD_OPTIONS=parallel=2` 控制支持该变量的构建步骤；专用 Bazel 配置还设置 `--jobs=2`，但前端内部任务可能使用其他并发策略，构建时需关注实际内存峰值。

如果依赖已安装，可用 `bash scripts/cuttlefish-host-setup --build` 仅构建，不请求 sudo。打包保留终端中的代理变量，不输出代理地址。构建前重启本工作区的 Bazel 服务并直接构建 `build_compilation_mode_txt`，将实际错误保存到 `logs/bazel-preflight.log`，避免上游打包步骤只报告 `Bazel install is broken`。不要与本工作区其他 Bazel 构建同时运行。

### Ubuntu 22.04 的 V4L2 头文件兼容

首次完整构建中，`virtio-media 0.0.7` 使用 `v4l2_requestbuffers.flags`，而本机 `linux-libc-dev 5.15` 的头文件没有该字段。不是通过删除 Rust 字段或关闭媒体功能解决。

脚本下载官方 Linux 6.6 源码归档，以 kernel.org 发布的 SHA-256
`d926a06c63dd8ac7df3f86ee1ffc2ce2a3b81a2d168484e76b5b389aba8e56d0`
核对，使用 `headers_install` 在数据盘导出 UAPI，再通过 bindgen 的 `BINDGEN_EXTRA_CLANG_ARGS` 指向这些头文件。归档按其原有许可使用，不复制进本仓库；未替换 `/usr/include`，也未升级运行内核。

专用 Bazel wrapper 和 rc 放在 `android-lab/bin/` 与 `android-lab/bazel-host.bazelrc`，仅用于本次构建，不修改用户全局 Bazel 配置或上游源码。Rust build script 显式启用 shell action 环境，使头文件参数生效。原来报错的 `virtio_media` 目标已在该配置下通过单目标构建；完整宿主包及运行仍需单独验证。

### 前端 Node.js 下载恢复

底层 `cuttlefish-base_1.58.0_amd64.deb` 已生成。前端首次打包因 Node.js 下载中断导致 SHA-256 不匹配而停止，并非需要禁用哈希检查。

脚本预下载固定 Node.js v22.14.0 x64 归档，校验上游固定哈希和官方 `SHASUMS256.txt`，通过仅限指定 URL/参数的 curl wrapper 供上游安装脚本使用本地缓存。其他 curl 请求仍走真实 curl，并设置连接、总时长和低速超时，不修改全局 curl。不要同时运行使用上游 `/tmp/nodejs` 的其他构建。

已有底层包时可以运行 `bash scripts/cuttlefish-host-setup --build-frontend`，只重试前端打包。该模式不会安装软件或请求 sudo。成功后两个宿主包的哈希保存在 `android-lab/logs/host-packages.sha256`；运行验证仍需安装、重新登录/重启和镜像。

## 本次构建结果与安装

`cuttlefish-base_1.58.0_amd64.deb` 和 `cuttlefish-user_1.58.0_amd64.deb` 均已成功打包，SHA-256 复核通过。上游 lintian 仍有 changelog 格式及 init/systemd 包装方面的警告；构建完成不代表已消除这些警告或运行验证通过。

无需再次编译，在本机普通用户终端运行：

```sh
cd /media/luskyle/DATA/android-lab/android-cuttlefish
sha256sum -c ../logs/host-packages.sha256
sudo apt install ./cuttlefish-base_1.58.0_amd64.deb ./cuttlefish-user_1.58.0_amd64.deb
sudo usermod -aG kvm,cvdnetwork,render "$USER"
```

只安装这两个明确包，不使用 `*.deb` 安装 metrics、云端集成等额外组件。保存工作后手动重启；目前 sudo 需要本机密码，自动流程未执行这一步。

安装完成后保存工作并手动重启。脚本不会自动重启、修改全局设备权限或启动虚拟设备。

## 运行验证与基线实例启动

已完成运行验证：
- 确认用户已在 `kvm`、`cvdnetwork`、`render` 用户组中，且 `/dev/kvm` 与 `/dev/vhost-vsock` 具备读写权限。
- 官方 x86_64 userdebug 构建（Build ID `16373615`，Android 17）已就绪于 `/media/luskyle/DATA/android-lab/cf-baseline`。
- ADB 工具已链接至用户路径 (`~/.local/bin/adb`)。
- Cuttlefish 虚拟设备实例已通过 `cvd create` / `cvd start` 启动成功。

### 常用运行控制命令

启动实例（使用本地镜像与主机工具）：
```sh
cvd create --host_path=/media/luskyle/DATA/android-lab/cf-baseline --product_path=/media/luskyle/DATA/android-lab/cf-baseline --daemon=true
```

或者进入解压目录后直接启动：
```sh
cd /media/luskyle/DATA/android-lab/cf-baseline
HOME="$PWD" ./bin/launch_cvd --daemon
```

检查设备状态与 ADB：
```sh
cvd fleet
adb devices -l
adb -s 127.0.0.1:6520 shell getprop sys.boot_completed
```
`sys.boot_completed` 输出 `1` 表示系统已完全启动。

访问 WebRTC 图形界面：
- 本机浏览器访问：`https://localhost:1443` 或 `https://localhost:8443`
- 支持查看屏幕显示及鼠标/触控交互。

停止实例：
```sh
cvd stop
# 或在基线目录：
# HOME="$PWD" ./bin/stop_cvd
```

采集基线数据：
```sh
bash scripts/litedroid report configs/rk3566.conf 127.0.0.1:6520
```

