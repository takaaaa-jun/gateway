# Nginxのコンテナ

## 技術スタック

- Nginx
- Docker

## ネットワーク

- shared-gateway-net

## ポート番号のルール

今後、各アプリのポート番号は以下のルールに統一する。

| 対象 | ポート番号 | 用途 |
| --- | --- | --- |
| gateway | 80 | ホストの80番をgatewayコンテナの80番に公開する（`80:80`） |
| frontend | 80 | コンテナ内部で画面へのリクエストを待ち受ける |
| backend | 8000 | コンテナ内部でAPIへのリクエストを待ち受ける |

- 外部からのアクセスはgatewayに集約し、各アプリへの接続のためにfrontend・backendのポートをホストへ公開する必要はない。
- gatewayはURLのパスを設定済みのルールと照合し、Dockerのサービス名とコンテナ内部のポートを指定して転送する。
- 各アプリはgatewayと同じ`shared-gateway-net`に接続し、そのネットワーク内で一意に識別できるサービス名またはネットワークエイリアスを使用する。
- コンテナごとに通信環境が独立しているため、異なるコンテナで同じ内部ポートを使用できる。
- 各アプリは他のコンテナから接続できるよう、`0.0.0.0:80`または`0.0.0.0:8000`で待ち受ける。

転送例（サービス名・パスは例示）：

```text
ユーザー → ホスト:80 → gateway:80
                        ├─ /app-a/     → app-a-frontend:80
                        ├─ /app-a/api/ → app-a-backend:8000
                        ├─ /app-b/     → app-b-frontend:80
                        └─ /app-b/api/ → app-b-backend:8000
```

このルールは統一方針であり、現在の設定には未反映。適用時は、各アプリの待ち受けポートとgatewayの転送先ポートを合わせて変更する。また、各アプリの画面・APIのURL設定を、gatewayで使用するパスに合わせる。

## 設定ファイル

- nginx.conf
- conf.d/recipe_search.conf

## コマンド

- sudo docker compose up -d
- sudo docker compose down
- sudo docker network create shared-gateway-net

## 新しいアプリの設定を生成する

リポジトリのルートで実行する。WindowsのPowerShellでは、Git for Windows付属の`sh.exe`を自動検出する以下のコマンドを使用する。

```powershell
.\scripts\add-app.ps1 アプリ名
```

Linux・WSL・Git Bashなど、`sh`が利用できる環境では以下を使用する。

```sh
sh scripts/add-app.sh check_annotator
```

引数を省略するとアプリ名の入力を求める。名前には半角英小文字・数字・`-`・`_`を使用し、先頭は英小文字または数字にする。既存ファイルは上書きしない。

上記の例では`conf.d/check_annotator.conf`を生成し、以下の転送を設定する。

| URLパス | 転送先 | 転送時のパス |
| --- | --- | --- |
| `/check_annotator/` | `check_annotator-frontend:80` | そのまま維持 |
| `/check_annotator/api/` | `check_annotator-backend:8000` | `/api/`に置換（例：`/check_annotator/api/items` → `/api/items`） |

アプリ側は次の条件に合わせる。

- 上記のサービス名、または同名のネットワークエイリアスで`shared-gateway-net`に接続する。
- frontendは`0.0.0.0:80`で待ち受け、`/check_annotator/`配下で画面・静的ファイルを配信する。
- backendは`0.0.0.0:8000`で待ち受け、`/api/`配下にAPIを用意する。
- ブラウザからのAPIアクセス先は`/check_annotator/api/`とする。

生成処理ではコンテナの起動・設定反映は行わない。アプリ側の準備後、起動済みのgatewayには以下で設定を検証してから反映する。

```sh
docker compose exec gateway nginx -t
# 検証に成功した場合のみ実行
docker compose exec gateway nginx -s reload
```
