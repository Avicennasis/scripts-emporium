# Contributing to scripts-emporium

Thanks for considering a contribution. Bug reports, docs fixes, and small
improvements are all welcome.

## Dev setup

```bash
git clone https://github.com/Avicennasis/scripts-emporium.git
cd scripts-emporium
```

Each script is standalone — setup depends on which script you're
working on. See the script's own README for details.

## Running the tests

Script-specific — see individual READMEs.

## Code style

If a `.pre-commit-config.yaml` is present, run `pre-commit install` once,
then `pre-commit run --all-files` to check locally.

## PR checklist

- [ ] Tests added or updated and passing locally.
- [ ] `pre-commit run --all-files` is clean (if configured).
- [ ] README and docs updated if public behavior changed.
- [ ] `CHANGELOG.md` updated under `[Unreleased]`.

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md).
Be respectful; assume good faith.
