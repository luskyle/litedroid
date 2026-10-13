# 板卡与 BSP 接入

## 必须取得的输入

| 输入 | 验证方式 |
|---|---|
| 完整板卡型号、PCB 版本、SoC、RAM/eMMC | 对照实物与厂商资料，不只记录芯片名称 |
| Android BSP 来源、版本、获取授权 | 记录厂商发布版本和源码/二进制许可 |
| 精确 lunch target 与构建命令 | 按厂商说明完成一次原版构建 |
| 对应 bootloader、内核、HAL、固件 | 确认与本板屏幕、触摸和无线模块匹配 |
| 刷机和恢复工具、镜像格式、分区图 | 验证串口、Loader/Maskrom 等恢复入口，流程以厂商为准 |
| 安全补丁和量产支持 | 确认维护期限与供应商问题反馈渠道 |
| 编译环境要求 | 确认宿主机系统、Java、编译器、磁盘与内存要求 |

不将厂商源码直接复制进本仓库。BSP 使用外部绝对路径；通过供应商仓库、repo manifest 或正式源码归档管理。下载仅从授权来源进行。

## 基线接入

1. 保存厂商原始 manifest/源码版本和镜像校验值。
2. 依厂商说明配置宿主机，原版编译成功。
3. 填写本仓库 `configs/local.conf`，运行 `doctor` 与 `build ... baseline`。
4. 如果厂商要求专用构建脚本/镜像打包，先确认执行顺序，再对构建入口做针对性适配；不得用空文件或旧镜像冒充输出。
5. 按厂商流程刷入并实测屏幕、触摸、网络、音频，以及业务所需外设。
6. 保存原版实机报告和验收结果，再开始产品裁剪。

`doctor` 只做基础检查，不能认定 Android 版本安全、BSP 可编译或板卡已兼容。RK3566/RK3576 配置中的目标故意留空，不猜测供应商命名。

## 首版产品默认假设

- 固定业务终端，优先运行自研应用，第一版不接入 GMS。
- 4 GB RAM / 32 GB eMMC 原型；根据实际业务与升级空间再降低配置。
- 不提前规定 Android 大版本，采用可持续维护且外设完整的 BSP。
- 不提前裁剪 Wi-Fi、蓝牙、摄像头或媒体服务，待硬件和应用需求确定。
- 自定义 Launcher、设备管理/锁定模式在业务应用确定后接入；不交付空壳 Launcher 假装业务已完成。

## 换板策略

新板卡单独建立配置和厂商产品目标，复用公共裁剪清单、业务应用与验收方法。每块板重新验证驱动、分区、签名、升级和恢复。一个镜像不能因为都是 Rockchip 芯片就跨板刷入。

## Radxa CM3 (RK3566) 专用落地指南

Radxa CM3 基于 RK3566，常搭配 Radxa CM3 IO Board 或树莓派 CM4 底板使用。官方支持 Android 11。

### 1. 官方 SDK 源码与目标定义

Radxa 官方针对 CM3 的 Android 11 SDK 信息如下：
* **Manifest 仓库**：`https://github.com/radxa/manifests.git`
* **分支与清单**：`-b Android11_Radxa_rk12 -m rockchip-r-release.xml`
* **同步命令**：
  ```bash
  mkdir -p /media/luskyle/DATA/android-lab/radxa-cm3-android11
  cd /media/luskyle/DATA/android-lab/radxa-cm3-android11
  repo init -u https://github.com/radxa/manifests.git -b Android11_Radxa_rk12 -m rockchip-r-release.xml
  repo sync -d -c -j4
  ```
* **CM3 精确 Lunch Target**：`rk356x_rock_cm3_r-userdebug`
* **厂商编译命令**：`source build/envsetup.sh && lunch rk356x_rock_cm3_r-userdebug && ./build.sh -UACKup`

### 2. 裁剪配置与接入

本仓库提供了针对 Radxa CM3 的专用配置：`configs/radxa-cm3.conf`。
配置包含默认针对工控/边缘显示终端的裁剪建议：
`remove_packages=Calendar DeskClock Email Music QuickSearchBox Gallery2 ExactCalculator Messaging Dialer`

接入与裁剪流程：
1. `cp configs/radxa-cm3.conf configs/local.conf`
2. 在 `configs/local.conf` 中填入 `bsp_dir=/media/luskyle/DATA/android-lab/radxa-cm3-android11`
3. 运行 `bash scripts/litedroid doctor configs/local.conf`
4. 运行 `bash scripts/litedroid integrate configs/local.conf`
5. 在 `device/rockchip/rk356x/rk356x_rock_cm3_r/rk356x_rock_cm3_r.mk`（或板级产品 makefile）底部加入：
   `include vendor/litedroid/product.mk`
### 3. 环境与产物本质界定

在开发和评估过程中，需清醒区分宿主模拟器产物与板卡固件产物的本质差异：
* **当前宿主运行的 Cuttlefish 模拟器**：基于 Google 官方 x86_64 AOSP，仅用于在宿主机无物理硬件时验证 Android 原生架构行为、裁剪可行性及评估应用依赖关系。**它不是 Radxa RK3566 镜像，不能刷入 ARM 硬件板卡。**
* **Radxa CM3 专属固件**：包含 ARM64 专有指令集、Rockchip Mali-G52 GPU、RGA 硬件加速器、NPU(rknn) 驱动以及 Linux 4.19/5.10 内核。其产物为 `update.img`（或分区 `.img`），需通过 Radxa 官方 Android 11 SDK 编译生成并使用 rkdeveloptool 刷入实卡。



