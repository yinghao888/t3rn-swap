说明：T3RN自动SWAP脚本，据说单个地址SWAP上限奖励是2万个BRN。

当前支持arb和uni互刷。刷之前检查链上是否有对应的测试eth。

安装支持
```bash
pip install web3 eth_account
pip install --upgrade web3
```
创建脚本
```bash
nano t3rn.py
```
参数配置：只能修改私匙，跨链金额不能更改。

PRIVATE_KEY = "0x1234567890" #填写私钥


op_uni.py ARB<->UNI 互SWAP刷奖励

```bash
python3 t3rn.py
```

![image](https://github.com/user-attachments/assets/c86e0d08-5cc0-458e-b30a-10fd0402c792)

