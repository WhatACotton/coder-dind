# Coder Server (Docker Compose)

Docker Compose 一発で立ち上がる Coder サーバー。

DinD (Docker in Docker) 構成なので、ホストに Docker さえあれば Coder + ワークスペース環境がまるごと動く。ワークスペース内でも `docker` コマンドが使える。個人利用・検証向け。

## 起動

```sh
docker compose up -d
```

`.env` なしでもデフォルト値で起動する。http://localhost:7080 を開く。

## 構成

| サービス | イメージ | 役割 |
|----------|---------|------|
| `coder` | `ghcr.io/coder/coder:latest` | Coder 本体 |
| `dind` | `docker:dind` | Docker デーモン (ワークスペースを管理) |
| `database` | `postgres:17` | データストア |

### ポートを dind 側で公開している理由

Coder は `network_mode: "service:dind"` で DinD とネットワーク名前空間を共有している。こうすると Coder からワークスペースコンテナに `localhost` で到達できる。代わりに Coder 自身にはポートを割り当てられないので、`7080` の公開は DinD 側で行っている。

### ネットワーク設定

nested Docker 環境では P2P 接続が不可能なため、以下の設定を入れている。

| 環境変数 | 値 | 理由 |
|----------|------|------|
| `CODER_DERP_FORCE_WEBSOCKETS` | `true` | DERP リレーを WebSocket 経由に強制 (nested Docker で安定) |
| `CODER_DERP_SERVER_STUN_ADDRESSES` | `disable` | STUN 無効化 (P2P 不可なので不要) |
| `CODER_AGENT_DISABLE_DIRECT` | `true` | P2P 直接接続を無効化 ("message too long" エラー回避) |

DinD コンテナの dockerd には `--mtu=1400` を指定し、WireGuard/tailnet 経由の "message too long" エラーを防いでいる。

### Vivado/Vitis マウント

ホストの外付けディスク (`/dev/sda1`) に入っている Xilinx ツールをワークスペースから利用できるようにしている。

```
VM /mnt/sda1 → compose dind /mnt/sda1 (bind, rslave) → Docker named volume "vivado" (local, bind) → workspace /mnt/vivado
```

DinD 内の Docker デーモンに `local` ドライバの named volume (`vivado`) を `device=/mnt/sda1, o=bind` で作成し、ワークスペースコンテナにマウントしている。Terraform の `docker_volume` リソースで管理し、`prevent_destroy` + `ignore_changes = all` でワークスペース再起動時の削除を防いでいる。

ディスクの中身:

| パス | 内容 |
|------|------|
| `/mnt/vivado/2025.2/Vivado/` | Vivado 2025.2 |
| `/mnt/vivado/2025.2/Vitis/` | Vitis 2025.2 |
| `/mnt/vivado/2025.2/Model_Composer/` | Model Composer |
| `/mnt/vivado/14.7/ISE_DS/` | ISE 14.7 |
| `/mnt/vivado/DocNav/` | DocNav |

ホスト側の前提:

```sh
# /dev/sda1 を rw でマウント
sudo mount /dev/sda1 /mnt/sda1
# shared propagation を有効化 (rootless Docker の場合)
sudo mount --make-rshared /mnt/sda1
```

`/etc/fstab` に追記しておくと再起動時に自動マウントされる。

## セキュリティ

> **Warning**
> DinD は `privileged: true` で動くのでコンテナ分離は効かない。個人利用・検証用途向け。信頼できないユーザーがいる環境には向かない。

### 既知の制限

#### RAM Usage が取得できない

DinD 内のコンテナでは cgroup v2 が threaded モードになるため、`coder stat mem` でコンテナのメモリ使用率を取得できない。ダッシュボードの RAM Usage 欄はエラー表示になる。

![RAM Usage エラー](ram_usage.png)

#### Devcontainer 検出を無効化している理由 (ワークスペース突然死対策)

Coder v2.24.0 以降、エージェントの devcontainer 検出機能がデフォルトで有効になった。この機能はエージェント内部の Container API (port 4) で `docker ps` / `docker inspect` を実行してコンテナを探すが、**nested DinD 環境ではこの API が正常に応答できない**。

coderd サーバーや Web UI からの Container API リクエストが毎回 30 秒タイムアウトし、これが積み重なるとエージェントの tailnet (WireGuard) 接続を圧迫する。特に VSCode 接続時は container 関連の API コールが増えるため、接続後 2〜3 分でエージェントの context がキャンセルされワークスペースが突然死する。

**対策:** テンプレートの entrypoint で agent 起動前に `CODER_AGENT_DEVCONTAINERS_ENABLE=0` を export して、この機能を無効化している。

```hcl
# templates/docker-in-docker/main.tf
entrypoint = ["sh", "-c", "export CODER_AGENT_DEVCONTAINERS_ENABLE=0; ${replace(...)}"]
```

> この問題は Coder 側で nested DinD への対応が改善されれば不要になる可能性がある。

## CLI セットアップ

サーバー起動後、CLI を入れてテンプレートを push する。

### Windows

```powershell
winget install Coder.Coder
coder login http://localhost:7080
coder templates push docker --directory .\templates\docker-in-docker
```

### macOS

```sh
brew install coder
coder login http://localhost:7080
coder templates push docker --directory ./templates/docker-in-docker
```

### Linux

```sh
curl -fsSL https://coder.com/install.sh | sh
coder login http://localhost:7080
coder templates push docker --directory ./templates/docker-in-docker
```

## テンプレート

[templates/docker-in-docker/](templates/docker-in-docker/) — AI コーディングツール・日本語環境・FPGA 開発ツール入りのワークスペーステンプレート。

### プリインストールツール

| カテゴリ | ツール |
|----------|--------|
| **エディタ** | code-server (日本語化済み) |
| **IDE** | JetBrains (Gateway 経由) |
| **AI コーディング** | Claude Code, Gemini CLI, GitHub Copilot CLI, OpenClaw, Cursor Agent, OpenAI Codex CLI |
| **VS Code 拡張** | Claude Code, ChatGPT, Gemini Code Assist |
| **パッケージマネージャ** | Nix (flakes 有効), direnv + nix-direnv |
| **開発ツール** | Node.js 24.x, GitHub CLI, zsh |
| **FPGA** | Vivado 2025.2, Vitis 2025.2, ISE 14.7 (`/mnt/vivado` 経由) |
| **ファイル管理** | File Browser (Web UI) |
