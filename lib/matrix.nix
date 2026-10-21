# The four behavioral cells for one attr as one attrset, so the driver can build them with a
# single nixb invocation (one wait in the machine-wide build queue instead of four).
{
  beforeSrc,
  afterSrc,
  overlay ? "",
  attr,
  shim,
  fixtures,
  salt ? "",
}:
let
  cell =
    side: variant:
    import ./behave.nix {
      src = if side == "before" then beforeSrc else afterSrc;
      overlay = if side == "before" then "" else overlay;
      toolsSrc = beforeSrc;
      inherit attr shim fixtures salt variant;
    };
in
{
  before-stock = cell "before" "stock";
  before-test = cell "before" "test";
  after-stock = cell "after" "stock";
  after-test = cell "after" "test";
}
