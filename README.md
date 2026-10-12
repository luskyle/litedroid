# LiteDroid

面向中低性能 ARM 板卡的 Android 产品化裁剪工程。采用**厂商 BSP + 公共产品配置**，不从零移植 AOSP，也不将产品逻辑绑定到 RK3566。

## 当前交付边界

本仓库提供可执行的 BSP 检查、产品配置接入、构建入口、镜像校验和只读设备报告。包含 RK3566 和 RK3576 候选配置，不包含厂商源码、驱动、固件、Google 组件或签名密钥。

**当前不能直接生成或刷入真实板卡固件**：需要具体板卡的可编译 BSP、准确 lunch target、刷机工具和外设资料。候选配置不是已经验证的板级支持；芯片相同也不意味着板卡镜像通用。

## 快速开始

先按 [BSP 接入清单](docs/bsp.md)取得并验证厂商原版 BSP。配置文件是普通 `key=value`，不是 shell；不加引号、不使用环境变量展开、不添加行尾注释。路径可以包含空格。

```sh
cp configs/rk3566.conf configs/local.conf
# 编辑 configs/local.conf：
# bsp_dir=/absolute/path/to/vendor-bsp
# lunch_target=厂商文档中的准确目标，例如带 userdebug 后缀的目标
# jobs=按构建机资源设置

bash scripts/litedroid doctor configs/local.conf
bash scripts/litedroid build configs/local.conf baseline
```

构建入口执行 BSP 的 `build/envsetup.sh`、`lunch` 和 `make -jN`，要求 BSP 支持 `get_build_var`，生成 `.img` 文件。部分厂商还需要专用打包命令，见 [部署流程](docs/deployment.md)。宿主机依赖按所选 BSP 安装，本仓库不自动安装或下载。

验证原版系统后接入产品配置：

```sh
# 先根据真实业务填写 remove_packages，可从小批量非必需应用开始。
bash scripts/litedroid integrate configs/local.conf
# 在 BSP 的板级产品 .mk 中，所有 inherit-product/include 之后加入：
# include vendor/litedroid/product.mk
bash scripts/litedroid build configs/local.conf product
```

`integrate` 只创建 `vendor/litedroid`，不自动修改厂商产品文件，也不覆盖已有不同配置。配置变更时人工审阅并更新 BSP 中的 `config.mk`；不要删除未知文件。`build product` 会验证接入文件、产品标记，以及待移除包是否仍在最终 `PRODUCT_PACKAGES` 中。

**默认不删包**，用于先跑通工程。初始候选可以是 `Calendar DeskClock Email Music QuickSearchBox`，但须先确认业务不依赖它们，再填写 `remove_packages`。这是 Make 产品包名，不是 `com.example` 形式的 APK 包名。候选并非适用于所有 BSP。

这一步仅筛选 `PRODUCT_PACKAGES`；`PRODUCT_PACKAGES_DEBUG`、复制的 APK、vendor 私有预装目录、运行时依赖和功能声明需要另外审查。每轮需要干净/独立的 BSP 输出目录并核对实际镜像，不能把构建清单检查当成最终裁剪验收。

刷机采用厂商正式流程，本仓库**没有自动刷机命令**，以免误写其他设备。刷机后可取证：

```sh
adb devices
bash scripts/litedroid report configs/local.conf 设备序列号
```

结果保存在被 Git 忽略的 `out/`。构建记录包括日志、产品输出路径、镜像 SHA-256、工程版本及脏工作区状态；设备报告不修改系统设置、不安装应用、不采集全量日志。报告可能包含设备/应用信息，应按内部资料管理。

## 工作顺序

1. [选板与 BSP 接入](docs/bsp.md)：优先 BSP 完整性与维护能力，原型优先 4 GB RAM / 32 GB eMMC。
2. [裁剪、构建、部署与恢复](docs/deployment.md)：先原版、再裁剪；量产签名与恢复是发布前置条件。
3. [实机验收](docs/acceptance.md)：测可操作启动、负载、内存、温升和恢复，不只看镜像大小。

## 工程自测

```sh
make test
```

测试使用临时模拟 BSP 和 adb，验证配置解析、接入防覆盖、构建门禁、失败传播和取证流程。它们不代表真实 Android 编译、板卡适配或 OTA 已通过。

## 维护原则

- 公共产品策略放在 `android/litedroid`，芯片和外设适配留在对应厂商 BSP。
- 保留 Android 权限体系、SELinux、Verified Boot 和核心服务；不得以关闭安全机制换取“精简”。
- Framework 仅在产品配置、资源 overlay 或应用层无法满足需求时修改。
- RK3568 不作为 RK3566 的明显性能升级；需要性能余量时评估 RK3576 等中档平台，并逐板验证 BSP。
- 本仓库 MIT 许可不覆盖外部 BSP、闭源二进制和第三方资产；分别遵守其许可。
