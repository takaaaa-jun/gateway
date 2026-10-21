# アプリ配信用gateway

Nginxを入口にして、URLのパスごとに各アプリのfrontend・backendへ転送する。新しいアプリを追加するときは、gatewayの転送設定と、アプリ側のDockerfile・Compose・環境設定を用意する。

以下は架空のアプリ名`sample_app`を使った例。実際に追加する名前に置き換える。ローカルで開発し、サーバーには確定したコードをcloneまたはpullして反映する。

## 接続とポートのルール

| 対象 | ポート | 接続方法 |
| --- | --- | --- |
| gateway | 80 | ホストの80番をコンテナの80番へ公開する |
| frontend | 80 | gatewayから`<アプリ名>-frontend:80`へ接続する |
| backend | 8000 | gatewayから`<アプリ名>-backend:8000`へ接続する |

- 各アプリにホスト公開用の`ports`は記載しない。開発専用ポートも設けない。
- frontendは`0.0.0.0:80`、backendは`0.0.0.0:8000`で待ち受ける。
- gatewayと各アプリは、既存のDockerネットワーク`shared-gateway-net`に接続する。
- 共有ネットワーク上の接続先には、アプリ名付きの一意なサービス名またはネットワークエイリアスを使う。
- このルールは新規アプリに適用する。既存アプリの設定には従来のポートが残っている。

```text
ユーザー → ホスト:80 → gateway:80
                        ├─ /sample_app/     → sample_app-frontend:80
                        └─ /sample_app/api/ → sample_app-backend:8000
```

## 1. 必要なファイルを用意する

gatewayとアプリは別のリポジトリで管理する。

```text
gateway/
├─ compose.yaml              # gatewayを起動する既存設定
├─ nginx.conf                # 共通設定・conf.dの読み込み
├─ conf.d/
│  └─ sample_app.conf         # スクリプトで生成する転送設定
└─ scripts/
   ├─ add-app.sh              # Linux・WSL・Git Bash用
   └─ add-app.ps1             # PowerShell用

sample_app/
├─ compose.yaml              # アプリの起動・ネットワーク設定
├─ .env.example              # 秘密値を含まない設定項目のひな形
├─ .env                      # 環境ごとの実値。Git管理しない
├─ .gitignore
├─ frontend/
│  ├─ Dockerfile
│  └─ ...                    # 画面のソース・配信設定
└─ backend/
   ├─ Dockerfile
   └─ ...                    # APIのソース・依存関係定義
```

生成スクリプトが作るのは`gateway/conf.d/<アプリ名>.conf`のみ。アプリ側のCompose・Dockerfile・環境設定は、以下を参考に作成する。

## 2. アプリ側のDockerfileとURL設定を作成する

Dockerfileはアプリの技術構成に合わせて用意する。既存のDockerfileがある場合は、それを利用して待ち受けポート・配信パスを合わせる。

| 項目 | 設定内容 |
| --- | --- |
| frontendの配信パス | `/sample_app/`配下。画面・画像・CSS・JavaScript・画面内リンクを合わせる |
| ブラウザからのAPI接続先 | `/sample_app/api/` |
| backendのAPIパス | `/api/`配下。例：`/api/items` |
| コンテナ間でAPIを呼ぶ場合 | `http://sample_app-backend:8000/api/...` |

gatewayは`/sample_app/api/items`をbackendの`/api/items`へ転送する。frontendへのパスは書き換えず、そのまま転送する。

ブラウザからDockerのサービス名へ直接接続する設定にはしない。画面の直接アクセスや再読み込みでも正しく表示できるよう、フレームワークのベースパス・ルーティング・静的ファイル配信を設定する。

### frontendのDockerfile例：静的ファイルをNginxで配信する場合

ビルド済みの画面ファイルを`frontend/dist/`へ出力するアプリの例。ビルド方法・出力先はアプリに合わせる。SSRなどNode.jsで動作させるアプリでは、そのフレームワーク用のDockerfileを使用する。

`frontend/Dockerfile`を作成する。

```dockerfile
FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY dist/ /usr/share/nginx/html/sample_app/
EXPOSE 80
```

`frontend/nginx.conf`を作成する。以下はSPAの例。

```nginx
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;

    location /sample_app/ {
        try_files $uri $uri/ /sample_app/index.html;
    }
}
```

この例では、Composeでイメージをビルドする前に画面をビルドして`dist/`を作成する。生成される静的ファイルのURLも`/sample_app/`配下になるよう設定する。

### backendのDockerfile例：FastAPI/Uvicornの場合

`backend/requirements.txt`にアプリの依存関係を記載する。最低限`fastapi`と`uvicorn`が必要。`backend/app/main.py`にFastAPIの`app`が定義されている場合、`backend/Dockerfile`は以下のように作成できる。

```dockerfile
FROM python:3.13-slim
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

`EXPOSE`は待ち受けポートの説明であり、アプリの起動ポートを変更するものではない。起動コマンドやサーバー設定で実際のポートを合わせる。`PORT`などの環境変数も、アプリが参照する場合にのみ有効。

## 3. アプリ側のComposeファイルを作成する

アプリのルートに`compose.yaml`を作成する。上記のDockerfileを使う構成例は以下。

```yaml
name: sample-app

services:
  frontend:
    build:
      context: ./frontend
    restart: unless-stopped
    expose:
      - "80"
    networks:
      app-network: {}
      shared-gateway-net:
        aliases:
          - sample_app-frontend

  backend:
    build:
      context: ./backend
    restart: unless-stopped
    environment:
      APP_ENV: ${APP_ENV:-production}
      CORS_ORIGINS: ${CORS_ORIGINS:-http://localhost}
      DATABASE_URL: ${DATABASE_URL:-}
      AUTH_SECRET_KEY: ${AUTH_SECRET_KEY:?Set AUTH_SECRET_KEY in .env}
    expose:
      - "8000"
    networks:
      app-network: {}
      shared-gateway-net:
        aliases:
          - sample_app-backend

networks:
  app-network:
    driver: bridge
  shared-gateway-net:
    external: true
```

- `name`は他のアプリと重複しないComposeプロジェクト名にする。
- `aliases`は設定生成時のアプリ名と一致させる。サービス名が`frontend`・`backend`でも、gatewayからは別名で識別できる。
- DBなどgatewayから接続しないサービスを追加する場合は、アプリ専用の`app-network`だけに接続する。
- `expose`は内部ポートを文書化する指定であり、アクセス制限やホストへの公開ではない。
- `environment`は設定値をコンテナに渡す。変数名と必要な項目は実際のアプリに合わせ、アプリ側でも読み取る処理を実装する。
- frontendのビルド時にベースパスなどが必要な場合は、Dockerfileの`ARG`とComposeの`build.args`で渡す。実行時の環境変数だけではビルド済みの設定を変更できない場合がある。

ローカルでホットリロードを使う場合は、任意で開発用の上書きComposeを用意して起動コマンド・ソースのマウントを変更する。その場合も内部ポート・ネットワーク・別名は共通にし、ホスト公開用ポートは追加しない。基本構成の起動には開発用・本番用のファイル分割は必須ではない。

## 4. 環境設定ファイルを作成する

アプリのルートに`.env.example`を作成する。以下は上記Composeに対応する項目の例。

```dotenv
APP_ENV=production
CORS_ORIGINS=http://localhost
DATABASE_URL=
AUTH_SECRET_KEY=
```

`.env.example`を`.env`へコピーする。

PowerShell：

```powershell
Copy-Item .env.example .env
```

Linux・WSL・Git Bash：

```sh
cp .env.example .env
```

既存の`.env`がある場合はコピーせず、必要な項目だけ更新する。`.env`の`AUTH_SECRET_KEY`に十分に長いランダムな秘密値を設定し、DBを使用するアプリでは接続情報も設定する。上記Composeでは秘密鍵が空のままだと設定検証に失敗する。

`CORS_ORIGINS`はブラウザでアクセスするオリジンにする。ローカルは`http://localhost`、サーバーでは実際のホスト名またはIPを使ったURLとし、アプリのパスは含めない。複数指定の形式などはアプリ側の実装に合わせる。

アプリ側の`.gitignore`に以下を追記する。

```gitignore
.env
.env.*
!.env.example
```

秘密値を含むファイルをイメージへコピーしないよう、各ビルドコンテキストの`.dockerignore`にも`.env`・`.env.*`を記載する。この例では`frontend/`と`backend/`が各ビルドコンテキストとなる。

`.env`はcloneではサーバーに配布されないため、サーバーにも環境に合った実値で別途作成する。DB／モックの切り替えを実装する場合はアプリ側で管理し、APIのURLとポートは変更しない。

## 5. gatewayの転送設定を生成する

gatewayのルートで実行する。PowerShellではGit for Windowsが必要で、付属のシェルを自動検出する。

```powershell
.\scripts\add-app.ps1 sample_app
```

Linux・WSL・Git Bash：

```sh
sh scripts/add-app.sh sample_app
```

引数を省略するとアプリ名の入力を求める。半角英小文字・数字・`-`・`_`を使用し、先頭は英小文字または数字にする。既存ファイルは上書きしない。

`conf.d/sample_app.conf`が生成される。生成だけではコンテナの起動や設定の再読み込みは行わない。

| URLパス | 転送先 | 転送時のパス |
| --- | --- | --- |
| `/sample_app/` | `sample_app-frontend:80` | そのまま維持 |
| `/sample_app/api/` | `sample_app-backend:8000` | 接頭辞を`/api/`へ置換 |

生成設定には、`/sample_app`から`/sample_app/`、`/sample_app/api`から`/sample_app/api/`への転送も含まれる。アプリ側のURL正規化と矛盾しないことを確認し、ブラウザではアプリが定義する画面パスを開く。

## 6. ネットワークとgatewayを起動する

Docker Engineが動作していることを確認する。WindowsではDocker Desktopを起動し、Linuxコンテナを使用する。

共有ネットワークはDockerホストごとに一度作成する。既存の場合は作成不要。

```sh
docker network inspect shared-gateway-net
# 存在しない場合のみ実行
docker network create shared-gateway-net
```

gatewayのルートで実行する。

```sh
docker compose config --quiet
docker compose up -d
docker compose ps
```

各コマンドの成功を確認してから次へ進む。gatewayの起動はアプリの起動を代行しない。

## 7. アプリを起動し、転送設定を反映する

アプリのルートで実行する。

```sh
docker compose --env-file .env config --quiet
# 検証に成功した場合のみ実行
docker compose --env-file .env up -d --build
docker compose --env-file .env ps
```

`config --quiet`で設定内容を画面に表示せず検証する。設定検証はDB接続やAPIの動作まで保証しない。DBの準備・スキーマ管理・ヘルスチェックはアプリ側で行う。

gatewayのルートに戻って実行する。

```sh
docker compose exec gateway nginx -t
# 検証に成功した場合のみ実行
docker compose exec gateway nginx -s reload
```

ブラウザから`http://localhost/sample_app/<画面パス>`を開き、画面・静的ファイル・API通信・画面の再読み込みを確認する。別端末から利用する場合は`localhost`をサーバーのホスト名またはIPに置き換える。

起動できない場合は、それぞれのリポジトリでログを確認する。

```sh
# アプリのルート
docker compose --env-file .env logs --tail 100 frontend backend

# gatewayのルート
docker compose logs --tail 100 gateway
```

## 8. サーバーへの初回配備・更新

初回はgatewayとアプリの両方をcloneし、サーバー用`.env`の作成、共有ネットワークの作成、転送設定の用意、gatewayとアプリの起動を上記の順序で行う。転送設定をGit管理して配布する場合は、サーバーで再生成する必要はない。

更新時は、アプリのルートで作業中の変更がないことを確認し、以下を実行する。

```sh
git pull --ff-only
docker compose --env-file .env config --quiet
# 検証に成功した場合のみ実行
docker compose --env-file .env up -d --build
```

コード更新だけならgatewayの再読み込みは不要。gatewayの転送設定も変更した場合は、gateway側も更新し、`nginx -t`の成功後に再読み込みする。ローカルとサーバーで公開ポート・内部ポートのルールは共通にする。

## 参考資料

- [Docker Composeのネットワーク](https://docs.docker.com/compose/how-tos/networking/)
- [Composeのサービス設定](https://docs.docker.com/reference/compose-file/services/)
- [Next.jsのbasePath（該当するアプリの場合）](https://nextjs.org/docs/pages/api-reference/config/next-config-js/basePath)
