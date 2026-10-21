# nix-cacert-harness

> [!WARNING]
> **AI Disclosure**: This whole repository (scripts, Nix expressions, shims, README and RESULTS)
> was generated with Claude Code, a mix of Claude Fable 5.1 and Claude Opus 5.5 (Opus wrote the
> scripts, Fable orchestrated and packaged them), and has only been lightly reviewed by a human.
> It exists to verify AI-assisted nixpkgs changes under the
> [nixpkgs AI policy](https://github.com/NixOS/nixpkgs/blob/master/CONTRIBUTING.md#automationai-policy),
> so read its own output with that in mind: it is published so it can be reviewed, and RESULTS.md
> records what was actually run. The static check wraps
> [zimbatm/nix-cacert-scan](https://github.com/zimbatm/nix-cacert-scan); the before/after plumbing,
> the behavioral test and the negative control are this repository's own.

Per-package evidence for the campaign in NixOS/nixpkgs#576475 (#576541 PEM bundles,
#576543 Java keystores). For one attribute it shows that:

- **before** the fix (the base commit) the package trusted CAs that `cacert` does not trust
  (or ignored `cacert` entirely), and
- **after** the fix (the worktree) it trusts exactly what `cacert` trusts and follows `cacert`
  when `cacert` changes.

There are two tools. They share the same before/after plumbing and need no checkout.

| | `bin/ca-static-check` (approach 1) | `bin/ca-behave-check` (approach 2) |
|---|---|---|
| question | Which trust stores ship in the output, and do they equal cacert? | Does the program accept a root only when that root is in `cacert`? |
| proves | set equality of the store file(s) with cacert's TLS roots | trust is *wired* to cacert at runtime |
| per-package work | none | a shim of 3 to 10 lines (`shims/<attr>.nix` or `.sh`); families can share one |
| cost | build/fetch both sides, then about 1 to 2 min of scanning | one extra rebuild of the package with a modified cacert, plus about 1 min |
| status | **tested** (2 packages, a known-good sample, a negative control, the scanner fallback) | **tested** for one Python library (installed package and `dist` wheel), two binary JDKs (temurin, zulu) and wordpress, plus a negative control |

## For reviewers: one command, no checkout

```sh
# a NixOS/nixpkgs pull request: base and head commits are read from GitHub
nix run github:irgolic/nix-cacert-harness -- <attr> --pr <N>

# a commit (PR head, or github:OWNER/REPO/SHA for a fork); "before" is its parent
nix run github:irgolic/nix-cacert-harness -- <attr> --after <sha>

# explicit before/after
nix run github:irgolic/nix-cacert-harness -- <attr> --base <sha> --after <sha>
```

Both sides are fetched as GitHub archive tarballs into the nix store (PR head commits of a
fork are served through the base repository's archive URL). The static check always runs; the
behavioral check runs when `shims/<attr>.nix` exists (currently: `python3Packages.httplib2`, `wordpress`,
`temurin-bin`, `temurin-jre-bin`, `zulu`, `openjdk`, `jre_minimal`, `python3Packages.raven`, `graalvmPackages.graalvm-ce`, `gam`, `scilab-bin`, `julia-bin`, `julia_110-bin`, `rubyPackages.excon`, `rubyPackages.httpclient`, `rubyPackages.nap`, `rubyPackages.algoliasearch`, `invoiceplane`; any JVM can reuse
`shims/java-runtime.nix`, any Python library `shims/python-lib.nix`, any Ruby gem `shims/ruby-gem.nix`). `--shim NAME` picks another
shim from `shims/` (and runs the behavioral check even without `shims/<attr>.nix`), e.g. `--shim python-wheel` tests the wheel in a Python package's `dist` output
instead of the installed package. Results and logs land in
`${XDG_CACHE_HOME:-~/.cache}/nix-cacert-harness/<attr>/`. Builds are bounded to 3 at a time,
4 cores each, and a side whose dry-run shows a long from-source build is skipped (diff-only)
unless `--force-build` is given. `nix` and `git` are taken from your PATH.

Inside a nixpkgs checkout the arguments are optional: "before" is the merge-base of HEAD with
`upstream/master`, `origin/master` or `master`, and "after" is the working tree.

### Example: the merged wordpress fix, NixOS/nixpkgs#576572

```console
$ nix run github:irgolic/nix-cacert-harness -- wordpress --pr 576572
PR #576572: wordpress_*: use cacert bundle instead of vendored bundle  base=808311374c3a head=d305233a9b6e
reference: fprs4zi8r6227x12qbsd1grvfrpz6201-nss-cacert-3.131.1 TLS roots=118 all=169
==================================================================
ATTR wordpress
before: github:NixOS/nixpkgs/808311374c3ab66fdf82ffff5e8bfc9e5d327786   after: github:NixOS/nixpkgs/d305233a9b6e1acc118fc94772db64a83e61cdac
before ok (0 built, 0s)
        drv /nix/store/l058nd6s2xddzwxp43d2pyccarlwf51l-wordpress-7.1.3.drv
after  ok (0 built, 0s)
        drv /nix/store/k9si7khhxfkl3vjl6ndlk484w88r52dv-wordpress-7.1.3.drv
| output:path | before | after |
|---|---|---|
| out:/share/wordpress/wp-includes/certificates/ca-bundle.crt | pem 119 certs: 4 not in cacert, 1 in cacert but not for TLS, 4 cacert TLS roots missing; scanner: ECC G3 | symlink->cacert:ca-no-trust-rules-bundle.crt pem 118 certs == cacert |
cacert in runtime closure (before): no
cacert in runtime closure (after): yes
CAs trusted before but not trusted for TLS by cacert (5 total), e.g.:
  - C=IN, OU=emSign PKI, O=eMudhra Technologies Limited, CN=emSign ECC Root CA - G3
  - C=US, OU=emSign PKI, O=eMudhra Inc, CN=emSign ECC Root CA - C3
  - C=US, OU=emSign PKI, O=eMudhra Inc, CN=emSign Root CA - C1
  - CN=Atos TrustedRoot 2011, O=Atos, C=DE
  - C=TW, O=Chunghwa Telecom Co., Ltd., OU=ePKI Root Certification Authority
VERDICT wordpress: FIXED: before trusted CAs outside cacert; after: 1 store(s) == cacert, none with extra CAs

base=github:NixOS/nixpkgs/808311374c3ab66fdf82ffff5e8bfc9e5d327786 shim=shims/wordpress.nix
  package derivations to build for the matrix: 3 php-extra-init-8.5.11.ini.drv php-with-extensions-8.5.11.drv wordpress-7.1.3.drv
  matrix build: 15s (incl. waiting for a nixb slot)
  before-stock: REFUSED -> /nix/store/c5q60innznwa6v0p6ai2l4h7w1sysz3g-ca-behave-wordpress-stock
  before-test: REFUSED -> /nix/store/9vhqwzg1ja68vpshdahk2w1lkczrvfjm-ca-behave-wordpress-test
  after-stock: REFUSED -> /nix/store/6lp65wx0a7mmjsp6wmyzqwbs9fnbb4bk-ca-behave-wordpress-stock
  after-test: CONNECTED -> /nix/store/1zhj54jyckjrvj9k9fyi1w83cxiq7y63-ca-behave-wordpress-test
wordpress  (before github:NixOS/nixpkgs/808311374c3a…, after github:NixOS/nixpkgs/d305233a9b6e…)
         | stock cacert | + test root  | override with test-root cacert
before   | REFUSED      | REFUSED      | NO-OP (package does not take cacert)
after    | REFUSED      | CONNECTED    | yes (rebuilt with cacert + test root)
control (before cells): curl --cacert test-root: CONNECTED, curl --cacert stock: REFUSED
VERDICT wordpress: PASS: after-fix trust follows cacert; before-fix ignores it
```

78 seconds on a warm machine (two nixpkgs tarballs fetched, wordpress and a php built). Reading it:

- **Static table**: the vendored bundle before (119 certs, 4 of them roots cacert does not trust,
  including emSign ECC Root CA - G3) versus a symlink into cacert after, equal to cacert's 118 roots.
- **Behavioral matrix**: before the fix, adding a root to cacert changes nothing (the bundle is
  frozen). After, the program connects exactly when the root is in cacert.
- **Controls**: `curl` with the test root connects and `curl` with stock cacert refuses, so the
  server was up and the refusals are certificate errors, not networking failures.
- Each cell is a store path you can inspect: `shim.log` has the program's own output.

## Layout

```
bin/ca-check             one command per package: static, then behavioral if a shim exists (--pr/--after/--base)
bin/ca-static-check      approach 1 (before/after table of trust stores vs cacert)
bin/ca-behave-check      approach 2 (2x2 behavioral matrix in the nix sandbox)
bin/gen-test-ca          one-time generation of the throwaway test root + localhost leaf
lib/common.sh            base resolution, fetchGit export, dry-run policy, cert-set helpers
lib/certset.py           fast PEM -> SHA-256 fingerprint + subject (stdlib only, one process)
lib/tools.nix            openssl, jq, curl, gawk, python3, keytool (jre_minimal), taken from the base
lib/nixpkgs.nix          nixpkgs + optional overlay (to try a fix before editing the tree)
lib/behave.nix           one behavioral cell (side x cacert variant)
lib/matrix.nix           the four cells as one attrset (one nixb queue slot)
probes/TlsProbe.java     HTTPS probe for any JVM (compiled with --release 8)
shims/                   per-package "make it do one HTTPS GET to $URL" snippets
fixtures/                test root + leaf. The keys are public test material: never trust the root.
fixes/                   overlays for --after-overlay (a NEGATIVE control; julia_*-bin without the install check)
out/<attr>/{static,behave}/   working files, scanner JSON, cell results (symlinks to store paths)
logs/                    console output of the runs in RESULTS.md
out-negative/, out-fallback/  working files of the negative-control and no-scanner runs
```

## Shared plumbing

- **Base ("before")**: `git merge-base HEAD upstream/master` in `$CAH_REPO`
  (the nixpkgs checkout you run it from, or `$CAH_REPO`). The fallback is `cacert-devendor`; `--base REV` overrides both.
  The commit is exported read-only with
  `builtins.fetchGit { url = $CAH_REPO; rev = …; shallow = true; }`, which copies
  the tree into the store. The first export takes about 100 s, later runs are cached. Nothing
  touches HEAD, the index or the worktree, so concurrent edits by other agents are safe.
- **After**: the live worktree (`-f $CAH_REPO`), optionally with
  `--after-overlay FILE` to simulate a fix without editing the tree. It was exercised with
  `fixes/bad-temurin-password-keystore.nix`, a deliberately broken variant of the real fix
  used as a negative control. The overlay must keep the package `callPackage`-overridable
  (use `overrideAttrs` on `prev.<attr>`, or `callPackage` a wrapper that takes `cacert`), so
  that the behavioral injection still reaches it.
- **Builds**:
  - Every build goes through the `nixb` wrapper (`$CAH_NIXB`).
  - When all requested outputs are already valid store paths (`nix path-info`), nothing is
    built or fetched, and the queue is skipped.
  - Every side is dry-run first. If a side would build more than `CAH_MAX_BUILDS` (4)
    derivations, or anything matching `CAH_HEAVY_RE` (julia, graalvm, openjdk, llvm, rustc,
    qtwebengine, ...), it is **skipped**. The static check then prints `git diff <base> -- <pkg dir>`
    instead (diff-only). Use `--force-build` to override.
- **Tools** (openssl, keytool, python3, ...) always come from the *base* nixpkgs. A
  concurrent edit to, say, openjdk in the worktree can therefore never force a JDK rebuild
  just to get `keytool`.

## Approach 1: static store check (`ca-static-check`)

```
bin/ca-static-check [--base REV] [--after-overlay FILE] [--dry-run-only] [--force-build] ATTR...
```

For each side it:

1. evaluates `drvPath`. When both sides have the same drv, it reports "no fix in worktree".
2. dry-runs and builds `ATTR^*`, i.e. all outputs. Python `dist` wheels are included.
3. runs the pinned scanner
   `github:zimbatm/nix-cacert-scan/3bae26b…` (`cacert-scan --path <real out path>`, JSON) on
   each output.
   - The scanner flags files with ≥20 known roots, a watched root (`emSign ECC Root CA - G3`,
     `AAA Certificate Services`), or JKS/PKCS12 magic.
   - If the scanner cannot be built, the tool falls back to a heuristic: files with ≥20
     `BEGIN CERTIFICATE` blocks, plus keystore magic bytes. The fallback was tested. It does
     not look inside archives, so wheel/jar copies go unreported in that mode.
   - The scanner ignores symlinks, and also returns nothing when handed a `result` symlink.
     The harness therefore resolves out paths and finds symlinks into `-nss-cacert-` itself.
4. turns every candidate path, on both sides, into a **set of SHA-256 fingerprints**:
   - PEM files go through `lib/certset.py`. It handles `TRUSTED CERTIFICATE` blocks by hashing
     only the leading certificate TLV.
   - Keystores go through `keytool -list -v`. It tries without a password first (which is how
     the JDK itself opens `cacerts`), then with `changeit`. A file named `cacerts` that
     *needs* a password is a PKCS12 with encrypted cert bags. The JDK sees it as empty, so it
     is flagged and counted as bad (see the negative control in RESULTS.md).
5. compares each set with the reference, which is the after side's `cacert`:
   - **TLS set**: `ca-no-trust-rules-bundle.crt`, 118 roots in NSS 3.131.1. This is also what
     `jre-generate-cacerts` puts in a keystore.
   - **all**: `unbundled` + `ca-bundle.crt`, 169 roots. This also contains roots that are only
     trusted for e-mail, such as Comodo "AAA Certificate Services".
6. prints one table row per store, e.g.

   ```
   | out:/lib/python3.14/site-packages/httplib2/cacerts.txt
   | pem 71 certs: 55 not in cacert, 8 in cacert but not for TLS, 110 cacert TLS roots missing; scanner: AAA
   | symlink->cacert:ca-no-trust-rules-bundle.crt pem 118 certs == cacert |
   ```

   It then prints the names of the CAs that were trusted before but are not trusted by cacert,
   whether `cacert` is in each side's runtime closure, and a VERDICT:
   - `FIXED`
   - `NOT FIXED`
   - `NOT FIXED (unchanged)`
   - `NOTHING DETECTED`
   - `INCOMPLETE` (a side was skipped)

   Bundles found *inside* archives (wheels, jars) are listed separately, from the scanner's
   findings. A symlink in the installed output cannot reach them (the #576542 class). A fix that
   changes the file in the source before the archive is built can, e.g. a `postPatch` symlink
   (botocore in NixOS/nixpkgs#490115, httplib2). A member whose sha256 equals a cacert bundle is
   reported as a byte-identical copy of it, like a real file, and is not counted as remaining.

Rules for "bad":
- A store is bad if it holds any certificate that cacert does not trust for TLS. That
  covers roots outside cacert, and cacert roots that are only trusted for e-mail.
- An unreadable keystore is also bad, because we can't prove anything about it.
- So is a `cacerts` keystore that only lists with a password, because the JVM sees no trust
  anchors in it.
- A symlink into cacert, or a byte-identical copy of a cacert bundle, is good by definition.
  This holds even for `ca-bundle.crt`, which carries non-TLS roots as trust-rule blocks that
  OpenSSL honours.

## Approach 2: behavioral check (`ca-behave-check`)

We can't get a leaf signed by a compromised root. Instead we show that the program's trust
*is a function of cacert*.

- `bin/gen-test-ca` (run once) creates a throwaway root and a `localhost` leaf (RSA-2048,
  SAN `localhost`/`127.0.0.1`/`::1`). The extensions are strict enough for Python 3.13+
  `VERIFY_X509_STRICT`.
- `cacertTest = cacert.override { extraCertificateFiles = [ fixtures/root.pem ]; }`. This is
  the stock cacert plus one root.
- **Injection**: by default, if the package's function takes a `cacert` argument
  (`lib.functionArgs pkg.override ? cacert`), the test variant is `pkg.override { cacert =
  cacertTest; }`. Otherwise the package is used unchanged.
  - A before-fix package almost never takes `cacert`, so for it the "test" cell is the same
    build as "stock" (reported as `NO-OP`). That is the claim being tested: its trust store is
    not a function of cacert.
  - A shim may supply its own `inject = pkg: cacert: …` for fixes that route through another
    package, for example certifi or a bundled `jre`.
- **Cell** (`lib/behave.nix`): a `runCommand` in the nix build sandbox, which has a private
  network namespace with only loopback, no `/etc/ssl`, and runs:
  1. `openssl s_server -www` on port 8443 with the test leaf;
  2. two **controls**:
     - `curl --cacert root.pem` must give CONNECTED;
     - `curl --cacert <stock cacert>` must fail with curl exit 60, i.e. REFUSED;
  3. the **shim**, under `env -i`: no `SSL_CERT_FILE`, `NIX_SSL_CERT_FILE` or
     `REQUESTS_CA_BUNDLE`, and so on.
  4. a result:
     - `CONNECTED` when the shim exits 0;
     - `REFUSED` only if its log shows a certificate-verification error (OpenSSL, Java PKIX,
       Go x509, GnuTLS, and libcurl's "SSL certificate problem" and mbedTLS "BADCERT_NOT_TRUSTED" wording);
     - `ERROR` for anything else, so that a broken shim can never pass as a refusal.

  The result is stored in the cell's output (`result`, `shim.log`, `info`), so it is cached
  and reproducible. Use `--rerun` to force a new run.
- `lib/matrix.nix` builds the four cells {before, after} × {stock, test} with **one** nixb
  call (`--keep-going`).

Expected matrix:

|        | stock cacert | cacert + test root | meaning |
|--------|--------------|--------------------|---------|
| before | REFUSED      | REFUSED (override NO-OP) | trust store frozen / ignores cacert |
| after  | REFUSED      | **CONNECTED** (rebuilt with test-root cacert) | trust follows cacert |

The verdict depends on the result:
- **PASS**: exactly this matrix, with both controls OK.
- **FAIL**: one of
  - `after-test` is REFUSED (not wired);
  - `after-stock` is CONNECTED (no verification, or an environment leak);
  - `after-test` is ERROR. The JVM's "trustAnchors parameter must be non-empty" gets a
    dedicated message: an empty or password-protected keystore.
- **INCONCLUSIVE**: the after-side injection was a NO-OP, i.e. the package's function does
  not take `cacert`. Trust then comes through a dependency. Example: `jre_minimal` is
  jlinked from openjdk, so proving it means rebuilding openjdk. Write an `inject`, or rely on
  approach 1.
- **SKIPPED**: the dry-run shows a heavy rebuild.
- **INVALID**: a control failed.

Together with approach 1, which shows the after store contains exactly cacert's set, this
shows "trusts exactly what cacert trusts". Approach 2 alone only shows "follows cacert".

### Shims

A shim makes the program do one HTTPS GET of `$URL`. Its exit code is 0 only if the response
came back over a verified connection. The variables `$URL`, `$HOST`, `$PORT`, `$PKG`
(package under test) and `$CACERT` (the cacert of this cell) are available.

- `shims/<attr>.sh`: a plain shell snippet with `$PKG/bin` on PATH, for CLIs. Note that a
  deletion-style fix (nmap, netsurf: the program already used the system store and only the
  stale extra bundle was removed) has nothing to prove behaviorally; the static scan is the evidence.
- `shims/<attr>.nix`: `{ pkg, pkgs, lib, probes, cacert }: { inputs = [ … ]; script = "…";
  inject = pkg: cacert: …; }`. `inject` is optional: the default is `pkg.override { cacert = … }` when
  `cacert` is a declared argument of the package function. Packages that take it through `...`
  (zulu) need an explicit `inject` (see `shims/zulu.nix`); the harness reports NO-OP otherwise.
  Use a `.nix` shim for anything that needs an interpreter or wrapper.
  - `shims/python-lib.nix`: `python.withPackages [ pkg ]`, `python3 -I`, one request. It is
    written for httplib2. For another library, copy it and change the 3-line snippet.
  - `shims/python-wheel.nix` (`--shim python-wheel`): the same request against the wheel in the
    package's `dist` output. It installs the wheel offline into the sandbox (`pip install
    --no-index --no-deps --target`), with an interpreter that has pip and the package's Python
    dependencies but not the package, and checks that the import comes from the wheel. The
    test variant rebuilds the package, so the wheel is rebuilt with the test-root cacert and the
    expected matrix is the same as for the installed package.
  - `shims/java-runtime.nix`: `java -cp ${probes.java} TlsProbe $URL`. It works for any
    JDK/JRE attr, and is symlinked as `temurin-jre-bin`, `temurin-bin`, `openjdk`,
    `jre_minimal`. `shims/zulu.nix` runs the same probe with its own `inject`.
  - For apps that bundle a jlink'd runtime, use `"$PKG/<runtime>/bin/java"` in the same line.
    The probe only needs `java.base`.

Sketched, untested shim ideas for other families:
- **PHP/composer apps**: `php -r` that `require`s the app's
  `vendor/autoload.php` and opens `$URL` with `stream_context_create(['ssl' => ['cafile' =>
  CaBundle::getBundledCaBundlePath()]])`, or with the app's own HTTP helper.
- **Ruby gems**: `ruby -e` with the gem's client. Now done: `shims/ruby-gem.nix` (see "To add a package to the behavioral check").
- **ncat / curl-like CLIs**: `.sh` shims.

GUI apps, servers and archive-embedded bundles are not practical to drive this way. Use
approach 1 for those.

## How to run (per package)

```sh
H=/path/to/cacert-harness
$H/bin/ca-check <attr>          # both: static always, behavioral if shims/<attr>.{nix,sh} exists
$H/bin/ca-static-check <attr>   # approach 1 only (any package, several attrs allowed)
$H/bin/ca-behave-check <attr>   # approach 2 only
# options: --base REV  --after-overlay fix.nix  --force-build
#          behavioral only: --shim NAME|FILE (NAME = shims/NAME.nix or .sh)  --sides after  --rerun
# env: CAH_REPO, CAH_OUT (default $H/out), CAH_NIXB, CAH_MAX_BUILDS, CAH_HEAVY_RE, CAH_SCANNER_REF
```

To add a package to the behavioral check:
- **JVM**: `ln -s java-runtime.nix shims/<attr>.nix`.
- **Python library**: copy `python-lib.nix` and edit the 3-line snippet. Its wheel: copy
  `python-wheel.nix` the same way, and run with `--shim <name>`.
- **Ruby gem** (gem-config fixes): a `shims/rubyPackages.<gem>.nix` of the form
  `args: import ./ruby-gem.nix args { require = "..."; code = "..."; }` (see `rubyPackages.excon.nix`);
  `ruby-gem.nix` injects the test cacert through `defaultGemConfig.override { cacert }`.
- **CLI**: write `shims/<attr>.sh`.

The output goes to stdout. Per-package working files (scanner JSON, to-build lists, cell
links with `shim.log`/`info`) go under `$CAH_OUT/<attr>/`.

## How long it takes

Times were measured on this machine, which has 16 cores and was loaded (load average around
10) by six to eight other agents' builds. Wall time is dominated by waiting for a `nixb` slot:
there are 3 slots machine-wide, polled every 5 s.

**One-off costs**
| step | time |
|---|---|
| export the base with fetchGit | about 100 s, then cached |
| build the scanner (Rust, 64 small drvs) | a few minutes, then cached |
| tools env | seconds |
| Java probe | needs `jdk_headless` from the cache, a 415 MiB fetch |
| `cacert + test root` | seconds |

**Static check, per package**
| situation | time |
|---|---|
| both sides already in the store | **18 to 26 s** (httplib2, temurin-jre-bin) |
| two attrs in one call | 50 s |
| one side needs a rebuild | add that build and any queue wait, e.g. 69 s for temurin-jre-bin with an overlay |
| first run | add about 30 s to compute and cache the cacert reference sets |

Most of the time is nix evaluation, about 10 s per side.

**Behavioral check, per package**
| situation | time |
|---|---|
| first run, package rebuilt once with the test-root cacert | **70 to 90 s** in total; the matrix build was 55 to 61 s, queue wait included |
| everything cached | about 20 s |
| decision to skip a heavy package | about 8 s |
| before the matrix was batched into one `nixb` call | a single cell once waited 553 s for a slot |

**One-command run (`ca-check`, everything cached)**
| package | time |
|---|---|
| httplib2 | 38 s |

For about 60 packages, expect the cost of rebuilding each package once more, with the
test-root cacert, plus about 1 min each. Heavy packages are skipped automatically.

## Limitations

- Approach 1 only sees what the scanner (or the fallback) flags. Roots compiled into
  binaries as DER (webpki and friends, the #576544 class) show up as findings but cannot be
  turned into a fingerprint set ("0 certs readable"), so they are counted as bad.
- "== cacert" proves the *file* is right, not that the program reads that file. A fix that
  points the program elsewhere, or a program with a second hard-coded store, needs approach 2.
- The reference is the cacert of the after side. A store that is *missing* cacert roots
  (a stale but strict subset) is reported but not counted as bad.
- Approach 2 needs a rebuild of the package with a different cacert. That rules out heavy
  from-source packages (julia, graalvm, openjdk itself, supertuxkart): the policy skips them,
  and they only get approach 1.
  - For example, the known-good openjdk (#576518) can only be checked statically here:
    `jre_minimal` is a jlink of the from-source JDK.
- Default injection is `.override { cacert }`. A fix that wires trust through a different
  attribute (certifi, a nixpkgs `jre`, a wrapper's `NIX_SSL_CERT_FILE`) needs `inject` in the
  shim.
  - A global overlay `cacert = cacertTest` would work for everything, but rebuilds every
    cacert consumer in the closure. Deliberately not done.
- For before-fix packages the "test" cell is a NO-OP, identical to stock. That is correct
  evidence that trust does not depend on cacert. It does not prove the program would refuse a
  *compromised* root that is in its vendored store; approach 1 shows that the root is there.
- The behavioral cells rely on the Linux nix sandbox: a private netns with loopback, and
  `/etc/hosts` for `localhost`. With `sandbox = false`, port 8443 may clash and the host's
  `/etc/ssl` is visible. The environment is still scrubbed, and the test root is never in a
  system store, so this cannot cause false CONNECTED results.
- The worktree is live, and other agents may still be editing the package while a run is in
  progress. The run reports drv paths, so results can be tied to a tree state.
