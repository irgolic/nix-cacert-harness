# Not a fix under test: makes blink-qt's closure build again so the cacert/blink-qt branch can be
# checked (--after-overlay). On the base and on the fix branch, python3Packages.msrplib and
# python3Packages.xcaplib fail in pythonMetadataCheckPhase with "No package metadata was found for
# msrplib" (resp. xcaplib): upstream's project names are python3-msrplib and python3-xcaplib
# (wheels python3_msrplib-0.21.2, python3_xcaplib-2.0.2), the derivations' pnames are msrplib and
# xcaplib. The proper nixpkgs fix is to rename them like python3-sipsimple and python3-otr; here
# only pname is changed, which is what the check reads.
# python3Packages.python3-sipsimple fails too: the C that Cython 3.3.0 generates for _core.pyx calls
# __pyx_tp_new_vectorcall_..._BaseHeader (and others) without a declaration, which GCC rejects. It
# builds with cython_3_2, as preshed and levenshtein already do.
#
# Why pythonPackagesExtensions and not `python3 = prev.python3.override { packageOverrides = ...; }`:
# blink-qt takes the top-level python3Packages, which is `python314Packages` (= python314.pkgs),
# not `python3.pkgs`, so an override of `python3` never reaches it. The extension applies to
# every Python package set, and only these three packages and their dependents change.
final: prev: {
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (pyfinal: pyprev: {
      msrplib = pyprev.msrplib.overrideAttrs { pname = "python3-msrplib"; };
      xcaplib = pyprev.xcaplib.overrideAttrs { pname = "python3-xcaplib"; };
      python3-sipsimple = pyprev.python3-sipsimple.override { cython = pyfinal.cython_3_2; };
    })
  ];
}
