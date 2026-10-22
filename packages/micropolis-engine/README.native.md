# MicropolisNative: native C API and macOS integration

The original C++ engine is shared by Emscripten and the native library. The native
build excludes `src/emscripten.cpp`, `src/callback.cpp`, JavaScript bindings and
all generated WASM files. It uses `native/callback.cpp` as a silent frontend and
`native/api.cpp` as the C boundary. No SDL, browser, Python runtime or additional
native dependencies are required beyond a C/C++17 toolchain, Make and pthreads.

The original [GPL/EA notices](../../MicropolisGPLLicenseNotice.md),
[GPL](../../gpl-3.0.txt), and [name license](../../MicropolisPublicNameLicense.md)
still apply. This is a modified version of the engine (2026-10-16), not an EA
product. Micropolis is a registered trademark of Micropolis Corporation
(Micropolis GmbH) and is licensed here as a courtesy of the owner under the
Micropolis Public Name License. See <https://www.micropolis.com>.

## Linux and macOS Make build

Run from the repository root:

```sh
make -f packages/micropolis-engine/native.mk -j4
make -f packages/micropolis-engine/native.mk -j4 test
ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1 \
  make -f packages/micropolis-engine/native.mk SANITIZE=1 -j4 test
```

Outputs are ignored under `build/native/` and `build/native-sanitized/`:
`libmicropolis_native.a`, `core_test`, `api_test`, object files and generated cities.
The sanitizer setting selects a separate directory to avoid reusing plain objects.
`BUILD_DIR=/absolute/path/to/build/...`, `CXX=clang++` and `CC=clang` can be set on
the Make command line. Keep output directories out of source control.

ASan/UBSan remain enabled for the sanitizer run. `detect_leaks=0` is needed in the
Codex Cloud sandbox because LeakSanitizer fails under its ptrace restrictions;
it is not evidence that leak checking passed. On a normal Mac or Linux host,
omit that setting or use `ASAN_OPTIONS=detect_leaks=1` to check leaks as well.
Do not ignore an actual sanitizer diagnostic.

The tests exercise construction on dirty memory, destruction before init,
reinitialization, pooled sprite strings, generation, tools/funds, 2,000 ticks,
pause/resume, haight.cty, all eight bundled scenario files, known-byte city
fixtures, negative funds, funding fractions, map/mop order, failed I/O, and
ownership/concurrent reads through a **pure C** consumer.

The historical loader intentionally reseeds the simulation from the clock and
scans roads/zones on load, refreshing traffic and other derived tiles. Therefore,
a running city's map is not promised to be bit-for-bit identical after load, nor
is the random stream continued from the save file. Tests separately verify exact
serialized bytes, raw decoding, full C/C++ map equivalence on a static fixture,
and successful simulation of real cities. This retains legacy initialization.

## C interface

Include [`native/include/micropolis_native.h`](native/include/micropolis_native.h).
The header is C11 compatible and also provides `extern "C"` for C++ consumers.
It contains the versioned constants, result codes, tool identifiers and snapshot
layout. No C++ objects, `long`, pointers to engine storage or JS values cross it.

- `mp_create` initializes a funded empty city and transfers ownership of one
  opaque `MPGame*`. `mp_destroy` releases it; NULL destruction is harmless.
- `mp_generate` creates a new city with the requested terrain seed and default
  runtime state. `mp_step`, `mp_set_speed` (0..3) and `mp_set_paused` drive time.
  Pausing remembers the selected speed; speed 0 is allowed without setting pause.
- `mp_get_snapshot` copies time, funds, population, speed/pause, date, funding
  fractions and a conservative revision counter. `mp_set_funding` accepts finite
  fractions 0..1. The classic format quantizes fractions to 1/65536.
- `mp_copy_map` copies the main or auxiliary map into caller-owned 12,000-element
  `uint16_t` storage. Output is **row-major** `y*120+x`, while engine/file storage
  is column-major `x*100+y`. Values include tile flags; use `value & 0x03ff` for ID.
- `mp_build` supports road, R/C/I, bulldozer, wire, railway, park and coal power.
  It delegates footprint, terrain and funding checks to `doTool` and returns
  distinct errors for insufficient funds, clearing required and other rejection.
- `mp_load_city` reads 27,120-byte classic and 51,120-byte map+mop files. Failed
  load leaves the previous engine in place. Successful load starts at speed 3,
  unpaused, matching the legacy loader's default rather than restoring pause.
- `mp_save_city` writes map+mop format via a temporary sibling and atomic rename.
  Failure preserves an existing destination; this is not a power-loss/fsync
  durability guarantee. The frontend must obtain filesystem/sandbox permission.

Check every `MPResult`. `mp_result_string` returns a static immutable string,
which the caller must never free. Buffers and C string paths must stay valid
through the call; the API does not retain them. No C++ exception crosses the ABI.
After an allocation/internal failure during a mutation, recreate that handle
because the operation may have partially changed it. Generate/load prepare a new
engine before replacing the old one, so their failures preserve the current city.

One handle's calls are mutex-serialized. Different handles have independent
simulation state. The caller must prevent destruction during any operation and
must not use stale/double-freed handles. Prefer one serial EngineSession per city
and publish copied state to the UI; do not hold engine pointers in views.

This initial frontend polls state. Sounds, messages, robots, scripted churches,
manually confirmed budgets and UI dialogs are not exposed yet; its native
callback adapter is intentionally silent. Automatic budget behavior is the
engine default. A future interactive frontend needs typed queued events and a
budget-response operation; rendering alone does not supply those UI features.

## Swift Package and Xcode (Apple Silicon)

`Package.swift` defines:

- `MicropolisNative`: C/C++ library, with the public C header imported as a Clang
  module. It compiles the shared sources directly, with C++17, without copies.
- `NativeSmoke`: small Swift command-line example with handle ownership, map
  copying, loading, road construction and 2,000 simulation ticks. No SwiftUI.

On an M1 or later Mac with Xcode selected, from the repository root:

```sh
xcode-select -p
xcrun --sdk macosx --show-sdk-path
xcrun swift build --package-path packages/micropolis-engine \
  --scratch-path build/swift-native --arch arm64
xcrun swift run --package-path packages/micropolis-engine \
  --scratch-path build/swift-native --arch arm64 NativeSmoke
xcrun swift run --package-path packages/micropolis-engine \
  --scratch-path build/swift-native --arch arm64 NativeSmoke \
  "$PWD/content/micropolis/cities/haight.cty"
make -f packages/micropolis-engine/native.mk CXX='xcrun clang++' CC='xcrun clang' test
```

SwiftPM handles the C++ runtime link. With Xcode, add this directory as a **local
package**, select `MicropolisNative` for the app target, then `import
MicropolisNative`. Swift C++ interoperability and an Objective-C++ bridge are
not required. When linking the Make static archive manually, add the public
header search path/Clang module and link Apple's `libc++` (`-lc++`); build the
archive with an arm64 Apple Clang target. Do not link Linux `.a` files on macOS.
No additional engine-specific frameworks are required. The package targets
macOS 13 or later; only arm64 needs to be built initially.

[`examples/swift/main.swift`](examples/swift/main.swift) is the executable example.
For a sandboxed app, keep security-scoped URL access active throughout a load or
save. No city data, graphics or sound assets are copied into the package. Bundle
only selected resources with confirmed redistribution rights.

The Swift manifest, Clang import and example were built and run on Apple M1
with Xcode 27.1 / Swift 6.4. The native SwiftUI app is in `apps/micropolis-macos`. Linux native tests do not validate macOS SDK,
arm64 ABI, signing, sandbox integration or SwiftUI rendering.

## Isolated WASM regression

With a working Emscripten toolchain and installed workspace JavaScript dependencies:

```sh
python3 packages/micropolis-engine/tests/native/verify_wasm.py --emxx em++
```

This compiles the updated original Web/Embind target under `build/wasm-regression`,
copies the web app there, substitutes only the copied artifacts, and runs its
unchanged Vitest/CLI suite. It then builds/runs the shared core tests as wasm32,
including file-byte and funding checks. The larger stack is only for the C++ test
program's stack-allocated dirty-storage fixture. Production WASM flags are not
changed. Original JS/WASM/data hashes are checked even if the runner fails.
The command never invokes `make install` or modifies existing generated bindings.

The CLI tests use local IPC through tsx, so the host must permit local sockets.
A socket-permission failure is an environment failure; do not disable those tests.

## Gameplay API additions (2026-10-17)

The existing ABI version 1 `MPSnapshot`, original tool IDs and .cty format are
unchanged. New native-only C entry points and the separate `MPDetails` structure:

- `mp_build` additionally accepts nuclear power, police/fire stations, stadium,
  seaport and airport (tool IDs 10–15). All 15 tools call the existing `doTool`.
  Hospitals emerge from residential demand; there is no school or manual
  hospital construction tool. No placeholder tool or frontend map-writing exists.
- `mp_get_details` copies engine tax income, required service budgets, assessed
  value, score/approval/class, power counts, demand, crime/pollution/traffic and
  disaster/automatic-budget flags. Initial loaded-city population/evaluation is
  refreshed on engine updates; the UI indicates this pending census.
- `mp_configure_budget` atomically sets tax 0–20 and finite service fractions
  0–1, enabling automatic budgets. Actual taxation, funding limits and annual
  spending remain in the engine; there is no new frontend financial model.
- `mp_set_disasters` controls random disasters. `mp_trigger_disaster` invokes
  existing fire, flood, tornado, earthquake, monster or meltdown functions.
  Effect depends on the current city; a successful call does not promise damage.

`native.mk test` now also runs `gameplay_test`: all tools, powered growth,
save/destroy/recreate/load/continue, fiscal persistence, 328,000 total ticks,
20 generation/load cycles and six disaster operations. ASan/UBSan are supported
by the same `SANITIZE=1` target. The shared engine and browser bindings have not
been changed by these additions. The SwiftUI integration uses scoped URL access
and NSFileCoordinator. For sandboxed saves, it calls the existing C save API in
an OS-provided item replacement directory, then uses FileManager to replace or
move the completed file to the selected URL. The C API's sibling temporary files
therefore stay inside the replacement directory rather than beside the user's
selected file. A separate signed sandbox probe verifies this file-grant boundary.

## Original tile animation (2026-10-21)

`mp_animate_tiles` advances one visual frame with the existing C++
`animateTiles()` table. It preserves map status flags and does not advance city
time or change funds. Paused cities, speed zero and disabled animation are
unchanged. `mp_step` retains its existing contract; the macOS EngineSession calls
the new function once after each nonempty tick batch (normally 100 ms).
`animation_test` checks all 1024 IDs and 32 frames against the existing core.
No shared simulation logic, Web/WASM binding or .cty format is changed.

## MicropolisJ機能向けの追加API（2026-10-22）

既存ABI v1のMPSnapshot/MPDetailsと既存関数を維持し、コピー型APIを追加した。

- `mp_copy_overlay`は人口・成長・地価・犯罪・汚染・交通・電力・消防・警察をworld座標のrow-major12,000値で返す。履歴は`mp_copy_history`の6種×2期間、各120値、最新が先頭。
- `mp_inspect`は既存のqueryツール結果を返す。無料。地面を不明扱いする既存categoryの問題だけをnative境界で補正。
- `mp_edit_stroke`は最大12,000点。仮エンジンへツールに必要なmaps/資金/autoBulldoze/animation/RNGをコピーし、既存doToolのみで料金・配置を求める。previewは実都市を変更せず、commitは全体資金不足時にmaps/資金/RNGを変更しない。無効な場所はスキップする。確定前表示と実確定の間に都市が変わった場合、確定時の都市で再計算する。
- `mp_generate_level`と`mp_set_options`は難易度・初期資金・自動撤去・自動予算。途中難易度変更は資金をリセットしない。misc15は既存の標準難易度フィールドとしてnative境界で保存・復元する。
- `mp_step`は自動予算OFFの決算phase直前で早く停止し、pauseする。`mp_get_options().budget_pending`を確認し、予算を設定→`mp_accept_budget`→`mp_set_paused(0)`で継続する。承認前resumeと保存は拒否する（保存の新結果`MP_BUDGET_PENDING`）。承認待ちphaseは従来.ctyで表現できないためで、既存保存先は変更しない。
- `mp_quote_budget`は仮エンジンで現在の集計値に対する年次見積りを計算し、実資金は変えない。Javaの期間内escrow集計を再実装しない。
- `mp_copy_finances`は直近120決算の明細。runtimeのみ。財政明細は実際の決算前後の資金差を基に記録する。C++自動予算のSpendカウンターが全要求額を入れる既存不整合は、native境界でcoreの承認済ValueとupdateFundEffectsを使って補正する。共有srcとWeb/WASMの挙動は変更しない。
- `mp_poll_events`（128件）・`mp_poll_sounds`（32件）は有界キューをコピーしてdrainする。`mp_set_sound_events(1)`でcore音声イベントを許可。再生はフロントエンド側。`mp_copy_sprites`は7種の有効スプライトのコピーで、capacity queryに対応する。
- `mp_save_city`は従来51120-byte拡張形式のまま。`mp_save_city_classic`は27120-byteを原子置換し、補助mapが非0なら欠落防止のため拒否する。Java v2のFile loaderは拡張形式を誤ってヘッダー付きと扱うため、SwiftUIは補助mapが空の都市にclassicを使う。

詳細な基準版・差異・検証は[機能比較表](../../documentation/notes/engine/native-macos-micropolisj-parity.ja.md)を参照。
