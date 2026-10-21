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
