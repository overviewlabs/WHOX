# WHOX Release Process

## Quick release

```bash
cd /home/ubuntu/.hermes/hermes-agent
bash scripts/release-whox.sh 0.1.1 --publish-release
```

This will:

1. Update version in `pyproject.toml`
2. Update `__version__` and `__release_date__` in `whox_cli/__init__.py`
3. Create a release commit
4. Create and push tag `v<version>`
5. Optionally publish a GitHub release

## No GitHub release object

```bash
bash scripts/release-whox.sh 0.1.2
```

This pushes commit + tag only.
