# agmsg-hub Instructions

このメモは、agmsg-hub を Codex CLI / Codex.app と remote server MVP で試すための実務手順です。

## 前提

- 通常の Codex client は `npx skills add` で入れる。`npx skills install` ではない。Vercel Skills CLI のコマンド名は `add`。
- `install.sh` は clone 済みの **agmsg-hub repo 内**で実行する開発/手動 install 用。
- `$agmsg` は **Codex で作業する repo 内**で使う。
- remote server は `agmsgd`。Codex CLI や Codex.app は server ではなく client/agent。
- remote mode では message DB と team/agent registry が server 側に集まる。local mode では従来通り各 client の `~/.agents/skills/agmsg/teams/` を使う。

## Install

Codex client へ通常 install:

```bash
npx -y skills@latest add 2bbb/agmsg-hub --skill agmsg -g -a codex -y --copy
```

`--copy` を付ける。agmsg は local mode では skill dir 配下に `db/`, `teams/`, `db/config.yaml` を書くため、symlink/cache 依存にしない方が事故が少ない。

clone して確認してから入れる場合:

```bash
git clone https://github.com/2bbb/agmsg-hub.git
cd agmsg-hub
./install.sh --agent-type codex
```

custom command 名が必要な場合は clone-based install を使う:

```bash
./install.sh --cmd m --agent-type codex
```

## 更新

Skills CLI install:

```bash
npx -y skills@latest update agmsg -g -y
```

clone-based install:

agmsg-hub repo 側:

```bash
cd /Users/2bit/prog/utils/agmsg
git pull
./install.sh --update --agent-type codex
```

`--update` は未インストールなら初回インストールにフォールバックする。

更新後は Codex CLI / Codex.app の新しい session を開く。既存 session は古い `SKILL.md` を保持している可能性がある。

server 側で `agmsgd` を起動中なら、必要に応じて止めて起動し直す。

## Server 起動

server machine にも同じ install をしておく:

```bash
npx -y skills@latest add 2bbb/agmsg-hub --skill agmsg -g -a codex -y --copy
```

server machine で:

```bash
~/.agents/skills/agmsg/scripts/server.sh serve --host 0.0.0.0 --port 8787
```

同じ machine から確認:

```bash
curl -fsS http://127.0.0.1:8787/api/v1/health
```

LAN 上の別 machine から確認:

```bash
curl -fsS http://<server-host>.local:8787/api/v1/health
```

期待値:

```json
{"ok":true,"api_version":"v1","server_version":"0.1.0","storage":"sqlite"}
```

`--host 0.0.0.0` は listen 用。client の URL には `0.0.0.0` を使わない。client は `127.0.0.1` か `<server-host>.local` を使う。

## Browser UI

`agmsgd` は同じ port で簡易 dashboard も出す。

server と同じ machine:

```text
http://127.0.0.1:8787/
```

LAN 上の別 machine:

```text
http://<server-host>.local:8787/
```

できること:

- health の確認
- team 一覧
- team member 一覧
- message history の確認
- test message の送信

`server.sh serve --token <token>` で bearer token を設定している場合、dashboard 左上の `Bearer token` に同じ token を入れる。HTML 自体は開けるが、API 呼び出しは token なしでは 401 になる。

この UI は現時点では local/LAN の debug/admin 用。未認証のまま public internet に直接出さない。

## Client 設定

server と同じ machine 上の client:

```bash
~/.agents/skills/agmsg/scripts/remote.sh configure http://127.0.0.1:8787
~/.agents/skills/agmsg/scripts/remote.sh switch remote
~/.agents/skills/agmsg/scripts/remote.sh status
```

別 machine 上の client:

```bash
~/.agents/skills/agmsg/scripts/remote.sh configure http://<server-host>.local:8787
~/.agents/skills/agmsg/scripts/remote.sh switch remote
~/.agents/skills/agmsg/scripts/remote.sh status
```

期待値:

```text
storage.active=remote
remote.health=ok
```

local SQLite に戻す:

```bash
~/.agents/skills/agmsg/scripts/remote.sh switch local
```

## Join

各 client で同じ team 名、別 agent 名を使って join する。remote mode ではこの登録は server 側の registry に保存され、`team.sh` と `whoami.sh` も server を見る。

例: server 側 Codex CLI:

```bash
cd /Users/2bit/prog/nozzle_proj
~/.agents/skills/agmsg/scripts/join.sh codex-test cli codex "$(pwd)"
```

例: 別 Mac 側 Codex.app:

```bash
cd /Users/2bit/prog/nozzle_proj
~/.agents/skills/agmsg/scripts/join.sh codex-test app codex "$(pwd)"
```

同じ project/type/agent で再 join しても重複登録にはならない。別 client や別 project から使う場合は、その client/project でも join する。

## 送受信テスト

server 側から別 Mac 側へ:

```bash
~/.agents/skills/agmsg/scripts/send.sh codex-test cli app "hello from cli"
```

別 Mac 側で受信:

```bash
~/.agents/skills/agmsg/scripts/inbox.sh codex-test app
```

逆方向:

```bash
~/.agents/skills/agmsg/scripts/send.sh codex-test app cli "hello from app"
~/.agents/skills/agmsg/scripts/inbox.sh codex-test cli
```

Codex からは:

```text
$agmsg doctor
$agmsg remote status
$agmsg
$agmsg send <agent> <message>
```

## 待機

Codex は Claude Code の Monitor 相当を持たないので、明示的に待つ場合は:

```text
$agmsg wait
$agmsg wait 120
$agmsg wait 120 5
```

意味:

```text
$agmsg wait        -> 最大60秒、2秒ごとに確認
$agmsg wait 120    -> 最大120秒、2秒ごとに確認
$agmsg wait 120 5  -> 最大120秒、5秒ごとに確認
```

shell 直叩き:

```bash
~/.agents/skills/agmsg/scripts/inbox.sh codex-test app --wait 120 --poll 5
```

## Codex sandbox の注意

Codex CLI / Codex.app では sandbox が localhost/LAN HTTP をブロックすることがある。Terminal の `curl` が成功していても、Codex 内の `$agmsg doctor` や `$agmsg remote status` が `remote.health` で失敗する場合がある。

この場合、server down と断定する前に、同じ agmsg script を **elevated/unrestricted shell permission** で1回再実行する。

切り分け:

```text
Terminal curl が失敗
  -> server / firewall / host / port の問題

Terminal curl は成功、Codex 内 curl が失敗
  -> Codex sandbox/network の問題

Codex 内 curl は成功、remote.sh status が失敗
  -> agmsg config / remote.url / token の問題
```

## actas

Codex の `$agmsg actas <name>` は send-side only。以後の `send.sh` の `from` を切り替えるだけで、受信側を完全にその role に絞るわけではない。

```text
$agmsg actas app
$agmsg send cli hello
```

解除/登録削除:

```text
$agmsg drop app
```

agent 名そのものを変更する場合:

```bash
~/.agents/skills/agmsg/scripts/rename.sh codex-test old_name new_name
```

remote mode では `join.sh`, `team.sh`, `whoami.sh` は server registry を使う。ただし `rename.sh` はまだ remote registry API に対応していないので、名前変更は未整備。

## よくある失敗

`remote.health` が fail:

```bash
~/.agents/skills/agmsg/scripts/remote.sh status
curl -fsS http://<host>:8787/api/v1/health
```

`remote.url` が `http://0.0.0.0:8787`:

```bash
~/.agents/skills/agmsg/scripts/remote.sh configure http://127.0.0.1:8787
# または
~/.agents/skills/agmsg/scripts/remote.sh configure http://<server-host>.local:8787
```

Codex が古い動きをする:

```bash
cd /Users/2bit/prog/utils/agmsg
git pull
./install.sh --update --agent-type codex
```

その後、新しい Codex session を開く。
