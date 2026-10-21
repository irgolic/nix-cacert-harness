# Not a fix: used with --after-overlay to test the cacert/julia-bin fix branch as is, minus its
# install check. That check runs Julia's whole test suite (one worker per CPU, not bounded by
# nixb's --cores) and would run twice (static after side, behavioral after-test). The fix is in
# installPhase (share/julia/cert.pem -> cacert); the install check does not touch that file.
# julia-bin, julia-stable-bin and julia-lts-bin are aliases of these attrs and follow them.
# overrideAttrs keeps the packages overridable, so the behavioral injection still reaches them.
final: prev:
prev.lib.genAttrs [ "julia_110-bin" "julia_111-bin" "julia_112-bin" "julia_113-bin" ] (
  a: prev.${a}.overrideAttrs { doInstallCheck = false; }
)
