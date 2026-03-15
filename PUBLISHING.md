# Publishing

## 1) Preflight checks

From plugin repo root:

```bash
cargo check
cargo package
```

## 2) Version bump

- Bump crate version in `Cargo.toml`.
- Commit and tag release:

```bash
git add .
git commit -m "release: vX.Y.Z"
git tag vX.Y.Z
git push origin main --tags
```

## 3) Publish Rust crate

```bash
cargo login
cargo publish
```

## 4) Post-publish verification

- Check package page on crates.io.
- Check docs build on docs.rs.
