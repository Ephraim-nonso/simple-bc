```

forge create --rpc-url https://rpc.sepolia-api.lisk.com \
--etherscan-api-key 123 \
--verify \
--verifier blockscout \
--verifier-url https://sepolia-blockscout.lisk.com/api \
--private-key <PRIVATE_KEY> \
src/NFT.sol:NFT





forge create --rpc-url <your_rpc_url> \
    --constructor-args "ForgeUSD" "FUSD" 18 1000000000000000000000 \
    --private-key <your_private_key> \
    --etherscan-api-key <your_etherscan_api_key> \
    --verify \
    src/MyToken.sol:MyToken



    forge script --chain sepolia script/BondingCurve.s.sol:BondingCurveScript --rpc-url $SEPOLIA_LISK_RPC_URL --broadcast --verify --verifier blockscout --verifier-url https://sepolia-blockscout.lisk.com/api -vvvv

     forge verify-contract 0x085F4AF59d7568E8E7081d38a981E91eff9CB6cF \./src/BondingCurve.sol:BondingCurve \                                        
--chain 4202 \
--watch \
--verifier blockscout \
--verifier-url https://sepolia-blockscout.lisk.com/api

```