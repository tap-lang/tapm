# 包管理设计

tap 包管理的规范。**状态：阶段 1 已实现，端到端可用。**

## 分工

| 命令 | 职责 | 用什么写 |
|---|---|---|
| `tap` | 编译器 + **构建**（`tap build` / `tap run`） | C |
| `tapm` | **依赖管理**（填充 `packages/`、维护锁文件） | tap |

这是 dune / opam 那套分工，不是 cargo 那套。**关键好处：`tap build` 完全独立于 `tapm`**——
`tapm` 本身有 bug 也不影响用户构建自己的项目。代价是两者要共同遵守一套目录约定（下面）。

**`tapm` 不调用 `tap`**，只操作文件系统，所以两者没有运行时耦合。

## 目录布局

```
myapp/
├─ package.toml                 name = "myapp", entry = "src/main.tp"
├─ src/                         本包源码
│   ├─ main.tp
│   └─ util.tp
├─ packages/                    依赖（tapm 负责填充）
│   ├─ foo/
│   │   ├─ package.toml         name = "foo"
│   │   └─ src/
│   │       ├─ lib.tp                import foo.lib
│   │       └─ internal/util.tp      import foo.internal.util
│   └─ bar/
│       ├─ package.toml         name = "bar"
│       └─ src/
└─ build/                       构建产物
```

`packages/` 是**单层平铺**的：每个依赖直接是 `packages/` 下的一个目录，不嵌套。

里面的目录有两种来源：

- **远程依赖**：`tapm` 下载到 `packages/<name>/`
- **path 依赖**：`tapm` **符号链接** `packages/<name>` → 清单里写的路径

两种都是「按 `name` 命名目录」，编译器不需要知道区别，只按目录名解析。

### 哪些进版本控制

```gitignore
packages/
build/
```

**`packages/` 不进版本控制**——它是 `tapm install` 生成的。代价是换台机器必须重跑一次
`tapm install`，所以**锁文件必须提交**，否则没法复现。

## package.toml

```toml
[package]
name = "myapp"
version = "0.1.0"
entry = "src/main.tp"          # 相对 package.toml 所在目录

[dependencies]
bar = { path = "../bar" }      # 本地路径依赖
foo = "1.0.0"                  # 精确版本，来自注册表（阶段 3）
```

- `entry` 只在 `tap` 编译**当前包**时使用。
- 依赖包自己的 `package.toml` 里也可以写 `entry`，但作为依赖被导入时用不上。
- **`packages/<name>/` 的目录名必须等于依赖清单里的 `name`**。这是和编译器之间的契约：
  编译器只按目录名解析，不读清单。由 `tapm` 保证。
- 编译器读 `entry` 的方式（极简扫描的边界）见 tap 仓库的
  [`docs/module.md`](https://github.com/) 的「包模式」一节。

## 锁文件：package.lock.toml

格式参考 Cargo.lock，**由 `tapm` 生成，不要手工编辑**：

```toml
# 自动生成，请勿手工修改
version = 1

[[package]]
name = "myapp"
version = "0.1.0"
dependencies = ["bar", "foo"]

[[package]]
name = "bar"
version = "0.1.0"
source = "path+../bar"

[[package]]
name = "foo"
version = "1.0.0"
source = "registry+https://example.com/index"
checksum = "..."
```

要点：

- **必须提交进版本控制。** `packages/` 被 gitignore 了，锁文件是唯一的可复现来源。
- `tapm install` **按锁文件重建 `packages/`，不重新求解**；要重新求解走 `tapm update`。
- path 依赖记 `source = "path+../bar"`，不记 checksum。

## 命令

### `tapm`

```text
tapm install            # 读 package.toml，展开依赖，接进 packages/，写锁文件
tapm list               # 列出 packages/ 里已经接上的依赖
tapm help
```

还没做：`add` / `remove` / `update`。

### `tap`（构建侧，详见 tap 仓库）

```text
tap build               # 包模式：读 entry，编译到 ./build/<name>
tap run                 # 包模式：编译完接着运行
tap run main.tp         # 文件模式：现有行为，不变
```

**无参数才走包模式**，给了文件就是文件级，用户不会困惑。

## 分阶段计划

**阶段 1：本地布局 + 解析规则** ✅ 已实现

1. ✅ 包边界识别（`package.toml` → `src/`）
2. ✅ 多目录 `TAP_MODULE_PATH`
3. ✅ 隐式搜索根 `<包根>/packages`
4. ✅ `[package] entry` 扫描 + `tap build` + `tap run` 包模式
5. ✅ `tapm`：读清单、展开 path 依赖、按 `name` 建 `packages/<name>/`（符号链接）

**阶段 2：版本与锁**

6. ⬜ 锁文件的 `version` / `source` 填全
7. ⬜ git URL 依赖

**阶段 3：注册表**

8. ⬜ 中心 registry + tarball + 内容哈希

**独立线（不阻塞阶段 1-2，但是第三方生态的前提）**

9. ⬜ tap 的 `pub` 类型作用域化 —— 见「已知限制」

## 阶段 1 验收标准

- `myapp/src/main.tp` 里 `import foo.lib`，`foo` 在 `packages/foo/`（含 `package.toml` +
  `src/lib.tp`）→ `tap build` 与 `tap run` 都通过
- `[dependencies] bar = { path = "../bar" }` → `tapm install` 处理后能 `import bar.x`
- tap 的现有回归全绿，`std/*` 不受影响

**实测已通过**（tap 侧 186/186，端到端清空重跑两遍）。

## 设计决定记录

留档是为了以后不再重新争论。

| 决定 | 选择 | 被否的方案和理由 |
|---|---|---|
| 依赖目录名 | `packages/` | `deps/`、`vendor/` |
| 源码位置 | `src/` 下，清单在外层 | 源码直接放包根——那样零编译器改动，但目录会乱 |
| import 名来源 | manifest 的 `name` | —— |
| 名字怎么映射到目录 | **甲**：`tapm` 按 `name` 建目录，编译器按目录名解析 | 乙：编译器扫所有 `package.toml` 建名字表——等于给 C 编译器塞一个 TOML 解析器 |
| path 依赖 | 符号链接接进 `packages/<name>/` | 复制（本地改动不生效）；让 `tapm` 生成 roots 文件给编译器读（多一层耦合） |
| 包管理器用什么写 | tap | C（那就不用单独一个命令了）、shell（TOML 解析会很难受） |
| 包管理器名字 | `tapm` | `tpm`（`TPM` 是 Trusted Platform Module 的通用缩写，搜索可发现性差） |
| 版本约束 | 先只支持精确版本 | semver 范围——需要求解器，等有真实需求 |
| 构建产物名 | `package.toml` 的 `name` | 入口文件基名 |
| 编译器读清单 | 极简扫描 `entry` | 完整 TOML 解析（浪费）；约定固定入口（和声明式矛盾） |
| `packages/` 进版本控制吗 | **不进**（gitignore） | 提交——但那是生成物，会让 diff 变脏 |
| `TAP_STD_PATH` 支持多目录吗 | **不支持**，保持单目录 | 标准库天然只有一个根，多目录没意义；模块根才需要多目录 |
| 锁文件名 | `package.lock.toml` | —— |
| 锁文件格式 | 参考 Cargo.lock（`[[package]]` 数组） | 自定义格式——没必要重新发明 |
| `tapm` 源码位置 | **独立仓库**，和 tap 同级（`tap-lang/tapm/`） | 放在 tap 仓库里——但它是独立演进的工具，和编译器没有运行时耦合 |

**另外否掉的一个方案**：把编译器改名 `tapc`、包管理器叫 `tap`（对应 go / cargo 那套）。
技术上可行，但迁移成本约 35 处引用 / 13 个文件，而收益只是「主入口拿短名字」——
在 `tap` / `tapm` 的分工下没有这个必要。

## 已知限制

### tap 的 `pub` 类型是全局裸名（第三方生态的拦路虎）

实测：两个包各写 `pub struct Point` 会报 `duplicate struct 'Point'`（且不带位置信息）。

**不解决，第三方包生态不存在**——每个包都得给类型起全局唯一名。

好消息是机制已经有了：非 `pub` 类型会被改名成 `__tap_module_N.Point`，两个包各自定义私有
`Point` 完全正常。只是 `pub` 类型跳过了这一步。

修法是让 `pub` 类型也改名，由 `import` 把类型名带进当前文件作用域，并支持命名空间限定类型
（`a.Point`，现在明确不支持）。这是 tap 编译器**最大的单项工程**，动的是类型名解析。

**注意：这条和目录布局无关。** `src/` 怎么放都好，只要两个第三方包导出同名类型就冲突。
所以阶段 1-2 能让「自己项目的多个模块」和「手动放进 `packages/` 的包」跑起来，
但真正的第三方生态要等这一条。

### 精确版本冲突是硬冲突

`packages/` 是平铺的，同一个包只能放一个版本。`foo` 要 `bar 1.0.0`、`baz` 要 `bar 2.0.0`
→ **直接报错**。

理论上可以共存（tap 没有 ABI，全量源码展开），但那要改目录命名方案（`bar@1.0.0`），
先不做。

### 编译时间随依赖数线性涨

依赖是源码级全展开、泛型全量单态化的，每个包每个实例化都进 LLVM。
包多了要做增量编译或缓存 IR。

反过来这也是好处：**没有 ABI，所以不需要 semver 兼容矩阵**，只需要「能编译」。

### 符号链接在 Windows 上需要开发者模式

path 依赖靠符号链接接进 `packages/`，Windows 上创建符号链接需要管理员权限或开启开发者模式。
**目前失败就直接报错，没有回退到复制**（见「还没做」）。

机制本身已实测：通过符号链接目录导入正常，且两个符号链接指向同一目录时**只加载一次**
（`realpath` 去重生效，不会报重复定义）。

## 还没做

- 锁文件的 `version` 字段是空的——读依赖版本的代码会段错误，见 `src/install.tp` 的 TODO
- `add` / `remove` / `update` 命令
- 非 path 依赖（注册表版本号）
- 符号链接失败时回退到复制
- `tapm` 需要从包根目录运行，不向上找（`tap build` 是向上找的，两者不一致）

## 实现时要同步更新的文档

- tap 仓库的 `docs/module.md`：路径查找顺序、包边界规则、`entry` 读取、包模式命令
- tap 仓库的 `docs/std.md` / `docs/runtime.md`：`tapm` 用到的目录遍历和符号链接 API
