# Publish module

1. Calculate resource account address

```
ADDRESS=0xa23e4cf349015e4ed268e470b49ac52a96b276cdc2a21eb96457e8e24943de5b
SEED=idleplanet

aptos account derive-resource-account-address --address $ADDRESS --seed $SEED

# 0xb341640e53e3c8630129b2a1378e0060cf410be5622906f213b9b37941806320
```

2. Fund (if there is not enough gas) and Publish module to resource account

```
aptos move create-resource-account-and-publish-package --address-name $ADDRESS --seed $SEED --included-artifacts none
```

# Upgrade module

1. Generate the inputs for metadata_serialized and code

```
aptos move build-publish-payload --json-output-file upgrade.json
```

2. Update upgrade json function id to upgrade function of deployed module

```
0x1::code::publish_package_txn
-> 0xe1b8d0c21f8bbb07c3702b6dce8f52dd2d8d64cb95cb2d4589eda48bd39c4cba::idle_planet_access::upgrade
```

2. Deploy modified contract

```
aptos move run --json-file upgrade.json --included-artifacts none
```

# Call function

```
aptos move run \
    --json-file ./entries/call.json
```
