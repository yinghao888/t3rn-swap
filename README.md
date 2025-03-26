说明：T3RN自动SWAP脚本，据说单个地址SWAP上限奖励是2万个BRN。

当前支持op和uni互刷。刷之前检查链上是否有对应的测试eth。

安装支持
```bash
pip install web3 eth_account
pip install --upgrade web3
```


参数配置：只能修改私匙和互跨次数，跨链金额不能更改。需要更改的请修改代码中对应的input data

PRIVATE_KEY = "0x1234567890" #填写私匙

AMOUNT_ETH = 1 # 每次跨链金额（单位：ETH）

TIMES = 1000 # 互跨来回次数

1 op_uni.py OP<->UNI 互SWAP刷奖励

```bash
python3 op_uni_03.py
```

