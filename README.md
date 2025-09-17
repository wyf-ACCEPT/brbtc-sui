## Deploy

```bash
sui move build
sui client publish

# then modify the `published-at` variable in `Move.toml`
```

## Upgrade

```bash
# make sure `published-at = "<package_id>"` and `brbtc = "0x0"` in `Move.toml`
sui client upgrade --upgrade-capability <upgrade_cap_id>
```