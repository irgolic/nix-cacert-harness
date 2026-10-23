# NOT a fix, and only meaningful on the machine where RESULTS.md's jabref run was made.
# The nix daemon there cannot build jabref: its build dir (/nix/var/nix/builds) is on the root
# tmpfs (13 GB, ~7.7 GB free) and the build needs ~12 GB. The fix branch's own .drv was therefore
# run outside the sandbox (`nix-shell <drv>` + genericBuild, build dir on disk), once as is and once
# as the matrix's after-test derivation (`jabref.override { cacert = <cacert + test root>; }`), and
# both outputs were imported with `nix store add`. This overlay (for `--after-overlay`, on the fix
# branch) makes `jabref` a copy of the first, and its `.override { cacert }` with the test-root
# cacert a copy of the second, so the static check and the behavioral cells run unchanged on them.
# The copies are rewritten from the out-of-sandbox $out to their own $out (wrapper scripts and the
# native-messaging manifest are the only files naming it), and get the same runtime references as
# Hydra's build of the base (gtk3, the jlinked JRE, postgresql, ...), found by Nix's usual scan.
final: prev:
let
  afterOut = "/nix/store/wvxzva3is0ck8yp2b4fqyp4q6ghp1s2n-jabref-6.0-alpha.6-oob-after";
  testOut = "/nix/store/xbbkspgrf407jcpalgvkl1v63scjr6px-jabref-6.0-alpha.6-oob-testroot";
  testCacert = "/nix/store/hv7n3g1zgw2wbsvkcdia495ybgqdqm02-nss-cacert-3.131.1";
  oobDir = {
    ${afterOut} = "/home/rafael/.cache/jabref-oob/out";
    ${testOut} = "/home/rafael/.cache/jabref-oob-testroot/out";
  };
  # runtime references of the out-of-sandbox output (same list as the base's narinfo References)
  refs = map builtins.storePath (
    builtins.filter (l: l != "") (prev.lib.splitString "\n" (builtins.readFile ./jabref-oob-refs.txt))
  );
  copy =
    p:
    prev.runCommand "jabref-6.0-alpha.6" { inherit refs; } ''
      cp -a --no-preserve=ownership ${builtins.storePath p} $out
      chmod -R u+w $out
      grep -rIl '${oobDir.${p}}' $out | while read -r f; do
        sed -i 's|${oobDir.${p}}|'"$out"'|g' "$f"
      done
    '';
  after = copy afterOut;
  test = copy testOut;
in
{
  jabref = after // {
    override =
      { cacert ? prev.cacert, ... }:
      if cacert.outPath == prev.cacert.outPath then
        after
      else if cacert.outPath == testCacert then
        test
      else
        throw "jabref-oob-standin: no out-of-sandbox build for cacert ${cacert.outPath}";
  };
}
