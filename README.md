# xl-elvm
EsoLangVM Compiler Infrastructure on xyzzy

## ELVMって何?

本家 https://github.com/shinh/elvm

[よく分かる解説](http://shinh.skr.jp/slide/elvm/000.html)

## xl-elvmとは

ELVMのbackendにxyzzy lispを加え、ELVMツールチェイン(8cc&elc)をxyzzy lisp向けにコンパイルした物です。
xyzzy上で(外部コマンドを使わずに)C言語のプログラムを様々な言語にコンパイルできます。

**現在対応しているコンパイル先言語**
- xyzzy lisp
- ELVM IR
- Ruby
- Python
- JavaScript
- Emacs Lisp
- VimScript
- TeX
- Common Lisp
- Bash
- Java
- C
- x86
- C-INTERCAL
- Whitespace
- piet
- Befunge
- Brainf*ck
- Unlambda

## インストール
[Releaseページ](https://github.com/youz/xl-elvm/releases)から
xl-elvm-(version).zipをダウンロードしてsite-lispフォルダ等 `*load-path*`
にあるフォルダ内に展開し、xyzzyで`(require "elvm")`を実行します。


## コマンド

M-x で実行するやつです。5つあります。

### elvm-compile-buffer
指定したバッファ上のCソースコードをコンパイルします。
コンパイル先言語を聞かれるので好きな言語を入力してください。

sampleフォルダのhello.cは10秒前後、fizzbuzz.cは大体十数分かかるので、
ちょっと複雑なコードをコンパイルするときは覚悟して実行しましょう。

なおxyzzy lispにコンパイルした場合、main関数は

`elvm-compiled:elvm-main (&optional input-stream output-stream)`

になります。
この関数は入力ストーリームと出力ストリームを引数に取り、それぞれ
標準入力と標準出力として扱います。
(省略した場合は`*standard-input*`と`*standard-output*`を使用します。)

実行するには、コンパイル結果のバッファでeval-bufferもしくは
byte-compile-file & load)した後、scratchバッファで
```
(with-input-from-string (is "stdin text")
  (with-output-to-buffer ((create-new-buffer "*stdout*"))
    (elvm-compiled:elvm-main is)))
```
のようにして呼び出してみてください。

### elvm-compile-file
Cソースファイルを指定してコンパイルします。

### elvm-compile-and-run-buffer
指定したバッファ上のCソースコードをxyzzy lispにコンパイルした後、
bytecompileした上で実行します。

### elvm-assemble-buffer
コンパイル時にターゲットをELVM IRにして出力したコードや、
本家ELVMの8ccで生成したELVM IRをアセンブルします。

### elvm-assemble-file
ELVM IRファイルを指定してアセンブルします。


## API
elvmパッケージからexportされている関数です。

- elvm:compile-c-to-eir (input-buffer output-buffer)
- elvm:assemble-eir (input-buffer output-buffer)

使い方はelvm/command.lを参考にしてみて下さい。
