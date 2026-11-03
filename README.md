# 位置シミュレータ (iOS Location Simulator)

Mac から、USB 接続した iPhone / iPad の位置情報を地図上でシミュレートする開発・テスト用ツールです。
Xcode の「Simulate Location」や GPX ファイルの切り替えを、地図のクリックで行えるようにしたものです。

内部では [pymobiledevice3](https://github.com/doronz88/pymobiledevice3) を使い、Xcode と同じ開発者向けの
位置シミュレーション機能 (DVT `LocationSimulation`) を呼び出しています。端末側にアプリを入れる必要はありません。

## 機能

- **地点モード**: 地図をクリックした場所へ移動。地名検索や `35.681,139.767` 形式の座標入力にも対応
- **ルートモード**: クリックで経由点を追加し、指定速度（徒歩・自転車・車のプリセット / 任意の km/h）で移動を再生。一時停止・往復の繰り返しに対応
- **GPX 読み込み**: `trkpt` / `rtept` / `wpt` をルートとして読み込み
- **お気に入り**: よく使う地点を保存
- **解除**: ボタン一つ、またはアプリ終了時に実際の GPS へ戻す

## 必要なもの

- macOS 13 以降
- Python 3（Homebrew の `python3` など）
- iOS / iPadOS 17 以降の端末（デベロッパモードを有効にしておく）
- USB ケーブルでの接続（初回は端末側で「このコンピュータを信頼」を許可）
- Mac アプリをビルドする場合は Xcode

## 使い方

### Mac アプリとして使う

```bash
./mac/build.sh
open build/位置シミュレータ.app
```

初回起動時に `~/Library/Application Support/LocSim/venv` へ pymobiledevice3 をインストールします。
続いて tunneld 起動のため管理者パスワードを求められます。

### スクリプトで使う

`start.command` をダブルクリックすると、`.venv` の作成、tunneld の起動（管理者パスワードが必要）、
GUI サーバーの起動を行い、ブラウザで `http://127.0.0.1:8765` が開きます。

## 仕組み

```
ブラウザ / WKWebView (index.html, Leaflet)
        │  HTTP (127.0.0.1:8765)
server.py ── pymobiledevice3 ── tunneld ── USB ── iPhone / iPad
```

- 位置のシミュレーションは、サーバーと端末の DVT 接続が開いている間だけ有効です。サーバーを終了すると元に戻ります。
- tunneld は iOS 17 以降の端末と通信するための RemoteXPC トンネルで、root 権限が必要です。
- Wi-Fi 経由の接続は、pymobiledevice3 で別途ペアリングしない限り使えません（Xcode の Wi-Fi ペアリングは流用できません）。

## 注意

- **開発・テスト目的で使ってください。** 位置情報ゲームや勤怠アプリなどで使うと、各サービスの利用規約違反になることがあります。
- 地名検索には [Nominatim](https://nominatim.org/) (OpenStreetMap) を使います。検索語は Nominatim に送られます。[利用ポリシー](https://operations.osmfoundation.org/policies/nominatim/)の範囲内で使ってください。
- 地図タイルは © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors、地図ライブラリは [Leaflet](https://leafletjs.com/) (BSD-2-Clause) です。

## ライセンス

GPL-3.0-or-later（依存している pymobiledevice3 のライセンスに合わせています）。[LICENSE](LICENSE) を参照してください。
