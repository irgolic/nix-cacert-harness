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
  - a custom `inject` in a shim;
  - an `--after-overlay` that *adds* a fix. Only the negative-control overlay was run.
- A global-overlay injection (`cacert = cacertTest` everywhere) was deliberately not done,
  because of the cost of the cascade.
- Only the two worked examples, the known-good sample and the negative control were run. The
  other ~60 campaign packages were not.
