# Results (2026-10-21)

Full console logs are in `logs/`. Per-package working files are in `out/`, `out-negative/`
and `out-fallback/`.

## Tree state

- When I started, the nixpkgs checkout was on another branch. `upstream/master` was
  the stale `2c2a60006` from 2026-09-04, and there was **no `cacert-devendor` branch**.
- About 15 minutes later the orchestrator switched to `cacert-devendor` and fetched upstream.
  - From then on, **base = `git merge-base HEAD upstream/master` =
    `8915027df75d0403ef013dd0cbf09ff3c602fd03`** (markuplinkchecker 1.2.2 -> 1.3.0, #576610).
  - All results below use this base.
- The brief says openjdk is already fixed by #576518.
  - That is true at `8915027df`: `--with-cacerts-file` is present.
  - It was **not** true at the stale `2c2a60006`.
- The worktree changed during my runs. Agents edited, and the orchestrator committed on
  `cacert-devendor`.
  - At the final runs, HEAD was `ded1277ae`.
  - The fixes under test, as `sha256(git diff 8915027df -- file)[:16]` (see
    `logs/final-tree-state.txt`):
    - `httplib2/default.nix`: 1f0a5ce2126ac817 (already committed);
    - `temurin-bin/jdk-linux-base.nix`: d8fa8143dfa55735 (uncommitted).

## Scanner (approach 1 input)

- `nix run github:zimbatm/nix-cacert-scan` is the closure wrapper (`cacert-scan-closure`).
  - It scans `nix-store -qR` of the path, so every Python package report includes python3's
    own `ensurepip/_bundled/pip-*.whl!certifi/cacert.pem`:
    ```
    python3.14-httplib2-0.32.0  /lib/python3.14/site-packages/httplib2/cacerts.txt  40 roots  AAA
    python3-3.14.8  /lib/python3.14/ensurepip/_bundled/pip-26.2.1-py3-none-any.whl!pip/_vendor/certifi/cacert.pem  115 roots  ECC G3
    ```
  - The harness therefore runs the inner `cacert-scan --path <real out path>` on each output
    only, and reads its JSON (`known_roots`, `watch`, `magic`, `sha256`).
- The scanner was built once through nixb from the pinned rev `3bae26b1140e…`: 64 small drvs,
  output `/nix/store/sx96bvq8xvilan9qi0h226gmahjxbglm-cacert-scan-0.1.0`.
- Quirks found:
  - The scanner skips symlinks (`symlink_metadata`), so a `result` link scans as nothing. The
    harness passes `readlink -f` paths and finds symlinks into cacert itself.
  - Current cacert's own `ca-bundle.crt` triggers the watch for `AAA Certificate Services`
    (an e-mail-only trust-rule block) and for `emSign Root CA - G1`. A raw "watch hit" is
    therefore not proof of a problem, and the harness only counts it for non-cacert files.
- The no-scanner fallback was tested (`logs/static-httplib2-noscanner.txt`): the same
  verdict, but without the wheel finding.

## Approach 1: `ca-static-check` (tested)

### python3Packages.httplib2 (PEM; fixed in the worktree with a symlink to ca-no-trust-rules-bundle.crt)

```
before ok (0 built, 2s)   drv /nix/store/zcbm7nnb1ip6lp7nmjhissd7cfqf2ijw-python3.14-httplib2-0.32.0.drv
after  ok (0 built, 4s)   drv /nix/store/l7sfswzsfkj8523j031lxg2aq0n0276s-python3.14-httplib2-0.32.0.drv
| out:/lib/python3.14/site-packages/httplib2/cacerts.txt
|   before: pem 71 certs: 55 not in cacert, 8 in cacert but not for TLS, 110 cacert TLS roots missing; scanner: AAA
|   after:  symlink->cacert:ca-no-trust-rules-bundle.crt pem 118 certs == cacert
inside archives (scanner only, not fixable by a symlink; issue #576542 class):
  before dist:/httplib2-0.32.0-py3-none-any.whl!httplib2/cacerts.txt  roots=40 trusts AAA Certificate Services
  after  dist:/httplib2-0.32.0-py3-none-any.whl!httplib2/cacerts.txt  roots=40 trusts AAA Certificate Services
cacert in runtime closure (before): no
cacert in runtime closure (after): yes
CAs trusted before but not trusted for TLS by cacert (63 total), e.g.:
  - C=GB, O=Comodo CA Limited, CN=AAA Certificate Services
  - C=BE, O=GlobalSign nv-sa, OU=Root CA, CN=GlobalSign Root CA
  - C=DE, O=TC TrustCenter GmbH, OU=TC TrustCenter Class 2 CA, CN=TC TrustCenter Class 2 CA II
  ...
VERDICT python3Packages.httplib2: FIXED: ... (+ bundles inside archives remain, see above)
```

The `dist` wheel output still carries the old bundle. That is expected for this fix and
belongs to #576542.

(That was the first, `postInstall` version of the fix. The fix branch now makes the symlink in
`postPatch`, so the wheel gets cacert's bundle too: see "python3Packages.httplib2 (fix branch,
postPatch)" below.)

### temurin-jre-bin (Java keystore; fixed in the worktree with jre-generate-cacerts)

```
| out:/lib/security/cacerts
|   before: keystore 118 certs: 4 not in cacert, 1 in cacert but not for TLS, 5 cacert TLS roots missing [no-password]; scanner: ECC G3
|   after:  keystore 118 certs == cacert [no-password]
cacert in runtime closure (before): no
cacert in runtime closure (after): no          <- expected: a keystore keeps no store reference
CAs trusted before but not trusted for TLS by cacert (5 total), e.g.:
  - CN=emSign ECC Root CA - C3, O=eMudhra Inc, OU=emSign PKI, C=US
  - CN=emSign ECC Root CA - G3, O=eMudhra Technologies Limited, OU=emSign PKI, C=IN
  - CN=emSign Root CA - C1, O=eMudhra Inc, OU=emSign PKI, C=US
  - C=DE, O=Atos, CN=Atos TrustedRoot 2011
  - OU=ePKI Root Certification Authority, O="Chunghwa Telecom Co., Ltd.", C=TW
VERDICT temurin-jre-bin: FIXED: before trusted CAs outside cacert; after: 1 store(s) == cacert, none with extra CAs
```

Time: 24 s, with both sides already in the store.

### jre_minimal (known-good sample: openjdk with #576518 at base)

```
| out:/lib/security/cacerts | keystore 118 certs == cacert [no-password] | keystore 118 certs == cacert [no-password] |
VERDICT jre_minimal: NOTHING DETECTED on the before side
```

An earlier run, made while the worktree's *first* temurin fix was in place, is worth
recording. That fix changed `temurin-bin`, and that is openjdk's `jdk-bootstrap`. The dry-run
of the after side therefore showed an openjdk rebuild, and the policy skipped it:

```
after  SKIPPED 2 drvs to build incl. openjdk-21.0.12.1+1.drv
diff-only: git diff 8915027df75d -- pkgs/development/compilers/openjdk     (empty: changed via a dependency)
VERDICT jre_minimal: INCOMPLETE (a side was not built)
```

The agent later added `regenerateCacerts = false` for the bootstrap JDK. After that, the after
drv equals the before drv again.

## Approach 2: `ca-behave-check` (tested for two packages)

### python3Packages.httplib2: PASS

```
  package derivations to build for the matrix: 1 python3.14-httplib2-0.32.0.drv
  matrix build: 61s (incl. waiting for a nixb slot)
         | stock cacert | + test root  | override with test-root cacert
before   | REFUSED      | REFUSED      | NO-OP (package does not take cacert)
after    | REFUSED      | CONNECTED    | yes (rebuilt with cacert + test root)
control (before cells): curl --cacert test-root: CONNECTED, curl --cacert stock: REFUSED
VERDICT python3Packages.httplib2: PASS: after-fix trust follows cacert; before-fix ignores it
```

The shim logs show the mechanism.
- before-test:
  ```
  CA_CERTS = .../site-packages/httplib2/cacerts.txt
  ssl.SSLCertVerificationError: [SSL: CERTIFICATE_VERIFY_FAILED] ... unable to get local issuer certificate
  ```
- after-test:
  ```
  CA_CERTS = .../httplib2/cacerts.txt
  status 200
  ```

Time: 1:26 on the first run, 20 s when cached.

### temurin-jre-bin: PASS

```
  package derivations to build for the matrix: 1 temurin-jre-bin-21.0.12.drv
  matrix build: 55s (incl. waiting for a nixb slot)
before   | REFUSED      | REFUSED      | NO-OP (package does not take cacert)
after    | REFUSED      | CONNECTED    | yes (rebuilt with cacert + test root)
control (before cells): curl --cacert test-root: CONNECTED, curl --cacert stock: REFUSED
VERDICT temurin-jre-bin: PASS: after-fix trust follows cacert; before-fix ignores it
```

- after-test shim log: `OK status=200 cipher=TLS_AES_256_GCM_SHA384`
- before-test shim log: `SSLHandshakeException: (certificate_unknown) PKIX path building failed`

Time: 1:10.

### jre_minimal: INCONCLUSIVE, which is the correct answer

`jre_minimal`'s function does not take `cacert`; its trust comes from openjdk. The injection is
therefore a NO-OP on both sides, and all four cells are REFUSED. A first version of the
verdict logic printed a misleading "FAIL" here. It now says:

```
VERDICT jre_minimal: INCONCLUSIVE: injecting the test-root cacert was a NO-OP on the after side (... its trust
comes from a dependency, e.g. the JDK it is jlinked from). Add an `inject` to the shim, or rely on ca-static-check
```

A behavioral proof for openjdk itself would need an openjdk rebuild. While the first temurin
fix was in place, the policy refused that:

```
  package derivations to build for the matrix: 2 openjdk-21.0.12.1+1.drv openjdk-minimal-jre-21.0.12.1+1.drv
  SKIPPED: 2 drvs to build incl. openjdk-21.0.12.1+1.drv  (use --force-build, or rely on ca-static-check)
```

### Negative control: a broken temurin fix is caught by both tools

`fixes/bad-temurin-password-keystore.nix` takes the worktree fix (the version current at that
time) and drops the `JAVA_TOOL_OPTIONS` lines, so keytool writes a password-encrypted PKCS12.

- **Static**: the first version said `FIXED`, because keytool lists the store fine with
  `changeit`. That is a real gap, now fixed. A `cacerts` that only lists with a password is
  now counted as bad:
  ```
  | out:/lib/security/cacerts | ... | keystore 118 certs == cacert [needs-password(changeit)] (JVM opens cacerts without a password: 0 trust anchors at runtime!) |
  VERDICT temurin-jre-bin: NOT FIXED: an after-side store is not equivalent to cacert (see table)
  ```
- **Behavioral**: this caught it on the first try. Both after cells fail with
  `InvalidAlgorithmParameterException: the trustAnchors parameter must be non-empty`:
  ```
  after    | ERROR        | ERROR        | yes (rebuilt with cacert + test root)
  VERDICT temurin-jre-bin: FAIL: the after-fix JVM sees an EMPTY trust store (password-protected PKCS12 cacerts? ...)
  ```

## Failures and bugs hit along the way (all fixed)

- **javac**: the store file name of `TlsProbe.java` broke `public class TlsProbe`. Now the
  file is copied to `TlsProbe.java` first.
- **Probe ordering**: the probe called `getCipherSuite()` after closing the stream. The first
  temurin after-test therefore ended in `IllegalStateException`, *after* a successful
  handshake. The result classifier correctly reported `ERROR` rather than CONNECTED or
  REFUSED; the probe is fixed.
- **Fork cost**: forking `openssl x509` per certificate cost 3 min per run on the loaded
  machine, at 20 ms per fork and about 1500 forks. A coreutils version was still slow at 21 s
  for 118 certs. It was replaced by `lib/certset.py`, one process per bundle, and the result
  was cross-checked: identical fingerprint sets for 118 TLS and 169 total roots against the
  openssl version.
- **Queue waits**: four separate `nixb` calls per behavioral check meant four waits; one
  cell waited 553 s for a slot. The cells are now one `lib/matrix.nix` build.
- **Skipping the queue**: `cah_realise` skips nixb entirely when `nix path-info` shows that
  all outputs are already valid.

## Not done / sketched only

- Shims for PHP/composer apps and Ruby gems are described in the README only. The ncat
  example (`shims/example-cli.sh`) is untested.
- Not exercised:
  - `--sides after`;
  - an `--after-overlay` that *adds* a fix. Only the negative-control overlay was run.
- A global-overlay injection (`cacert = cacertTest` everywhere) was deliberately not done,
  because of the cost of the cascade.
- Only the two worked examples, the known-good sample and the negative control were run. The
  other ~60 campaign packages were not.

## Validation against independently merged PRs (via `--pr`, no checkout)

Run on 2026-10-21 with `nix run path:. -- <attr> --pr <N>` from `/`, both sides fetched from
GitHub by the PR's base and head commits.

### wordpress, PR #576572 (merged, by bartoostveen): static FIXED, behavioral PASS, 1:18 total

```
| out:/share/wordpress/wp-includes/certificates/ca-bundle.crt | pem 119 certs: 4 not in cacert, 1 in cacert but not for TLS, 4 cacert TLS roots missing; scanner: ECC G3 | symlink->cacert:ca-no-trust-rules-bundle.crt pem 118 certs == cacert |
VERDICT wordpress: FIXED: before trusted CAs outside cacert; after: 1 store(s) == cacert, none with extra CAs

         | stock cacert | + test root  | override with test-root cacert
before   | REFUSED      | REFUSED      | NO-OP (package does not take cacert)
after    | REFUSED      | CONNECTED    | yes (rebuilt with cacert + test root)
VERDICT wordpress: PASS: after-fix trust follows cacert; before-fix ignores it
```

The shim (`shims/wordpress.nix`) does what `class-wp-http.php` does: `Requests::set_certificate_path(ABSPATH.WPINC.'/certificates/ca-bundle.crt')`, then one GET with the shipped Requests library under `php`.

### osquery, PR #576516 (merged): `--pr` resolution checked with `--dry-run-only` (both sides evaluated; osquery is a long build, not run)

### nmap, PR #576568 (merged): static only by design

The fix removes a bundle that ncat merged with the system store; nothing in the package reads cacert at a build-time path, so there is no wiring for the behavioral test to prove. The former `shims/example-cli.sh` (ncat, untested) was removed for that reason.

## Campaign fix branches (via `--base`/`--after`, no checkout)

### zulu (fix branch): static FIXED, behavioral PASS, 2:13 total

Run on 2026-10-21 from `/` with the local flake (no GitHub API calls):
`nix run path:. -- zulu --base github:irgolic/nixpkgs/8915027df75d0403ef013dd0cbf09ff3c602fd03 --after github:irgolic/nixpkgs/f428226b7bb9e1c857b5a36c85e4adf7d35f8829`
(`f428226b7`, "zulu: generate cacerts from cacert"). `zulu` is `zulu21`, i.e. `zulu-ca-jdk-21.0.11`.

```
| out:/lib/security/cacerts | keystore 109 certs: 33 not in cacert, 17 in cacert but not for TLS, 59 cacert TLS roots missing [no-password]; scanner: AAA,ECC G3 | keystore 118 certs == cacert [no-password] |
VERDICT zulu: FIXED: before trusted CAs outside cacert; after: 1 store(s) == cacert, none with extra CAs

  package derivations to build for the matrix: 1 zulu-ca-jdk-21.0.11.drv
  matrix build: 73s (incl. waiting for a nixb slot)
         | stock cacert | + test root  | override with test-root cacert
before   | REFUSED      | REFUSED      | NO-OP (package does not take cacert)
after    | REFUSED      | CONNECTED    | yes (rebuilt with cacert + test root)
control (before cells): curl --cacert test-root: CONNECTED, curl --cacert stock: REFUSED
VERDICT zulu: PASS: after-fix trust follows cacert; before-fix ignores it
```

- Shim logs: both before cells and after-stock end in
  `SSLHandshakeException: (certificate_unknown) PKIX path building failed`. After-test runs on
  the zulu rebuilt with the test-root cacert and prints `OK status=200 cipher=TLS_AES_256_GCM_SHA384`.
- This is the first run of a shim with a custom `inject` (`shims/zulu.nix`). zulu's version
  files declare only `{ callPackage, enableJavaFX, ... }` and forward the rest to `common.nix`,
  so the default `functionArgs ? cacert` test finds nothing. The shim overrides `cacert` only
  when that side's `common.nix` takes it. The base's does not, so before-test is a NO-OP. An
  unconditional override there was an evaluation error, so the before cells failed to build.
- "cacert in runtime closure (after): no" is expected: `jre-generate-cacerts` builds the
  keystore from cacert at build time.

### python3Packages.httplib2 (fix branch, postPatch): static FIXED, behavioral PASS with both shims

The fix now makes the symlink in `postPatch`, in the source tree, before the wheel is built, as
merged NixOS/nixpkgs#490115 does for botocore:
`ln -sf ${cacert}/etc/ssl/certs/ca-bundle.crt httplib2/cacerts.txt`. The build copies the file,
so the installed `cacerts.txt` and the one in the `dist` wheel are both regular files with the
content of cacert's `ca-bundle.crt` (sha256 `81ffe987…`, checked with `cmp` and `unzip -p`). The
package's own tests pass (507 passed). Branch `cacert/python3Packages.httplib2` =
`e4b7d4ce526cf04c114f650fb2c8143cf2761b8b`.

Run on 2026-10-21 from `/` with the local flake (no GitHub API calls). Cleaned outputs:
`runs/httplib2.txt` and `runs/httplib2-wheel.txt` in the gist.

```sh
nix run path:. -- python3Packages.httplib2 --base github:irgolic/nixpkgs/8915027df75d0403ef013dd0cbf09ff3c602fd03 --after github:irgolic/nixpkgs/e4b7d4ce526cf04c114f650fb2c8143cf2761b8b
nix run path:. -- python3Packages.httplib2 --base github:irgolic/nixpkgs/8915027df75d0403ef013dd0cbf09ff3c602fd03 --after github:irgolic/nixpkgs/e4b7d4ce526cf04c114f650fb2c8143cf2761b8b --shim python-wheel
```

Static (the same for both runs; 1:24 for the first run, 0:50 for the second):

```
| out:/lib/python3.14/site-packages/httplib2/cacerts.txt | pem 71 certs: 55 not in cacert, 8 in cacert but not for TLS, 110 cacert TLS roots missing; scanner: AAA | byte-identical copy of a cacert bundle: pem 169 certs (118 TLS roots + 51 non-TLS, i.e. cacert's own trust-rules bundle) |
inside archives (scanner only; a symlink in the installed output cannot reach them, issue #576542 class):
  before dist:/httplib2-0.32.0-py3-none-any.whl!httplib2/cacerts.txt  roots=40 trusts AAA Certificate Services
  after  dist:/httplib2-0.32.0-py3-none-any.whl!httplib2/cacerts.txt  roots=166, byte-identical copy of cacert:ca-bundle.crt
cacert in runtime closure (after): no          <- expected: the file is a copy now, not a symlink
VERDICT python3Packages.httplib2: FIXED: before trusted CAs outside cacert; after: 1 store(s) == cacert, none with extra CAs (+ after-side archive copies are byte-identical to cacert)
```

Behavioral, `shims/python-lib.nix` (installed package) and `shims/python-wheel.nix` (`dist` wheel),
the same matrix:

```
         | stock cacert | + test root  | override with test-root cacert
before   | REFUSED      | REFUSED      | NO-OP (package does not take cacert)
after    | REFUSED      | CONNECTED    | yes (rebuilt with cacert + test root)
control (before cells): curl --cacert test-root: CONNECTED, curl --cacert stock: REFUSED
VERDICT python3Packages.httplib2: PASS: after-fix trust follows cacert; before-fix ignores it
```

- Wheel shim logs: every cell prints `httplib2 0.32.0 from /build/wheel/httplib2/__init__.py` and
  `CA_CERTS = /build/wheel/httplib2/cacerts.txt`, i.e. the import comes from the pip-installed
  wheel. The refusals are `CERTIFICATE_VERIFY_FAILED ... unable to get local issuer certificate`;
  after-test prints `status 200`.
- **Negative control for the wheel shim**: the same shim against the first, `postInstall` version
  of the fix (`github:irgolic/nixpkgs/9928cfa9993ea47bb4601a8677055134d12bd5b6`), whose wheel kept
  the vendored file, fails as it should:
  ```
  after    | REFUSED      | REFUSED      | yes (rebuilt with cacert + test root)
  VERDICT python3Packages.httplib2: FAIL: after-fix package does not trust the test root added to cacert (...)
  ```

Harness changes made for this run:
- **Archive members**: the scanner's sha256 of each archive member is now kept. A member that is
  byte-identical to a cacert bundle is printed as such, like a real file, and does not trigger
  "(+ bundles inside archives remain)". Without this, the after wheel showed
  `roots=166 trusts AAA Certificate Services,emSign Root CA - G1`: those are cacert's own
  `ca-bundle.crt` trust-rule blocks (the scanner quirk noted above).
- **`--shim NAME`** resolves `shims/NAME.nix`, `shims/NAME.sh` or `shims/NAME` of the harness, so it
  works under `nix run` without a checkout (a file path still works). An explicit `--shim` uses its
  own working directory, `out/<attr>/behave-<shim>/`.
- **`ca-check`** passed every option to `ca-static-check` too, which took `--shim X` for two
  attribute names. The behavioral-only options (`--shim`, `--sides`, `--rerun`) now go to
  `ca-behave-check` only, and `--shim` runs it even when `shims/<attr>` does not exist.

### python3Packages.raven (fix branch): static FIXED, behavioral PASS

Run on 2026-10-21 from `/` with the local flake:
`nix run path:. -- python3Packages.raven --base github:irgolic/nixpkgs/8915027df75d0403ef013dd0cbf09ff3c602fd03 --after github:irgolic/nixpkgs/ce68df1c722b0132567b24298ab000378c45fce3`
(`ce68df1c7`, "python3Packages.raven: use cacert bundle instead of vendored CA file": a `postInstall`
symlink of `raven/data/cacert.pem` to cacert's `ca-bundle.crt`). 1:19 in total. Cleaned output:
`runs/python3Packages.raven.txt` in the gist.

```
| out:/lib/python3.14/site-packages/raven/data/cacert.pem | pem 155 certs: 94 not in cacert, 19 in cacert but not for TLS, 76 cacert TLS roots missing; scanner: AAA | symlink->cacert:ca-bundle.crt pem 169 certs (118 TLS roots + 51 non-TLS, i.e. cacert's own trust-rules bundle) |
inside archives (scanner only; a symlink in the installed output cannot reach them, issue #576542 class):
  before dist:/raven-6.10.0-py2.py3-none-any.whl!raven/data/cacert.pem  roots=107 trusts AAA Certificate Services
  after  dist:/raven-6.10.0-py2.py3-none-any.whl!raven/data/cacert.pem  roots=107 trusts AAA Certificate Services
VERDICT python3Packages.raven: FIXED: before trusted CAs outside cacert; after: 1 store(s) == cacert, none with extra CAs (+ bundles inside archives remain, see above)

         | stock cacert | + test root  | override with test-root cacert
before   | REFUSED      | REFUSED      | NO-OP (package does not take cacert)
after    | REFUSED      | CONNECTED    | yes (rebuilt with cacert + test root)
control (before cells): curl --cacert test-root: CONNECTED, curl --cacert stock: REFUSED
VERDICT python3Packages.raven: PASS: after-fix trust follows cacert; before-fix ignores it
```

- Shim (`shims/python3Packages.raven.nix`): an interpreter with raven only, so `certifi` is not
  importable (checked) and `raven.conf.defaults.CA_BUNDLE` is `raven/data/cacert.pem`. One GET with
  `raven.transport.http.HTTPTransport(timeout=10).send(url, None, {})`, i.e. the default
  `sync+https` transport with its default `verify_ssl=True, ca_certs=defaults.CA_BUNDLE`.
- raven's verified path (`raven.utils.http.urlopen`) calls `ssl.wrap_socket(sock, ca_certs=...,
  cert_reqs=CERT_REQUIRED)`, which Python removed in 3.12, so on python3.14 it raises
  `AttributeError` before any TLS happens. The shim restores `ssl.wrap_socket` with the removed
  function's semantics (verify mode and CA file from the arguments, no hostname check) before
  importing raven. This is the package's state in nixpkgs, independent of the fix: raven is the
  unmaintained predecessor of sentry-sdk.
- Shim logs: before-test prints `CA_BUNDLE = .../raven/data/cacert.pem -> .../python3.14-raven-6.10.0/.../raven/data/cacert.pem`
  (the vendored file) and ends in `CERTIFICATE_VERIFY_FAILED ... unable to get local issuer
  certificate`; after-test prints `-> .../nss-cacert-3.131.1/etc/ssl/certs/ca-bundle.crt` and
  `status 200`.
- The fix is a `postInstall` symlink, so the wheel in the `dist` output still carries the vendored
  bundle (the static table above). The httplib2 fix moved to `postPatch` for that reason.

### graalvmPackages.graalvm-ce (fix branch): behavioral PASS; static NOT FIXED (two native-image binaries)

Run on 2026-10-21 from `/` with the local flake:
`nix run path:. -- graalvmPackages.graalvm-ce --base github:irgolic/nixpkgs/8915027df75d0403ef013dd0cbf09ff3c602fd03 --after github:irgolic/nixpkgs/3961f527a2230734f10ea70cc22cb8890e7f4cbc`
(`3961f527a`, "graalvm-ce: generate cacerts from cacert": `buildGraalvm.nix` regenerates
`lib/security/cacerts` with `jre-generate-cacerts` in `postFixup`). The top-level `graalvm-ce` is a
throw alias, so the attr is `graalvmPackages.graalvm-ce` (25.4.4.1.1, a binary repackaging; the
dry-run policy does not treat it as heavy). Both sides were already in the store; the matrix built
the test-root graalvm-ce once (matrix build 126 s, queue wait and the install check, which runs `native-image` twice, included).
Cleaned output: `runs/graalvmPackages.graalvm-ce.txt` in the gist.

```
| out:/lib/libnative-image-agent.so | pem: 0 certs readable; scanner: AAA,ECC G3 | pem: 0 certs readable; scanner: AAA,ECC G3 |
| out:/lib/security/cacerts | keystore 111 certs: 33 not in cacert, 17 in cacert but not for TLS, 57 cacert TLS roots missing [no-password]; scanner: AAA,ECC G3 | keystore 118 certs == cacert [no-password] |
| out:/lib/svm/bin/native-image | pem: 0 certs readable; scanner: AAA,ECC G3 | pem: 0 certs readable; scanner: AAA,ECC G3 |
VERDICT graalvmPackages.graalvm-ce: NOT FIXED: an after-side store is not equivalent to cacert (see table)

         | stock cacert | + test root  | override with test-root cacert
before   | REFUSED      | REFUSED      | NO-OP (package does not take cacert)
after    | REFUSED      | CONNECTED    | yes (rebuilt with cacert + test root)
control (before cells): curl --cacert test-root: CONNECTED, curl --cacert stock: REFUSED
VERDICT graalvmPackages.graalvm-ce: PASS: after-fix trust follows cacert; before-fix ignores it
```

- Shim (`shims/graalvmPackages.graalvm-ce.nix`): the `java-runtime` probe with its own `inject`.
  `graalvm-ce/default.nix` declares only `{ stdenv, fetchurl, graalvmPackages, useMusl }`, so the
  default injection would be a NO-OP on the after side too. The fix is in the scope's
  `buildGraalvm.nix`, which takes `...` and forwards unknown arguments into `mkDerivation`, so
  passing `cacert` to it blindly would change the before-side derivation without wiring anything.
  The shim instead overrides the package's `graalvmPackages` argument with
  `graalvmPackages.overrideScope (_: _: { cacert = c; })`, and only when that side's
  `buildGraalvm.nix` declares `cacert`.
- Shim logs: the three refusing cells end in `PKIX path building failed`; after-test prints
  `java.home=.../graalvm-ce-25.4.4.1.1 trustStore=(default)` and `OK status=200`.
- Static: the keystore itself goes from 111 certs (50 not trusted for TLS by cacert) to exactly
  cacert's 118. The verdict is NOT FIXED because of two ELF files, `lib/svm/bin/native-image` and
  `lib/libnative-image-agent.so`. Both are native-image builds that upstream ships; their image heap
  carries the upstream JDK's root set as DER (the scanner finds 99 known roots, the same count as
  the before keystore), and they are byte-identical before and after (same sha256). Regenerating
  `lib/security/cacerts` cannot reach roots compiled into a binary (#576544 class); only rebuilding
  those images from source would. Neither is the JVM that `bin/java` runs: the behavioral check shows
  that one follows cacert. Images that users build with the fixed `native-image` take the trust
  store from `$JAVA_HOME/lib/security/cacerts` at image build time (GraalVM documents this); that was not tested here (a
  `native-image` compile does not fit the shim's 120 s timeout).

### gam (fix branch): static FIXED, behavioral PASS

Run on 2026-10-21 from `/` with the local flake:
`nix run path:. -- gam --base github:irgolic/nixpkgs/8915027df75d0403ef013dd0cbf09ff3c602fd03 --after github:irgolic/nixpkgs/1b18fced0d9a5bed56faa2a574f0882060327c48`
(`1b18fced0`, "gam: use cacert bundle for the vendored fallback CA file": a `postInstall` symlink
of `gam/cacerts.pem` to cacert's `ca-bundle.crt`). 2:09 in total. Cleaned output: `runs/gam.txt`
in the gist.

```
| out:/lib/python3.14/site-packages/gam/cacerts.pem | pem 26 certs: 1 not in cacert, 5 in cacert but not for TLS, 98 cacert TLS roots missing | symlink->cacert:ca-bundle.crt pem 169 certs (118 TLS roots + 51 non-TLS, i.e. cacert's own trust-rules bundle) |
VERDICT gam: FIXED: before trusted CAs outside cacert; after: 1 store(s) == cacert, none with extra CAs (+ bundles inside archives remain, see above)

         | stock cacert | + test root  | override with test-root cacert
before   | REFUSED      | REFUSED      | yes (rebuilt with cacert + test root)
after    | REFUSED      | CONNECTED    | yes (rebuilt with cacert + test root)
control (before cells): curl --cacert test-root: CONNECTED, curl --cacert stock: REFUSED
VERDICT gam: PASS: after-fix trust follows cacert; before-fix ignores it
```

- gam already took `cacert` at base (its wrapper sets `GAM_CA_FILE`), so the before side is rebuilt
  with the test-root cacert too, not a NO-OP. It still refuses: the vendored fallback does not
  follow cacert. That is the stronger form of the before-side claim.
- `GAM_CA_FILE` is read only when gam *creates* `gam.cfg` (it becomes `cacerts_pem` there). An
  existing `gam.cfg` with an empty `cacerts_pem`, or a run without the wrapper, uses
  `$GAM_PATH/cacerts.pem`, the file the fix replaces.
- Shim (`shims/gam.nix`): runs the program the wrapper execs (`bin/.gam-wrapped`, with the
  program's own `sys.path` setup) under `env -i` (no `GAM_CA_FILE`) with a fresh `GAMCFGDIR`, so
  the new `gam.cfg` has `cacerts_pem =`. The request is
  `gam config user_service_account_access_only true user nobody@example.com create drivefile url $URL`:
  `getMediaBody` fetches the URL with gam's `getHttpObj()` (httplib2, `ca_certs=cacerts_pem`)
  before any Google credentials are needed. `user_service_account_access_only` skips the Directory
  API object that resolving `user <u>` builds first. The driver wraps `getMediaBody` to print the
  CA file and exit 0 after the fetch returns, because the next step contacts Google.
- Shim logs: before cells print `cacerts_pem = .../gam/cacerts.pem -> .../gam-7.43.04/.../gam/cacerts.pem`
  and gam's own `ERROR: URL: https://localhost:8443/, [SSL: CERTIFICATE_VERIFY_FAILED] ... unable to get local issuer certificate`;
  after-test prints `-> .../nss-cacert-3.131.1/etc/ssl/certs/ca-bundle.crt` and
  `fetched https://localhost:8443/ content-type text/html`.
- Found on the way, not part of the fix: the `bin/gam` wrapper exits 127 on both sides
  (`line 88: export GAMCFGDIR="${XDG_CONFIG_HOME:-$HOME/.config}/gam": No such file or directory`).
  The `--run` entries in `makeWrapperArgs` keep their literal single quotes, so each `export`
  line runs as a command name, and `bash -e` stops there.
- As for raven, the fix is a `postInstall` symlink, so the `dist` wheel keeps the vendored file.

### scilab-bin (fix branch): behavioral PASS; static NOT FIXED (JCEF's libcef.so)

Run on 2026-10-21 from `/` with the local flake:
`nix run path:. -- scilab-bin --base github:irgolic/nixpkgs/8915027df75d0403ef013dd0cbf09ff3c602fd03 --after github:irgolic/nixpkgs/89afd381a888d7497fdedc57bbd0815d9b837514`
(`89afd381a`, "scilab-bin: generate cacerts from cacert": `postFixup` regenerates
`thirdparty/java/lib/security/cacerts` with `jre-generate-cacerts`, after an explicit
`autoPatchelf` so that the bundled `keytool` runs). scilab-bin 2027.0.0 is a binary repackaging:
the dry-run showed one drv per side (the package itself), built in 82 s (before) and 137 s (after);
the matrix build (the test-root scilab-bin) took 129 s, queue wait included. Cleaned output:
`runs/scilab-bin.txt` in the gist.

```
| out:/lib/thirdparty/jcef/libcef.so | pem: 0 certs readable; scanner: AAA,ECC G3 | pem: 0 certs readable; scanner: AAA,ECC G3 |
| out:/thirdparty/java/lib/security/cacerts | keystore 144 certs: 19 not in cacert, 12 in cacert but not for TLS, 5 cacert TLS roots missing [no-password]; scanner: ECC G3 | keystore 118 certs == cacert [no-password] |
VERDICT scilab-bin: NOT FIXED: an after-side store is not equivalent to cacert (see table) (+ bundles inside archives remain, see above)

         | stock cacert | + test root  | override with test-root cacert
before   | REFUSED      | REFUSED      | NO-OP (package does not take cacert)
after    | REFUSED      | CONNECTED    | yes (rebuilt with cacert + test root)
control (before cells): curl --cacert test-root: CONNECTED, curl --cacert stock: REFUSED
VERDICT scilab-bin: PASS: after-fix trust follows cacert; before-fix ignores it
```

- Shim (`shims/scilab-bin.nix`): the TLS probe on the bundled JRE,
  `"$PKG/thirdparty/java/bin/java" -cp <probe> TlsProbe "$URL"`. It runs as is: autoPatchelf has set
  the JRE's RUNPATHs, and the probe needs only `java.base`, so nothing from the launcher scripts'
  environment is needed. The package declares `cacert`, so the default injection applies.
- Shim logs: every cell prints `java.home=.../scilab-bin-2027.0.0/thirdparty/java trustStore=(default)`;
  the three refusing cells end in `PKIX path building failed`, after-test prints `OK status=200`.
- Static: the bundled JRE's keystore goes from 144 certs (31 not trusted for TLS by cacert) to
  exactly cacert's 118. The verdict is NOT FIXED because of `lib/thirdparty/jcef/libcef.so`, the
  Chromium Embedded Framework: the scanner finds 130 known roots compiled into it (Chromium's own
  root store), and the file is byte-identical before and after (same sha256). Roots compiled into a
  binary cannot be replaced by packaging (#576544 class). The "inside archives" lines are code-signing
  material, not trust stores: jar signature blocks (`META-INF/*.RSA`, `*.DSA`) and the Authenticode /
  macOS signatures of flatlaf's Windows and macOS natives, unchanged before and after.

### julia-bin and julia_110-bin (fix branch, install check skipped): static FIXED, behavioral PASS

Run on 2026-10-21 from `/` with the local flake:
`nix run path:. -- julia-bin --base github:irgolic/nixpkgs/8915027df75d0403ef013dd0cbf09ff3c602fd03 --after github:irgolic/nixpkgs/05f45e387af5a700548a6dcfc1de4d6e8260eea5 --after-overlay fixes/julia-bin-skip-installcheck.nix`,
and the same for `julia_110-bin` (`05f45e387`, "julia-bin: use cacert bundle instead of vendored CA
bundle": `installPhase` symlinks `share/julia/cert.pem` to cacert's `ca-no-trust-rules-bundle.crt`
in `generic-bin.nix`, which every `julia_1xx-bin` uses). `julia-bin` is `julia_113-bin` (1.13.2);
`julia_110-bin` (1.10.12, the LTS) was added because its libcurl uses mbedTLS instead of OpenSSL.
Cleaned outputs: `runs/julia-bin.txt` and `runs/julia_110-bin.txt` in the gist.

**The after side is the fix branch with `doInstallCheck = false`** (`fixes/julia-bin-skip-installcheck.nix`,
which changes nothing else). The real derivation's install check runs Julia's whole test suite with
one worker per CPU (nixb's `--cores 4` does not bound it), and the harness would run it twice (the
static after side and the test-root after cell). The dry-run policy did not stop it: the after side
is one drv, and `CAH_HEAVY_RE` matches `-julia-<digit>` but not `julia-bin-1.13.2`. Nobody has run
that test suite on the fix branch (the fix's author skipped the check as well), so these runs say
nothing about whether it passes. The wiring under test is in `installPhase`; the install check does
not touch `cert.pem`. Both before sides came from the binary cache; each after side built in about 30 s.

```
julia-bin:
| out:/share/julia/cert.pem | pem 121 certs: 3 not in cacert, 0 in cacert but not for TLS, 0 cacert TLS roots missing; scanner: ECC G3 | symlink->cacert:ca-no-trust-rules-bundle.crt pem 118 certs == cacert |
VERDICT julia-bin: FIXED: before trusted CAs outside cacert; after: 1 store(s) == cacert, none with extra CAs
julia_110-bin:
| out:/share/julia/cert.pem | pem 144 certs: 19 not in cacert, 12 in cacert but not for TLS, 5 cacert TLS roots missing; scanner: ECC G3 | symlink->cacert:ca-no-trust-rules-bundle.crt pem 118 certs == cacert |
VERDICT julia_110-bin: FIXED: before trusted CAs outside cacert; after: 1 store(s) == cacert, none with extra CAs

both:
         | stock cacert | + test root  | override with test-root cacert
before   | REFUSED      | REFUSED      | NO-OP (package does not take cacert)
after    | REFUSED      | CONNECTED    | yes (rebuilt with cacert + test root)
control (before cells): curl --cacert test-root: CONNECTED, curl --cacert stock: REFUSED
VERDICT julia-bin: PASS: after-fix trust follows cacert; before-fix ignores it
VERDICT julia_110-bin: PASS: after-fix trust follows cacert; before-fix ignores it
```

- Shim (`shims/julia-bin.nix`, symlinked as `julia_110-bin.nix`): `julia --startup-file=no -e` with
  `using Downloads; Downloads.request(url; output = devnull)`. It prints
  `NetworkOptions.ca_roots_path()` first. That function returns `$JULIA_SSL_CA_ROOTS_PATH`,
  `$SSL_CERT_FILE` or `$SSL_CERT_DIR` if set, else the first existing Linux system bundle
  (`/etc/ssl/cert.pem`, `/etc/ssl/certs/ca-certificates.crt`, ...), else
  `Sys.BINDIR/../share/julia/cert.pem` (checked in the shipped `NetworkOptions/src/ca_roots.jl`).
  The cell has none of the first two, so the bundled file is used; Downloads passes it to libcurl as
  `CURLOPT_CAINFO`. On NixOS, `/etc/ssl/certs/ca-certificates.crt` exists and wins, so the fix matters
  where no system bundle exists (build sandboxes, minimal containers, non-NixOS hosts without one).
- Shim logs: before cells print `ca_roots_path() = .../julia-bin-1.13.2/share/julia/cert.pem -> `
  the same file (vendored); after cells print `-> .../nss-cacert-3.131.1/etc/ssl/certs/ca-no-trust-rules-bundle.crt`
  (the stock or the test-root cacert). Refusals: 1.13 `RequestError: SSL certificate OpenSSL verify result:
  unable to get local issuer certificate (20)`, 1.10 `RequestError: Cert verify failed: BADCERT_NOT_TRUSTED`.
  after-test prints `status 200`.
- **Harness change**: the first julia_110-bin run classified the three mbedTLS refusals as ERROR
  (`INCOMPLETE: CONNECTED ERROR ERROR ERROR`), because no pattern matched `BADCERT_NOT_TRUSTED`.
  `lib/behave.nix` now also counts `SSL certificate problem` (libcurl's prefix for verification
  failures with OpenSSL-style backends) and `BADCERT_NOT_TRUSTED` (libcurl with mbedTLS) as
  refusals. This changes every cell's derivation, so cached cells run once more.

### rubyPackages.{excon,httpclient,nap,algoliasearch} (fix branch): static FIXED, behavioral PASS for all four

All four fixes are one commit, `6f7ca0cd2` ("rubyPackages.{algoliasearch,excon,httpclient,nap}: use
cacert bundle instead of vendored CA files"): `postInstall` hooks in `ruby-modules/gem-config` that
symlink each gem's bundle to cacert's `ca-bundle.crt`. Run on 2026-10-21 from `/` with the local flake,
one run per attribute:
`nix run path:. -- rubyPackages.<gem> --base github:irgolic/nixpkgs/8915027df75d0403ef013dd0cbf09ff3c602fd03 --after github:irgolic/nixpkgs/6f7ca0cd245e2a442b12af32e80709134fb81e21`.
40 s to 1:20 each. Cleaned outputs: `runs/rubyPackages.<gem>.txt` in the gist.

| gem | vendored file (before) | after | behavioral |
|---|---|---|---|
| excon 1.3.1 | `data/cacert.pem`: 148 certs, 23 not in cacert, 12 not for TLS | symlink->cacert:ca-bundle.crt | PASS |
| httpclient 2.9.0 | `lib/httpclient/cacert.pem`: 153 certs, 98 not in cacert, 19 not for TLS; `cacert1024.pem`: 153 certs, 116 not in cacert | both symlink->cacert:ca-bundle.crt | PASS |
| nap 1.1.0 | `support/cacert.pem`: 155 certs, 100 not in cacert, 19 not for TLS | symlink->cacert:ca-bundle.crt | PASS |
| algoliasearch 1.27.5 | `resources/ca-bundle.crt`: 158 certs, 128 not in cacert, 14 not for TLS | symlink->cacert:ca-bundle.crt | PASS |

The matrix is the same for all four:

```
         | stock cacert | + test root  | override with test-root cacert
before   | REFUSED      | REFUSED      | NO-OP (package does not take cacert)
after    | REFUSED      | CONNECTED    | yes (rebuilt with cacert + test root)
control (before cells): curl --cacert test-root: CONNECTED, curl --cacert stock: REFUSED
VERDICT rubyPackages.<gem>: PASS: after-fix trust follows cacert; before-fix ignores it
```

- Shims: `shims/ruby-gem.nix` (shared) and one `shims/rubyPackages.<gem>.nix` per gem with its
  request. `ruby -e` runs with the gem and the gems it propagates on `GEM_PATH`. `SSL_CERT_FILE` and
  `SSL_CERT_DIR` are unset (checked), and OpenSSL's default file
  (`/etc/ssl/certs/ca-certificates.crt`) does not exist in the sandbox (printed), so only the gem's
  bundle can make the connection verify.
  - excon: `Excon.get(url)` with no `ssl_ca_file`. `SSLSocket` adds `Excon::DEFAULT_CA_FILE`
    (`data/cacert.pem`) to a store with OpenSSL's default paths.
  - httpclient: `HTTPClient.new.get(url)`. `SSLConfig` lazily loads `lib/httpclient/cacert.pem`.
  - nap: `REST.get(url, {}, { tls_verify: true })`. nap verifies only with `tls_verify` (or
    `verify_ssl`); without it, it uses `VERIFY_NONE` and no bundle at all. That was read from
    `rest/request.rb`, not run. The fix matters only for callers that ask for verification.
  - algoliasearch: `Algolia::Client.new(application_id:, api_key:, hosts: ["localhost:8443"])`
    needs no real credentials. The shim takes the HTTPClient session the client builds for that
    host (`thread_local_hosts`, which calls `ssl_config.add_trust_ca(resources/ca-bundle.crt)`) and
    does one GET with it. The client's own request methods would then `JSON.parse` the test
    server's HTML page. `add_trust_ca` also stops httpclient from loading its own `cacert.pem`, so
    in the after-test cell, where the whole gem set is rebuilt, the CONNECTED comes from
    algoliasearch's file and not from the httpclient fix.
- Injection: the fixes take `cacert` in gem-config (`defaultGemConfig`), not in the gem's own
  function, so the default `.override { cacert }` is a NO-OP for every gem. `ruby-gem.nix` has an
  `inject` that rebuilds the gem set the way ruby's `passthru.gems` does
  (`ruby-modules/with-packages`) with `gemConfig = defaultGemConfig.override { cacert = <test cacert>; }`,
  and takes the same gem. At base gem-config does not take `cacert`, so it is a NO-OP there.
- Shim logs: the before cells print e.g. `DEFAULT_CA_FILE = .../excon-1.3.1/data/cacert.pem -> .../ruby3.4-excon-1.3.1/.../data/cacert.pem`
  and end in `SSL_connect returned=1 ... certificate verify failed (unable to get local issuer certificate)`.
  The after-test cells print `-> .../nss-cacert-3.131.1/etc/ssl/certs/ca-bundle.crt` and `status 200`.
- Found on the way, not part of the fix: `require "algoliasearch"` fails on nixpkgs' Ruby 3.4 with
  `cannot load such file -- base64 (LoadError)`. `algolia/client.rb` requires `base64`, a bundled
  (no longer default) gem since Ruby 3.4, and the gem does not declare it. The first run was
  therefore ERROR in all four cells. The shim adds `rubyPackages.base64` to the gem path
  (`extraGems = [ "base64" ]`).
- These runs used the harness as of `58c0701` plus these shims. The other agent's later
  `lib/behave.nix` change (`79032d1`, more refusal wordings) only widens the REFUSED pattern; every
  REFUSED cell here already matched the older pattern.

### invoiceplane (fix branch): static FIXED, behavioral PASS

Run on 2026-10-21 from `/` with the local flake:
`nix run path:. -- invoiceplane --base github:irgolic/nixpkgs/8915027df75d0403ef013dd0cbf09ff3c602fd03 --after github:irgolic/nixpkgs/278c921729a83d74a63ea3740cf8392903d9f255`
(`278c92172`, "invoiceplane: use cacert bundle instead of vendored CA bundles": symlinks of
`application/config/cacert.pem` and `vendor/stripe/stripe-php/data/ca-certificates.crt` to cacert's
`ca-no-trust-rules-bundle.crt`). 1:33 in total. Cleaned output: `runs/invoiceplane.txt` in the gist.

```
| out:/application/config/cacert.pem | pem 136 certs: 111 not in cacert, 14 in cacert but not for TLS, 107 cacert TLS roots missing; scanner: AAA | symlink->cacert:ca-no-trust-rules-bundle.crt pem 118 certs == cacert |
| out:/vendor/stripe/stripe-php/data/ca-certificates.crt | pem 135 certs: 31 not in cacert, 18 in cacert but not for TLS, 32 cacert TLS roots missing; scanner: AAA,ECC G3 | symlink->cacert:ca-no-trust-rules-bundle.crt pem 118 certs == cacert |
VERDICT invoiceplane: FIXED: before trusted CAs outside cacert; after: 2 store(s) == cacert, none with extra CAs

         | stock cacert | + test root  | override with test-root cacert
before   | REFUSED      | REFUSED      | NO-OP (package does not take cacert)
after    | REFUSED      | CONNECTED    | yes (rebuilt with cacert + test root)
control (before cells): curl --cacert test-root: CONNECTED, curl --cacert stock: REFUSED
VERDICT invoiceplane: PASS: after-fix trust follows cacert; before-fix ignores it
```

- Shim (`shims/invoiceplane.nix`, modeled on `wordpress.nix`): `php -r` with the package's
  `vendor/autoload.php`, and one GET through `\Stripe\HttpClient\CurlClient::instance()->request(...)`.
  InvoicePlane's Stripe gateway uses `StripeClient`, whose requests go through `ApiRequestor` to that
  client. The client sets `CURLOPT_CAINFO` to `Stripe::getCABundlePath()`, i.e. stripe-php's
  `data/ca-certificates.crt`, since InvoicePlane never sets one. Going through `ApiRequestor` would
  then `json_decode` the test server's HTML page.
- Shim logs: before-test prints `stripe-php 14.10.0 CA bundle .../invoiceplane-1.7.2.1/vendor/stripe/stripe-php/data/ca-certificates.crt`
  and ends in stripe-php's `ApiConnectionException: Could not verify Stripe's SSL certificate ...
  (Network error [errno 60]: SSL certificate OpenSSL verify result: unable to get local issuer certificate (20))`.
  after-test prints `CA bundle .../nss-cacert-3.131.1/etc/ssl/certs/ca-no-trust-rules-bundle.crt` and `status 200`.
- Only stripe-php's file is exercised. `application/config/cacert.pem` is not read by any PHP code in
  the package (no reference outside the file itself), so the static table is the only evidence for it.

### moodle (fix branch): static FIXED; no behavioral shim (the vendored files are not read on Linux)

Static only, run on 2026-10-21 from `/` with the local flake:
`nix run path:.#static -- moodle --base github:irgolic/nixpkgs/8915027df75d0403ef013dd0cbf09ff3c602fd03 --after github:irgolic/nixpkgs/d9f9e6713ca473d95c644349c4f9fc17d36e4bb6`
(`d9f9e6713`, "moodle: use cacert bundle instead of vendored CA bundles"). Cleaned output:
`runs/moodle.txt` in the gist.

```
| out:/share/moodle/public/lib/cacert.pem | pem 150 certs: 115 not in cacert, 15 in cacert but not for TLS, 98 cacert TLS roots missing; scanner: AAA | symlink->cacert:ca-no-trust-rules-bundle.crt pem 118 certs == cacert |
| out:/share/moodle/public/lib/google/src/Google/IO/cacerts.pem | pem 70 certs: 57 not in cacert, 8 in cacert but not for TLS, 113 cacert TLS roots missing; scanner: AAA | symlink->cacert:ca-no-trust-rules-bundle.crt pem 118 certs == cacert |
VERDICT moodle: FIXED: before trusted CAs outside cacert; after: 2 store(s) == cacert, none with extra CAs
```

No shim, for the same reason as nmap: on Linux nothing in Moodle reads either file, so a behavioral
test of Moodle's own code path would show the same result before and after.
- `lib/filelib.php`, `curl::get_cacert()`: `$CFG->dataroot/moodleorgca.crt` if readable, else
  php.ini `curl.cainfo`, else `$CFG->libdir/cacert.pem` **only when `$CFG->ostype === 'WINDOWS'`**,
  else `null`, i.e. libcurl's default store. `resetopt()` sets `CURLOPT_CAINFO` only when that is
  non-null.
- `lib/google/src/Google/IO/cacerts.pem` is the default `CURLOPT_CAINFO` of the bundled Google API
  client's `Google_IO_Curl` (and the `cafile` of `Google_IO_Stream`). Moodle's `get_google_client()`
  (`lib/google/lib.php`) replaces that IO class with `moodle_google_curlio`, which sends requests
  with Moodle's own `curl` class, so `get_cacert()` above decides.
- A shim could call `Google_IO_Curl` directly, but that is the vendored library's code, not a path
  Moodle takes, so it was not written. The fix is still worth having, for Windows-only code and for
  anything that loads the Google client without Moodle's wrapper. The static check is the evidence.

### h2o (fix branch): static FIXED, behavioral PASS

Run on 2026-10-21 from `/` with the local flake:
`nix run path:. -- h2o --base github:irgolic/nixpkgs/8915027df75d0403ef013dd0cbf09ff3c602fd03 --after github:irgolic/nixpkgs/9695aa7d969197154a8f2e1745bd4bd0303af275`
(`9695aa7d9`, "h2o: use cacert bundle instead of vendored CA bundle": a `postInstall` symlink of
`share/h2o/ca-bundle.crt` to cacert's `ca-bundle.crt`). Both sides were built from source, one drv
each (296 s before, 221 s after); the matrix's first build of the test-root h2o took 212 s, queue
wait included. Cleaned output: `runs/h2o.txt` in the gist.

```
| out:/share/h2o/ca-bundle.crt | pem 129 certs: 46 not in cacert, 18 in cacert but not for TLS, 53 cacert TLS roots missing; scanner: AAA,ECC G3 | symlink->cacert:ca-bundle.crt pem 169 certs (118 TLS roots + 51 non-TLS, i.e. cacert's own trust-rules bundle) |
VERDICT h2o: FIXED: before trusted CAs outside cacert; after: 1 store(s) == cacert, none with extra CAs

         | stock cacert | + test root  | override with test-root cacert
before   | REFUSED      | REFUSED      | NO-OP (package does not take cacert)
after    | REFUSED      | CONNECTED    | yes (rebuilt with cacert + test root)
control (before cells): curl --cacert test-root: CONNECTED, curl --cacert stock: REFUSED
VERDICT h2o: PASS: after-fix trust follows cacert; before-fix ignores it
```

- What reads the file (checked in the source at the package's rev `cee2cca6`): `src/httpclient.c`
  (`bin/h2o-httpclient`, installed by `INSTALL(TARGETS h2o-httpclient ...)`) loads
  `$H2O_ROOT/share/h2o/ca-bundle.crt`. `H2O_ROOT` is an environment override (unset in the cell)
  or the compiled-in `-DH2O_ROOT=${CMAKE_INSTALL_PREFIX}`; the built binary contains the `out`
  path. Verification is on unless `-k` is given (`SSL_VERIFY_PEER | SSL_VERIFY_FAIL_IF_NO_PEER_CERT`,
  plus a hostname check after the handshake). A failed chain ends the request with
  `h2o-httpclient: <X509_verify_cert_error_string>`, before any response.
- Shim (`shims/h2o.nix`): `timeout 10 h2o-httpclient --io-timeout 2000 -o /dev/null "$URL"`. Success
  is the `HTTP/1 200` status line, not the exit code. The harness's `openssl s_server -www` answers
  HTTP/1.0 without Content-Length and ends with a TLS close_notify, and h2o-httpclient does not take
  that as the end of the body. After a verified 200 it exits 1 with `I/O timeout`; in about 1 run in 6
  it hangs past its own `--io-timeout` instead (reproduced outside the sandbox with the same server:
  the status line arrives, the server has sent close_notify, and the client never returns).
  `-m HEAD`, `-H 'connection: close'` and `-2 0` do not change this. The first two runs of the
  matrix show both cases: after-test was ERROR once with `HTTP/1 200 ok` followed by `I/O timeout`,
  and once on the 120 s cell timeout; the second version also lacked `grep` on the shim's PATH.
- Shim logs: the three refusing cells print `ca-bundle.crt -> .../h2o-2.3.0-rolling-2026-10-21/share/h2o/ca-bundle.crt`
  (before, vendored) or `-> .../nss-cacert-3.131.1/etc/ssl/certs/ca-bundle.crt` (after-stock), then
  `h2o-httpclient: unable to get local issuer certificate`. after-test prints the test-root cacert's
  path, `HTTP/1 200 ok`, `h2o-httpclient: I/O timeout` and `status 200 received after the verified handshake`.

### python3Packages.raven, `dist` wheel (fix branch, postPatch): behavioral PASS; the postInstall version FAILS

The fix branch `cacert/python3Packages.raven` is now `bdcce494d`. It makes the symlink in `postPatch`,
in the source tree, as the httplib2 fix does: `ln -sf ${cacert}/etc/ssl/certs/ca-bundle.crt raven/data/cacert.pem`.
The wheel in the `dist` output is built from that tree, so it gets cacert's bundle too. The new shim
`shims/python-wheel-raven.nix` runs raven's request against that wheel.

Run on 2026-10-22 from `/` with the local flake, against commits of the local nixpkgs checkout
(`CAH_REPO=/home/rafael/nixpkgs`, exported with `fetchGit`):

```sh
nix run path:. -- python3Packages.raven --base 8915027df75d0403ef013dd0cbf09ff3c602fd03 --after bdcce494d6d60d0c8f0cbec7554583d52cc73588 --shim python-wheel-raven
nix run path:. -- python3Packages.raven --base 8915027df75d0403ef013dd0cbf09ff3c602fd03 --after ce68df1c722b0132567b24298ab000378c45fce3 --shim python-wheel-raven   # negative control
```

2:08 and 1:10 in total. Nothing was built except the cells: both sides and the test-root raven were
already in the store. Cleaned output: `runs/python3Packages.raven-wheel.txt` in the gist.

Fix branch (`bdcce494d`):

```
| out:/lib/python3.14/site-packages/raven/data/cacert.pem | pem 155 certs: 94 not in cacert, 19 in cacert but not for TLS, 76 cacert TLS roots missing; scanner: AAA | byte-identical copy of a cacert bundle: pem 169 certs (118 TLS roots + 51 non-TLS, i.e. cacert's own trust-rules bundle) |
inside archives (scanner only; a symlink in the installed output cannot reach them, issue #576542 class):
  before dist:/raven-6.10.0-py2.py3-none-any.whl!raven/data/cacert.pem  roots=107 trusts AAA Certificate Services
  after  dist:/raven-6.10.0-py2.py3-none-any.whl!raven/data/cacert.pem  roots=166, byte-identical copy of cacert:ca-bundle.crt
VERDICT python3Packages.raven: FIXED: before trusted CAs outside cacert; after: 1 store(s) == cacert, none with extra CAs (+ after-side archive copies are byte-identical to cacert)

         | stock cacert | + test root  | override with test-root cacert
before   | REFUSED      | REFUSED      | NO-OP (package does not take cacert)
after    | REFUSED      | CONNECTED    | yes (rebuilt with cacert + test root)
control (before cells): curl --cacert test-root: CONNECTED, curl --cacert stock: REFUSED
VERDICT python3Packages.raven: PASS: after-fix trust follows cacert; before-fix ignores it
```

Negative control, the first (`postInstall`) version of the fix (`ce68df1c7`), same shim:

```
  after  dist:/raven-6.10.0-py2.py3-none-any.whl!raven/data/cacert.pem  roots=107 trusts AAA Certificate Services
VERDICT python3Packages.raven: FIXED: ... (+ bundles inside archives remain, see above)

         | stock cacert | + test root  | override with test-root cacert
before   | REFUSED      | REFUSED      | NO-OP (package does not take cacert)
after    | REFUSED      | REFUSED      | yes (rebuilt with cacert + test root)
control (before cells): curl --cacert test-root: CONNECTED, curl --cacert stock: REFUSED
VERDICT python3Packages.raven: FAIL: after-fix package does not trust the test root added to cacert (...)
```

- Shim (`shims/python-wheel-raven.nix`): `shims/python-wheel.nix` with the request of
  `shims/python3Packages.raven.nix`. pip installs `${pkg.dist}/*.whl` offline into the sandbox.
  The interpreter has pip only (raven declares no required Python dependencies), so `certifi` is
  not importable (checked). `ssl.wrap_socket` is restored before raven is imported. Then one
  `HTTPTransport(timeout=10).send(url, None, {})`.
- Shim logs: every cell prints `raven 6.10.0 from /build/wheel/raven/__init__.py` and
  `CA_BUNDLE = /build/wheel/raven/data/cacert.pem`, a regular file (the wheel holds the content, not a
  symlink). The refusing cells end in `urlopen error [SSL: CERTIFICATE_VERIFY_FAILED] certificate verify
  failed: unable to get local issuer certificate`. after-test on the fix branch prints `status 200`.
- The negative control is the commit whose installed package passed in "python3Packages.raven (fix
  branch)" above. Its wheel was rebuilt with the test-root cacert but still carries the vendored file,
  so the wheel shim refuses. The installed-package shim cannot tell the two versions apart; the wheel
  shim can.
- The before cells are the same store paths in both runs.

### `shims/python-wheel.nix` generalized: httplib2 wheel re-run, PASS (no regression)

`shims/python-wheel.nix` now takes optional `module`, `prelude` and `snippet` arguments, with the
httplib2 request as the default. A wheel shim for another library is a two-line file,
`args: import ./python-wheel.nix (args // { module = "..."; snippet = "..."; })`, not a copy.
`--shim python-wheel` alone behaves as before. Its generated script differs slightly: `CA_CERTS` is
printed after the wheel-origin check, the version is read with `getattr`, and there is a blank line.
So its cells re-ran.

Re-run against the httplib2 fix branch, 1:50 in total, cleaned output
`runs/httplib2-wheel-generalized.txt` in the gist:

```sh
nix run path:. -- python3Packages.httplib2 --base 8915027df75d0403ef013dd0cbf09ff3c602fd03 --after github:irgolic/nixpkgs/e4b7d4ce526cf04c114f650fb2c8143cf2761b8b --shim python-wheel
```

```
VERDICT python3Packages.httplib2: FIXED: before trusted CAs outside cacert; after: 1 store(s) == cacert, none with extra CAs (+ after-side archive copies are byte-identical to cacert)
         | stock cacert | + test root  | override with test-root cacert
before   | REFUSED      | REFUSED      | NO-OP (package does not take cacert)
after    | REFUSED      | CONNECTED    | yes (rebuilt with cacert + test root)
control (before cells): curl --cacert test-root: CONNECTED, curl --cacert stock: REFUSED
VERDICT python3Packages.httplib2: PASS: after-fix trust follows cacert; before-fix ignores it
```

The matrix and verdict are the same as in "python3Packages.httplib2 (fix branch, postPatch)". after-test
prints `httplib2 0.32.0 from /build/wheel/httplib2/__init__.py`, `CA_CERTS = /build/wheel/httplib2/cacerts.txt`
and `status 200`. The other three cells end in `CERTIFICATE_VERIFY_FAILED ... unable to get local issuer certificate`.

### blink-qt (fix branch, postPatch): after side FIXED; before unbuildable, so the verdict is INCOMPLETE

`--after 6676921ad0d35eadb0d7bbc4110d6e07a1a6f94b` (`cacert/blink-qt`, "blink-qt: use cacert bundle
instead of vendored CA bundle": a `postPatch` symlink of `resources/tls/ca.crt` to cacert's
`ca-no-trust-rules-bundle.crt`). Run on 2026-10-22 from `/` against the local checkout, cleaned
output `runs/blink-qt.txt` in the gist:

```sh
CAH_REPO=/home/rafael/nixpkgs nix run path:. -- blink-qt --base 8915027df75d0403ef013dd0cbf09ff3c602fd03 --after 6676921ad0d35eadb0d7bbc4110d6e07a1a6f94b --after-overlay fixes/unbreak-msrplib.nix --force-build
```

blink-qt does not build on the base, independently of the fix. Three of its Python dependencies fail:
- `python3Packages.msrplib` and `python3Packages.xcaplib` fail in `pythonMetadataCheckPhase` with
  `No package metadata was found for msrplib` (`xcaplib`). Upstream's project names are
  `python3-msrplib` and `python3-xcaplib` (the wheels are `python3_msrplib-0.21.2` and
  `python3_xcaplib-2.0.2`), but the pnames are `msrplib` and `xcaplib`.
- `python3Packages.python3-sipsimple` fails to compile its Cython 3.3.0 output: `_core.c` calls
  `__pyx_tp_new_vectorcall_..._BaseHeader` (and `BaseContactHeader`, `BaseContentTypeHeader`,
  `IdentityHeader`, ...) without a declaration, which GCC rejects (`-Wimplicit-function-declaration`,
  `-Wint-conversion`). It builds with `cython_3_2` (3.2.5), as preshed and levenshtein already do.

`fixes/unbreak-msrplib.nix` works around all three, for the after side only (that is how
`--after-overlay` works): pname `python3-msrplib` and `python3-xcaplib` through `overrideAttrs`, and
`python3-sipsimple.override { cython = cython_3_2; }`. It uses `pythonPackagesExtensions`, because
blink-qt takes the top-level `python3Packages`, which is `python314Packages` (`python314.pkgs`), so a
`python3 = prev.python3.override { packageOverrides = ...; }` overlay would not reach it. The dry run
showed 4 drvs: the three dependencies (787 s through `nixb`, nearly all of it sipsimple and its bundled pjsip) and
blink-qt (73 s).

```
before BUILD FAILED (log: ~/.cache/nix-cacert-harness/blink-qt/static/before/build.log)
after  ok (1 built, 73s)
| out:/share/blink/tls/ca.crt | n/a | byte-identical copy of a cacert bundle: pem 118 certs == cacert |
  after  dist:/blink-6.0.6-cp314-cp314-linux_x86_64.whl!blink-6.0.6.data/data/share/blink/tls/ca.crt  roots=115, byte-identical copy of cacert:ca-no-trust-rules-bundle.crt
cacert in runtime closure (after): yes
VERDICT blink-qt: INCOMPLETE (a side was not built) (+ after-side archive copies are byte-identical to cacert)
```

The installed file is a copy, not a symlink: setuptools' `data_files` copies the symlink's target,
and so does the wheel. `roots=115` is the scanner's count of roots it knows; the member is
byte-identical to cacert's 118-root file.

Independent check with `bin/nixb`: `lib/nixpkgs.nix` plus the overlay on both commits, so that there
is a "before" to compare with (a blink-qt-only rebuild, 39 s).

| file | sha256 | PEM blocks | CN=AG Projects Development |
|---|---|---|---|
| cacert `ca-no-trust-rules-bundle.crt` | `8fd949630c20b946465122a53e33982d24f673ddf8b93776a39c7ba00b6a4d6a` | 118 | 0 |
| upstream source `resources/tls/ca.crt` | `0553831db87f4ef6dfa2362e09d9fe4f1ae4eb6d6949596fa5322a2da61dd251` | 135 | 1 |
| before: `out` `share/blink/tls/ca.crt` | `0553831d…` (= upstream) | 135 | 1 |
| before: `dist` wheel `*/share/blink/tls/ca.crt` | `0553831d…` (= upstream) | 135 | 1 |
| after: `out` `share/blink/tls/ca.crt` | `8fd94963…` (= cacert) | 118 | 0 |
| after: `dist` wheel `*/share/blink/tls/ca.crt` | `8fd94963…` (= cacert) | 118 | 0 |

By SHA-256 fingerprint, the before bundle has 135 certificates: 53 not in cacert, 18 in cacert but not
for TLS (e.g. AAA Certificate Services, DigiCert Global Root CA, GlobalSign Root CA), 64 of cacert's TLS
roots; 54 of cacert's 118 TLS roots are missing. One of the 53 is AG Projects' private development CA
(`C=NL, ST=Noord-Holland, L=Haarlem, O=AG Projects, OU=Development, CN=AG Projects Development`), first in
the file. Others are cross-signed or superseded versions of current roots (ISRG Root X1 cross-signed by
DST Root CA X3, the 2016 GTS Root R1 to R4) and Let's Encrypt intermediates (R3, R10, R11, E5, E6).
These counts were computed by hand with `openssl x509 -fingerprint`, because the harness only describes
sides it built.

What reads the file: blink's `TLSSettingsExtension.ca_list` defaults to `Resources.get('tls/ca.crt')`,
i.e. `share/blink/tls/ca.crt`. python3-sipsimple passes it to pjsip as the SIP-over-TLS `ca_file`, and
loads it into the account's GnuTLS `X509Credentials`, which MSRP over TLS uses. No behavioral shim: the
before side cannot be built without the overlay, and the TLS consumers are a SIP stack and GnuTLS
sessions, not a single HTTPS call.


## Java fixes that bundle or build a JRE (run against local fix branches)

Run on 2026-10-22 from `/` against the local nixpkgs checkout (several branches were not pushed
yet), so `--after` is a bare sha that the harness exports with `builtins.fetchGit` from `$CAH_REPO`:
`CAH_REPO=/home/rafael/nixpkgs nix run path:. -- <attr> --base 8915027df75d0403ef013dd0cbf09ff3c602fd03 --after <sha>`.
Cleaned outputs are `runs/<attr>.txt` in the gist.

Two harness changes came out of these runs:
- `ca-behave-check` now honours `--dry-run-only`. Before, `ca-check` passed the flag on and
  `ca-behave-check` took it for the attribute name (the real one came last and won), so a "dry run"
  of corretto21 started the whole matrix build.
- `ca-static-check` lists JAR signature blocks (`META-INF/*.RSA|DSA|EC`) on one line per side
  instead of judging them as stores (see "Rules for bad" in the README). They are PKCS#7 signatures
  with DigiCert code-signing chains; the scanner reads their DER as `pkcs12`. eclipse-java has 56
  as files (`features/*/META-INF/ECLIPSE_.RSA`) and 416 inside jars, identical before and after, and
  each one showed up as "pem: 0 certs readable", which made the first static verdict NOT FIXED.

### eclipses.eclipse-java (fix branch): static FIXED, behavioral PASS

`--after ff12820b84025631641ac710ea026f2d1f932c77` (`cacert/eclipses`, "eclipses: generate the bundled
JustJ JRE's cacerts from cacert"): `build-eclipse.nix` regenerates
`eclipse/plugins/org.eclipse.justj.openjdk.*/jre/lib/security/cacerts` with `jre-generate-cacerts`
(using the keytool of nixpkgs' `jdk25`, since the bundled JRE is not patched). eclipse-java 4.41 ships
JustJ `hotspot.jre.full.linux.x86_64_25.0.4`. First run 7:59 in total: the before side was built
(18 s), the after side was already in the store, and the matrix built the test-root eclipse-java once
(144 s, queue wait included). The re-run with the signature-block change, everything cached: 2:23.

```
| out:/eclipse/plugins/org.eclipse.justj.openjdk.hotspot.jre.full.linux.x86_64_25.0.4.v20260826-0822/jre/lib/security/cacerts | keystore 118 certs: 4 not in cacert, 1 in cacert but not for TLS, 5 cacert TLS roots missing [no-password]; scanner: ECC G3 | keystore 118 certs == cacert [no-password] |
jar signature blocks (META-INF/*.RSA|DSA|EC: code-signing certificate chains, not trust stores; not counted; listed in static/<side>/sigblocks.tsv):
  before 56 files + 416 in archives
  after 56 files + 416 in archives
VERDICT eclipses.eclipse-java: FIXED: before trusted CAs outside cacert; after: 1 store(s) == cacert, none with extra CAs

         | stock cacert | + test root  | override with test-root cacert
before   | REFUSED      | REFUSED      | NO-OP (package does not take cacert)
after    | REFUSED      | CONNECTED    | yes (rebuilt with cacert + test root)
control (before cells): curl --cacert test-root: CONNECTED, curl --cacert stock: REFUSED
VERDICT eclipses.eclipse-java: PASS: after-fix trust follows cacert; before-fix ignores it
```

- What this proves: Eclipse itself does not run on the JustJ JRE. `build-eclipse.nix` deletes the
  JustJ `-vm` line from `eclipse.ini` and the wrapper puts nixpkgs' `jdk` on `PATH`, so the IDE's own
  TLS (update sites, marketplace) uses nixpkgs' JDK store, which #576518 already wires to cacert. The
  run proves that the *bundled* JRE's store is wired to cacert. That matters for anything that
  launches that JRE.
- Shim (`shims/eclipses.eclipse-java.nix`, on the new shared `shims/bundled-jre.nix`): the TLS probe
  on `eclipse/plugins/org.eclipse.justj.openjdk.*/jre/bin/java` (the glob must match exactly one
  JRE). The package leaves that JRE unpatched (its interpreter is `/lib64/ld-linux-x86-64.so.2`, which
  the sandbox does not have), so the shim runs `bin/java` through nixpkgs' `ld-linux` with glibc and
  zlib on `--library-path`. The JVM still takes its `java.home` from `libjli.so`'s location: every cell
  prints `java.home=/nix/store/…-eclipse-java-4.41/eclipse/plugins/org.eclipse.justj.openjdk.hotspot.jre.full.linux.x86_64_25.0.4.v20260826-0822/jre trustStore=(default)`.
- Injection: the attr is `buildEclipseUnversioned` (`callPackage ./build-eclipse.nix { … }` in
  `eclipse/default.nix`) applied to per-edition data, so the derivation has no `.override` and the
  default injection would be a NO-OP. The shim re-evaluates `pkgs.eclipses.override { callPackage = … }`
  with a `callPackage` that also passes `cacert` to functions that declare it, and takes the same
  `pname`. It does so only when that side's `build-eclipse.nix` declares `cacert`; the base does not,
  so before-test is the before-stock derivation (NO-OP).
- Shim logs: the three refusing cells end in `SSLHandshakeException: (certificate_unknown) PKIX path
  building failed`; after-test prints `OK status=200 cipher=TLS_AES_256_GCM_SHA384`.
