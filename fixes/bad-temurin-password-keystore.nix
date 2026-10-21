# NEGATIVE CONTROL for the harness, not a fix: take the worktree's temurin-jre-bin fix and
# drop the JAVA_TOOL_OPTIONS that make keytool write a password-less PKCS12. The resulting
# cacerts contains exactly cacert's roots, but in password-encrypted cert bags, which the JDK
# (opening cacerts without a password) cannot see. Both checks should flag it.
# Usage: ca-{static,behave}-check --after-overlay fixes/bad-temurin-password-keystore.nix temurin-jre-bin
final: prev: {
  temurin-jre-bin = prev.temurin-jre-bin.overrideAttrs (o: {
    postFixup =
      let
        new = builtins.replaceStrings [
          ''JAVA_TOOL_OPTIONS="-Dkeystore.pkcs12.certProtectionAlgorithm=NONE -Dkeystore.pkcs12.macAlgorithm=NONE" \''
        ] [ "" ] o.postFixup;
      in
      assert new != o.postFixup; # fail loudly if the worktree fix changed shape
      new;
  });
}
